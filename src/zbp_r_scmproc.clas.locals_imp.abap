CLASS lhc_zr_scmproc DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS:
      get_global_authorizations FOR GLOBAL AUTHORIZATION
        IMPORTING
        REQUEST requested_authorizations FOR Procurement
        RESULT result,
      setProcurementId FOR DETERMINE ON MODIFY
        IMPORTING keys FOR Procurement~setProcurementId,
      determineExchangeRateTotal FOR DETERMINE ON MODIFY
        IMPORTING keys FOR Procurement~determineExchangeRateTotal,
      validateCurrencies FOR VALIDATE ON SAVE
        IMPORTING keys FOR Procurement~validateCurrencies,
      validateQuantityAndPrice FOR VALIDATE ON SAVE
        IMPORTING keys FOR Procurement~validateQuantityAndPrice.

    " ── Helpers ────────────────────────────────────────────────────────────
    " Lazy-initialised so the unit test can inject a double before first use.
    CLASS-DATA api_client TYPE REF TO zif_scm_exch_rate_api.
    CLASS-METHODS get_api_client RETURNING VALUE(result) TYPE REF TO zif_scm_exch_rate_api.

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
    RESULT DATA(procurements)
    FAILED DATA(failed_read).

    IF procurements IS INITIAL.
      RETURN.
    ENDIF.

    DATA update_table TYPE TABLE FOR UPDATE zr_scmproc\\Procurement.
    DATA(api) = get_api_client(  ).

    LOOP AT procurements ASSIGNING FIELD-SYMBOL(<procurement>).
      " Skip rows where the user has not yet filled in the required fields
      IF <procurement>-UnitPrice IS INITIAL
      OR <procurement>-Quantity IS INITIAL
      OR <procurement>-SourceCurrency IS INITIAL
      OR <procurement>-PreferredCurrency IS INITIAL.
        CONTINUE.
      ENDIF.


      TRY.
          DATA(exchange_rate) = api->get_exchange_rate(
              source_currency = <procurement>-SourceCurrency
              target_currency = <procurement>-PreferredCurrency
           ).

          DATA(total) = <procurement>-Quantity * CONV decfloat34( <procurement>-UnitPrice ) * exchange_rate.

          APPEND VALUE #(
            %tky = <procurement>-%tky
            ExchangeRate = exchange_rate
            TotalInPreferredCcy = CONV #( total )
            ApiMessage = |Rate: 1 { <procurement>-SourceCurrency } = { exchange_rate }|
                                  & |{ <procurement>-PreferredCurrency } (live from  open.er-api.com)|
           ) TO update_table.
        CATCH zcx_scm_api_error INTO DATA(api_error).
          " Write the error into ApiMessage so the UI can display it.
          " Do NOT raise or fail — the determination contract forbids rejection.
          APPEND VALUE #(
            %tky = <procurement>-%tky
            ExchangeRate          = 0
            TotalInPreferredCcy   = 0
            ApiMessage            = |⚠ { api_error->get_text( ) }|
           ) TO update_table.
      ENDTRY.

    ENDLOOP.

    " Push the calculated values back into the transactional buffer
    IF update_table IS NOT INITIAL.
      MODIFY ENTITIES OF zr_scmproc IN LOCAL MODE
      ENTITY Procurement
      UPDATE FIELDS ( ExchangeRate TotalInPreferredCcy RateFetchTimestamp ApiMessage )
      WITH update_table
      REPORTED DATA(reported_modify).
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
    RESULT DATA(procurements)
    FAILED DATA(failed_read).

    LOOP AT procurements INTO DATA(procurement).
      " Invalidate state messages
      APPEND VALUE #(
          %tky = procurement-%tky
          %state_area = 'VALIDATE_CURRENCIES'
       ) TO reported-procurement.

      IF procurement-SourceCurrency IS INITIAL.
        APPEND VALUE #( %tky = procurement-%tky ) TO failed-procurement.
        APPEND VALUE #(
            %tky = procurement-%tky
            %msg = new_message_with_text(
                severity = if_abap_behv_message=>severity-error
                text = 'Source currency must not be empty.'
             )
            %element-SourceCurrency = if_abap_behv=>mk-on
            %state_area = 'VALIDATE_CURRENCIES'
         ) TO reported-procurement.
        CONTINUE.
      ENDIF.

      IF procurement-PreferredCurrency IS INITIAL.
        APPEND VALUE #( %tky = procurement-%tky ) TO failed-procurement.
        APPEND VALUE #(
            %tky = procurement-%tky
            %msg = new_message_with_text(
                severity = if_abap_behv_message=>severity-error
                text = 'Preferred currency must not be empty.'
             )
            %element-PreferredCurrency = if_abap_behv=>mk-on
            %state_area = 'VALIDATE_CURRENCIES'
         ) TO reported-procurement.
        CONTINUE.
      ENDIF.

      IF procurement-SourceCurrency = procurement-PreferredCurrency.
        APPEND VALUE #( %tky = procurement-%tky ) TO failed-procurement.
        APPEND VALUE #(
            %tky = procurement-%tky
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

ENDCLASS.

















