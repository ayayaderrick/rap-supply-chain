"══════════════════════════════════════════════════════════════════════════════
" Status constants — single source of truth. Never use bare literals.
"══════════════════════════════════════════════════════════════════════════════
CLASS lsc_procurement_status DEFINITION FINAL.
  PUBLIC SECTION.
    CONSTANTS:
      open     TYPE zscm_overall_status VALUE 'O',
      approved TYPE zscm_overall_status VALUE 'A'.
ENDCLASS.

CLASS lsc_procurement_status IMPLEMENTATION.
ENDCLASS.

CLASS lhc_zr_scmproc DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS:
      get_global_authorizations FOR GLOBAL AUTHORIZATION
        IMPORTING
        REQUEST requested_authorizations FOR Procurement
        RESULT result,
      setProcurementId FOR DETERMINE ON SAVE
        IMPORTING keys FOR Procurement~setProcurementId,
      determineExchangeRateTotal FOR DETERMINE ON MODIFY
        IMPORTING keys FOR Procurement~determineExchangeRateTotal,
      validateCurrencies FOR VALIDATE ON SAVE
        IMPORTING keys FOR Procurement~validateCurrencies,
      validateQuantityAndPrice FOR VALIDATE ON SAVE
        IMPORTING keys FOR Procurement~validateQuantityAndPrice,
      refreshRate FOR MODIFY
        IMPORTING keys FOR ACTION Procurement~refreshRate RESULT result,
      approve FOR MODIFY
        IMPORTING keys FOR ACTION Procurement~approve RESULT result,
      setInitialStatus FOR DETERMINE ON MODIFY
        IMPORTING keys FOR Procurement~setInitialStatus,
      get_instance_features FOR INSTANCE FEATURES
        IMPORTING keys REQUEST requested_features FOR Procurement RESULT result.

    " ── Helpers ────────────────────────────────────────────────────────────
    " Lazy-initialised so the unit test can inject a double before first use.
    CLASS-DATA api_client TYPE REF TO zif_scm_exch_rate_api.
    CLASS-METHODS get_api_client RETURNING VALUE(result) TYPE REF TO zif_scm_exch_rate_api.

    " Shared rate-fetch logic used by both the determination and the action
    TYPES: ts_entity_result TYPE STRUCTURE FOR READ RESULT zr_scmproc\\Procurement.
    TYPES: ts_entity_update TYPE STRUCTURE FOR UPDATE zr_scmproc\\Procurement.
    CLASS-METHODS fetch_and_build_update
      IMPORTING procurement   TYPE ts_entity_result
      RETURNING VALUE(result) TYPE ts_entity_update
      RAISING   zcx_scm_api_error.


ENDCLASS.

CLASS lhc_zr_scmproc IMPLEMENTATION.
  METHOD get_global_authorizations.
  ENDMETHOD.
  METHOD setProcurementId.

    " Exit early if no keys are provided
    IF keys IS INITIAL.
      RETURN.
    ENDIF.

    " Read the newly created instances
    READ ENTITIES OF zr_scmproc IN LOCAL MODE
    ENTITY Procurement
    FIELDS ( ProcurementID ) WITH CORRESPONDING #( keys )
    RESULT DATA(procurements).

    " Filter out any records that already have a ProcurementID assigned
    DATA(procurements_wo_id) = procurements.
    DELETE procurements_wo_id WHERE ProcurementID IS NOT INITIAL.

    DATA(lv_quantity) = lines( procurements_wo_id ).
    DATA lv_start_id TYPE zscm_procurement_id.

    TRY.
        cl_numberrange_runtime=>number_get(
          EXPORTING
            nr_range_nr       = '01'
            object            = 'ZSCM_PRNR'
            quantity          = CONV #( lv_quantity )
          IMPORTING
            number            = DATA(lv_returned_number)
            returned_quantity = DATA(lv_returned_qty)
        ).

        " Calculate starting point (Assuming interval returns the last number of the block)
        lv_start_id = lv_returned_number - lv_returned_qty.

      CATCH cx_number_ranges INTO DATA(lx_number_ranges).
        " Modern RAP message handling from exception
        reported-procurement = VALUE #( FOR proc IN procurements_wo_id (
          procurementuuid = proc-ProcurementUUID
          %is_draft       = proc-%is_draft
          %msg            = new_message_with_text(
                              severity = if_abap_behv_message=>severity-error
                              text     = lx_number_ranges->get_text( )
                            )
        ) ).
        RETURN.
    ENDTRY.

    " Prepare the update sequence using EML
    DATA lt_update TYPE TABLE FOR UPDATE zr_scmproc.

    lt_update = VALUE #( FOR proc IN procurements_wo_id INDEX INTO lv_index (
      procurementuuid        = proc-ProcurementUUID
      %is_draft              = proc-%is_draft
      procurementid          = |{ ( lv_start_id + lv_index ) WIDTH = 8 PAD = '0' ALIGN = RIGHT }| " Ensures NUMC8 format
      %control-procurementid = if_abap_behv=>mk-on
    ) ).

    MODIFY ENTITIES OF zr_scmproc IN LOCAL MODE
    ENTITY Procurement
    UPDATE FIELDS ( ProcurementID ) WITH lt_update.

  ENDMETHOD.

  "────────────────────────────────────────────────────────────────────────────
  " Determination: fetch live exchange rate, calculate total.
  " Contract: NEVER rejects. Errors are written to ApiMessage so the user
  " can see what went wrong without being blocked from saving.
  "────────────────────────────────────────────────────────────────────────────
  METHOD determineExchangeRateTotal.

    READ ENTITIES OF zr_scmproc IN LOCAL MODE
    ENTITY Procurement
    FIELDS ( UnitPrice Quantity SourceCurrency PreferredCurrency )
    WITH CORRESPONDING #( keys )
    RESULT DATA(lt_procurement)
    FAILED DATA(lt_failed_read).

    IF lt_procurement IS INITIAL.
      RETURN.
    ENDIF.

    DATA lt_updates TYPE TABLE FOR UPDATE zr_scmproc\\Procurement.
    DATA(api) = get_api_client(  ).

    LOOP AT lt_procurement ASSIGNING FIELD-SYMBOL(<procurement>).
      " Skip rows where the user has not yet filled in the required fields
      IF <procurement>-UnitPrice IS INITIAL
      OR <procurement>-Quantity IS INITIAL
      OR <procurement>-SourceCurrency IS INITIAL
      OR <procurement>-PreferredCurrency IS INITIAL.
        CONTINUE.
      ENDIF.


      TRY.
          DATA(lv_exchange_rate) = api->get_exchange_rate(
              source_currency = <procurement>-SourceCurrency
              target_currency = <procurement>-PreferredCurrency
           ).

          DATA(lv_total) = <procurement>-Quantity * CONV decfloat34( <procurement>-UnitPrice ) * lv_exchange_rate.

          APPEND VALUE #(
            %tky = <procurement>-%tky
            ExchangeRate = lv_exchange_rate
            TotalInPreferredCcy = CONV #( lv_total )
            ApiMessage = |Rate: 1 { <procurement>-SourceCurrency } = { lv_exchange_rate }|
                                  & |{ <procurement>-PreferredCurrency } (live from  open.er-api.com)|
           ) TO lt_updates.
        CATCH zcx_scm_api_error INTO DATA(api_error).
          " Write the error into ApiMessage so the UI can display it.
          " Do NOT raise or fail — the determination contract forbids rejection.
          APPEND VALUE #(
            %tky = <procurement>-%tky
            ExchangeRate          = 0
            TotalInPreferredCcy   = 0
            ApiMessage            = |⚠ { api_error->get_text( ) }|
           ) TO lt_updates.
      ENDTRY.

    ENDLOOP.

    " Push the calculated values back into the transactional buffer
    IF lt_updates IS NOT INITIAL.
      MODIFY ENTITIES OF zr_scmproc IN LOCAL MODE
      ENTITY Procurement
      UPDATE FIELDS ( ExchangeRate TotalInPreferredCcy RateFetchTimestamp ApiMessage )
      WITH lt_updates
      REPORTED DATA(lt_reported_modify).
    ENDIF.

  ENDMETHOD.

  "────────────────────────────────────────────────────────────────────────────
  " Helper: lazy-init the API client.
  " Unit tests set api_client to a test double before calling behavior methods.
  "────────────────────────────────────────────────────────────────────────────
  METHOD get_api_client.
    IF api_client IS INITIAL.
      api_client = zcl_scm_exch_rate_api=>create(  ).
    ENDIF.
    result = api_client.
  ENDMETHOD.


  "────────────────────────────────────────────────────────────────────────────
  " Validation: currencies must be different and non-empty.
  "────────────────────────────────────────────────────────────────────────────
  METHOD validateCurrencies.

    READ ENTITIES OF zr_scmproc IN LOCAL MODE
    ENTITY Procurement
    FIELDS ( SourceCurrency PreferredCurrency )
    WITH CORRESPONDING #( keys )
    RESULT DATA(lt_procurement)
    FAILED DATA(lt_failed).

    failed = CORRESPONDING #( DEEP lt_failed ).

    LOOP AT lt_procurement INTO DATA(ls_procurement).
      " Invalidate state messages
      APPEND VALUE #(
          %tky = ls_procurement-%tky
          %state_area = 'VALIDATE_CURRENCIES'
       ) TO reported-procurement.

      IF ls_procurement-SourceCurrency IS INITIAL.
        APPEND VALUE #( %tky = ls_procurement-%tky ) TO failed-procurement.
        APPEND VALUE #(
            %tky = ls_procurement-%tky
            %msg = new_message_with_text(
                severity = if_abap_behv_message=>severity-error
                text = 'Source currency must not be empty.'
             )
            %element-SourceCurrency = if_abap_behv=>mk-on
            %state_area = 'VALIDATE_CURRENCIES'
         ) TO reported-procurement.
        CONTINUE.
      ENDIF.

      IF ls_procurement-PreferredCurrency IS INITIAL.
        APPEND VALUE #( %tky = ls_procurement-%tky ) TO failed-procurement.
        APPEND VALUE #(
            %tky = ls_procurement-%tky
            %msg = new_message_with_text(
                severity = if_abap_behv_message=>severity-error
                text = 'Preferred currency must not be empty.'
             )
            %element-PreferredCurrency = if_abap_behv=>mk-on
            %state_area = 'VALIDATE_CURRENCIES'
         ) TO reported-procurement.
        CONTINUE.
      ENDIF.

      IF ls_procurement-SourceCurrency = ls_procurement-PreferredCurrency.
        APPEND VALUE #( %tky = ls_procurement-%tky ) TO failed-procurement.
        APPEND VALUE #(
            %tky = ls_procurement-%tky
            %msg = new_message_with_text(
                severity = if_abap_behv_message=>severity-error
                text = |Source and preferred currency cannot be the same. Choose a different target currency|
             )
            %element-SourceCurrency = if_abap_behv=>mk-on
            %element-PreferredCurrency = if_abap_behv=>mk-on
            %state_area = 'VALIDATE_CURRENCIES'
         ) TO reported-procurement.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  "────────────────────────────────────────────────────────────────────────────
  " Validation: quantity and unit price must be positive.
  "────────────────────────────────────────────────────────────────────────────
  METHOD validateQuantityAndPrice.

    READ ENTITIES OF zr_scmproc IN LOCAL MODE
    ENTITY Procurement
    FIELDS ( Quantity UnitPrice )
    WITH CORRESPONDING #( keys )
    RESULT DATA(lt_procurement)
    FAILED DATA(lt_failed).

    failed = CORRESPONDING #( DEEP lt_failed ).

    LOOP AT lt_procurement INTO DATA(ls_procurement).
      " Invalidate state messages
      APPEND VALUE #(
          %tky = ls_procurement-%tky
          %state_area = 'VALIDATE_QTY_PRICE'
       ) TO reported-procurement.

      IF ls_procurement-Quantity <= 0.
        APPEND VALUE #( %tky = ls_procurement-%tky ) TO failed-procurement.
        APPEND VALUE #(
            %tky = ls_procurement-%tky
            %msg = new_message_with_text(
                severity = if_abap_behv_message=>severity-error
                text = 'Quantity must be greater than zero.'
             )
            %element-Quantity = if_abap_behv=>mk-on
            %state_area = 'VALIDATE_QTY_PRICE'
         ) TO reported-procurement.
      ENDIF.

      IF ls_procurement-UnitPrice <= 0.
        APPEND VALUE #( %tky = ls_procurement-%tky ) TO failed-procurement.
        APPEND VALUE #(
            %tky = ls_procurement-%tky
            %msg = new_message_with_text(
                severity = if_abap_behv_message=>severity-error
                text = 'Unit price must be greater than zero.'
             )
            %element-UnitPrice = if_abap_behv=>mk-on
            %state_area = 'VALIDATE_QTY_PRICE'
         ) TO reported-procurement.
      ENDIF.
    ENDLOOP.


  ENDMETHOD.


  "────────────────────────────────────────────────────────────────────────────
  " Action: RefreshRate
  " Re-fetches the live exchange rate on demand. Reports errors via the
  " RAP message framework so the user sees them as Fiori toast messages.
  "────────────────────────────────────────────────────────────────────────────
  METHOD refreshRate.

    READ ENTITIES OF zr_scmproc IN LOCAL MODE
    ENTITY Procurement
    FIELDS ( UnitPrice Quantity SourceCurrency PreferredCurrency )
    WITH CORRESPONDING #( keys )
    RESULT DATA(lt_procurement)
    FAILED DATA(lt_failed_read).

    failed = CORRESPONDING #( DEEP lt_failed_read ).

    DATA lt_updates TYPE TABLE FOR UPDATE zr_scmproc\\Procurement.

    LOOP AT lt_procurement INTO DATA(ls_procurement).
      IF ls_procurement-SourceCurrency IS INITIAL OR ls_procurement-PreferredCurrency IS INITIAL.
        APPEND VALUE #( %tky = ls_procurement-%tky ) TO failed-procurement.
        APPEND VALUE #(
            %tky = ls_procurement-%tky
            %msg = new_message_with_text(
                severity = if_abap_behv_message=>severity-error
                text = 'Cannot refresh rate: source and preferred currency must be filled first.'
             )
         ) TO reported-procurement.
      ENDIF.
      CONTINUE.

      TRY.
          APPEND fetch_and_build_update( ls_procurement ) TO lt_updates.
        CATCH zcx_scm_api_error INTO DATA(api_error).
          APPEND VALUE #( %tky = ls_procurement-%tky ) TO failed-procurement.
          APPEND VALUE #(
              %tky = ls_procurement-%tky
              %msg = new_message_with_text(
                  severity = if_abap_behv_message=>severity-error
                  text = api_error->get_text(  )
               )
           ) TO reported-procurement.
          CONTINUE.
      ENDTRY.
    ENDLOOP.

    CHECK lt_updates IS NOT INITIAL.

    MODIFY ENTITIES OF zr_scmproc IN LOCAL MODE
    ENTITY Procurement
    UPDATE FIELDS ( ExchangeRate TotalInPreferredCcy RateFetchTimestamp ApiMessage )
    WITH lt_updates
    REPORTED DATA(lt_reported_modify).

    " Return the updated entities as the action result
    READ ENTITIES OF zr_scmproc IN LOCAL MODE
    ENTITY Procurement
    ALL FIELDS WITH CORRESPONDING #( lt_updates )
    RESULT DATA(lt_updated_entities)
    FAILED DATA(lt_failed_read2).

    failed = CORRESPONDING #( DEEP lt_failed_read2 ).

    result = VALUE #( FOR entity IN lt_updated_entities (
        %tky = entity-%tky
        %param = CORRESPONDING #( entity )
    ) ).

  ENDMETHOD.

  "────────────────────────────────────────────────────────────────────────────
  " Shared helper: call the API and build an update row.
  " Raised zcx_scm_api_error propagates to the caller; it decides how
  " to surface it (determination → ApiMessage, action → reported message).
  "────────────────────────────────────────────────────────────────────────────
  METHOD fetch_and_build_update.

    DATA(lv_exchange_rate) = get_api_client(  )->get_exchange_rate(
        source_currency = procurement-SourceCurrency
        target_currency = procurement-PreferredCurrency
     ).

    DATA(lv_total) = procurement-Quantity * CONV decfloat34( procurement-UnitPrice ) * lv_exchange_rate.

    result = VALUE #(
       %tky = procurement-%tky
       ExchangeRate = lv_exchange_rate
       TotalInPreferredCcy = CONV #( lv_total )
       RateFetchTimestamp = cl_abap_context_info=>get_system_time( )
       ApiMessage = |Rate Fetched: 1 { procurement-SourceCurrency } = { lv_exchange_rate }|
                                 & |{ procurement-PreferredCurrency } (live from  open.er-api.com)|
     ).

  ENDMETHOD.

  "────────────────────────────────────────────────────────────────────────────
  " Action: Approve
  " Transitions OverallStatus from Open → Approved.
  " Rejects if no valid exchange rate has been fetched yet.
  "────────────────────────────────────────────────────────────────────────────
  METHOD approve.

    READ ENTITIES OF zr_scmproc IN LOCAL MODE
    ENTITY Procurement
    FIELDS ( OverallStatus ExchangeRate TotalInPreferredCcy )
    WITH CORRESPONDING #( keys )
    RESULT DATA(lt_procurement)
    FAILED DATA(lt_failed_read).

    failed = CORRESPONDING #( DEEP lt_failed_read ).

    DATA lt_updates TYPE TABLE FOR UPDATE zr_scmproc\\Procurement.

    LOOP AT lt_procurement INTO DATA(ls_procurement).
      IF ls_procurement-ExchangeRate IS INITIAL OR ls_procurement-ExchangeRate = 0.
        APPEND VALUE #( %tky = ls_procurement-%tky ) TO failed-procurement.
        APPEND VALUE #(
            %tky = ls_procurement-%tky
            %msg = new_message_with_text(
                severity = if_abap_behv_message=>severity-error
                text = 'Cannot approve: no exchange rate has been fetched. '
                        && 'Enter source and preferred currency and wait for the '
                        && 'rate to appear, or click Refresh Rate.'
             )
         ) TO reported-procurement.
        CONTINUE.
      ENDIF.

      APPEND VALUE #(
        %tky = ls_procurement-%tky
        OverallStatus = lsc_procurement_status=>approved
       ) TO lt_updates.
    ENDLOOP.

    CHECK lt_updates IS NOT INITIAL.

    MODIFY ENTITIES OF zr_scmproc IN LOCAL MODE
    ENTITY Procurement
    UPDATE FIELDS ( OverallStatus )
    WITH lt_updates
    REPORTED DATA(lt_reported_modify).

    " Return the updated entities
    READ ENTITIES OF zr_scmproc IN LOCAL MODE
    ENTITY Procurement
    ALL FIELDS WITH CORRESPONDING #( lt_updates )
    RESULT DATA(lt_updated_entities)
    FAILED DATA(lt_failed_read2).

    failed = CORRESPONDING #( DEEP lt_failed_read2 ).

    result = VALUE #( FOR entity IN lt_updated_entities (
        %tky = entity-%tky
        %param = CORRESPONDING #( entity )
     ) ).

  ENDMETHOD.

  "────────────────────────────────────────────────────────────────────────────
  " Determination: setInitialStatus
  " Automatically sets OverallStatus to Open for new instances.
  "────────────────────────────────────────────────────────────────────────────
  METHOD setInitialStatus.

    IF keys IS INITIAL.
      RETURN.
    ENDIF.

    READ ENTITIES OF zr_scmproc IN LOCAL MODE
    ENTITY Procurement
    FIELDS ( OverallStatus )
    WITH CORRESPONDING #( keys )
    RESULT DATA(lt_procurement).

    DELETE lt_procurement WHERE OverallStatus IS NOT INITIAL.
    CHECK lt_procurement IS NOT INITIAL.

    MODIFY ENTITIES OF zr_scmproc IN LOCAL MODE
    ENTITY Procurement
    UPDATE FIELDS ( OverallStatus )
    WITH VALUE #( FOR line IN lt_procurement ( %tky = line-%tky OverallStatus = lsc_procurement_status=>open ) )
    REPORTED DATA(lt_update_reported).

    reported = CORRESPONDING #( DEEP lt_update_reported ).

  ENDMETHOD.

  METHOD get_instance_features.

    READ ENTITIES OF zr_scmproc IN LOCAL MODE
    ENTITY Procurement
    FIELDS ( OverallStatus ExchangeRate SourceCurrency PreferredCurrency )
    WITH CORRESPONDING #( keys )
    RESULT DATA(lt_procurement)
    FAILED DATA(lt_failed_read).

    failed = CORRESPONDING #( DEEP lt_failed_read ).

    result = VALUE #( FOR line IN lt_procurement (
        %tky = line-%tky
        %action-Edit = COND #( WHEN line-OverallStatus = lsc_procurement_status=>approved
                               THEN if_abap_behv=>fc-o-disabled
                               ELSE if_abap_behv=>fc-o-enabled )
        %action-approve = COND #( WHEN line-OverallStatus = lsc_procurement_status=>open
                                  AND line-ExchangeRate IS NOT INITIAL
                                  AND line-ExchangeRate <> 0
                                  THEN if_abap_behv=>fc-o-enabled
                                  ELSE if_abap_behv=>fc-o-disabled )
        %action-refreshRate = cond #( when line-OverallStatus = lsc_procurement_status=>open
                                      and line-SourceCurrency is not initial
                                      and line-PreferredCurrency is not initial
                                      then if_abap_behv=>fc-o-enabled
                                      else if_abap_behv=>fc-o-disabled )
     ) ).

  ENDMETHOD.

ENDCLASS.

















