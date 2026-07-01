"══════════════════════════════════════════════════════════════════════════════
" Test double for the exchange rate API — returns hardcoded rates
"══════════════════════════════════════════════════════════════════════════════
CLASS ltd_exchange_rate_api DEFINITION FINAL.
  PUBLIC SECTION.
    INTERFACES zif_scm_exch_rate_api.
    DATA simulated_rate  TYPE decfloat34.
    DATA should_fail     TYPE abap_bool.
ENDCLASS.

CLASS ltd_exchange_rate_api IMPLEMENTATION.
  METHOD zif_scm_exch_rate_api~get_exchange_rate.
    IF should_fail = abap_true.
      RAISE EXCEPTION NEW zcx_scm_api_error( error_message = 'Simulated API failure' ).
    ENDIF.
    result = simulated_rate.
  ENDMETHOD.
ENDCLASS.

"! @testing BDEF:ZR_SCMPROC
CLASS ltc_procurement DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    CLASS-DATA cds_environment TYPE REF TO if_cds_test_environment.
    CLASS-DATA api_double       TYPE REF TO ltd_exchange_rate_api.

    "! Instantiate class under test and setup test double frameworks
    CLASS-METHODS class_setup    RAISING cx_static_check.
    "! Destroy test environments and test doubles
    CLASS-METHODS class_teardown.
    METHODS:
      "! Reset test doubles
      setup,
      "! Reset transactional buffer
      teardown,

      "! Check total of order instance
      determination_calculate_total         FOR TESTING,
      "! Check returned API message in case of api error
      determination_handle_api_error        FOR TESTING,
      "! Check empty currency field
      determination_skip_empty_field        FOR TESTING,
      "! Check source and target currency are not same
      validation_reject_same_curr           FOR TESTING,
      "! Check quantity field is not zero
      validation_reject_zero_quan           FOR TESTING,
      "! Check price field is not zero
      validation_rejects_zero_price         FOR TESTING,
      "! Check fields are updated
      action_updates_fields                 FOR TESTING,
      "! Check for api error message
      action_fails_on_error                 FOR TESTING,
      "! Check status change on action
      approve_action_changes_status         FOR TESTING,
      "! Check action disabled without rate
      approve_action_blocked_wo_rate        FOR TESTING,
      "! Check new instance has status 'Open'
      feature_ctrl_open_enables_edit        FOR TESTING,
      "! Check approve action disables editing
      ft_ctrl_approved_locks_fields         FOR TESTING.

    " Helper: create a procurement record and return its UUID
    METHODS create_test_procurement
      IMPORTING procurement_id    TYPE zscm_procurement_id
                source_currency   TYPE waers
                preferred_ccy     TYPE waers
                quantity          TYPE zscm_quantity
                unit_price        TYPE zscm_unit_price
      RETURNING VALUE(result_key) TYPE zr_scmproc-ProcurementUuid.


ENDCLASS.


CLASS ltc_procurement IMPLEMENTATION.



  METHOD class_setup.
    cds_environment = cl_cds_test_environment=>create( i_for_entity = 'ZR_SCMPROC' ).
    api_double = NEW ltd_exchange_rate_api(  ).
    lhc_zr_scmproc=>api_client = api_double.
  ENDMETHOD.

  METHOD class_teardown.
    cds_environment->destroy(  ).
  ENDMETHOD.

  METHOD setup.
    cds_environment->clear_doubles(  ).
    api_double->should_fail = abap_false.
    api_double->simulated_rate = '1.2'.  " 1 USD = 1.2 EUR (default)
  ENDMETHOD.

  METHOD teardown.
    ROLLBACK ENTITIES.
  ENDMETHOD.

  "──────────────────────────────────────────────────────────────────────────
  " Helper: create a procurement entity in the transactional buffer
  " and return its generated UUID so tests can READ it afterwards.
  "──────────────────────────────────────────────────────────────────────────
  METHOD create_test_procurement.

    MODIFY ENTITIES OF zr_scmproc IN LOCAL MODE
    ENTITY Procurement
    CREATE FIELDS ( MaterialName SourceCurrency PreferredCurrency
                        Quantity UnitPrice )
    WITH VALUE #( (
        %cid = procurement_id
        MaterialName      = |Material { procurement_id }|
        SourceCurrency    = source_currency
        PreferredCurrency = preferred_ccy
        Quantity          = quantity
        UnitPrice         = unit_price
     ) )
     MAPPED DATA(mapped)
     FAILED DATA(failed)
     REPORTED DATA(reported).

    IF mapped-procurement IS NOT INITIAL.
      " Retrieve the UUID assigned by managed numbering
      result_key = mapped-procurement[ 1 ]-ProcurementUUID.
    ELSE.
      cl_abap_unit_assert=>fail( msg = 'EML Create failed to produce a valid mapped UUID' ).
    ENDIF.

  ENDMETHOD.

  METHOD determination_calculate_total.

    api_double->simulated_rate = '1.2'.

    DATA(uuid) = create_test_procurement(
        procurement_id  = '01'
        source_currency = 'USD'
        preferred_ccy   = 'EUR'
        quantity        = '10'
        unit_price      = '100'
     ).

    READ ENTITIES OF zr_scmproc IN LOCAL MODE
    ENTITY Procurement
    FIELDS ( TotalInPreferredCcy ExchangeRate ApiMessage )
    WITH VALUE #( ( ProcurementUUID = uuid ) )
    RESULT DATA(lt_results).

    DATA(ls_result) = lt_results[ 1 ].
    cl_abap_unit_assert=>assert_equals(
    msg = 'Total should be Qty × Price × Rate = 10 × 100 × 1.2 = 1200'
    exp = CONV zscm_total_in_preferred_ccy( '1200' )
    act = ls_result-TotalInPreferredCcy ).

    cl_abap_unit_assert=>assert_equals(
    msg = 'ExchangeRate should reflect the simulated rate'
    exp = CONV zscm_exchange_rate( '1.2' )
    act = ls_result-ExchangeRate ).

    cl_abap_unit_assert=>assert_not_initial(
    msg = 'ApiMessage should contain the rate description'
    act = ls_result-ApiMessage ).

  ENDMETHOD.

  METHOD determination_handle_api_error.

    api_double->should_fail = abap_true.

    DATA(uuid) = create_test_procurement(
      procurement_id  = '02'
      source_currency = 'USD'
      preferred_ccy   = 'EUR'
      quantity        = '5'
      unit_price      = '200' ).

    READ ENTITIES OF zr_scmproc IN LOCAL MODE
      ENTITY Procurement
        FIELDS ( TotalInPreferredCcy ExchangeRate ApiMessage )
        WITH VALUE #( ( ProcurementUUID = uuid ) )
      RESULT DATA(results).

    DATA(row) = results[ 1 ].
    cl_abap_unit_assert=>assert_equals(
      exp = CONV zscm_total_in_preferred_ccy( '0' )
      act = row-TotalInPreferredCcy
      msg = 'Total must be 0 when API fails' ).

    cl_abap_unit_assert=>assert_not_initial(
      act = row-ApiMessage
      msg = 'ApiMessage must contain the error description' ).

  ENDMETHOD.

  METHOD determination_skip_empty_field.

    MODIFY ENTITIES OF zr_scmproc IN LOCAL MODE
      ENTITY Procurement
        CREATE FIELDS (  MaterialName Quantity UnitPrice )
        WITH VALUE #( ( %cid            = 'SKIP_TEST'
                        ProcurementId   = '03'
                        MaterialName    = 'Test Material'
                        Quantity        = '1'
                        UnitPrice       = '50'
                        " SourceCurrency and PreferredCurrency intentionally empty
                      ) )
      MAPPED   DATA(mapped)
      FAILED   DATA(failed)
      REPORTED DATA(reported).

    " No failures expected from the determination itself
    cl_abap_unit_assert=>assert_initial(
      act = failed-Procurement
      msg = 'Determination must not fail when currency fields are empty' ).

  ENDMETHOD.

  METHOD validation_rejects_zero_price.

    MODIFY ENTITIES OF zr_scmproc IN LOCAL MODE
     ENTITY Procurement
       CREATE FIELDS ( MaterialName SourceCurrency PreferredCurrency
                       Quantity UnitPrice )
       WITH VALUE #( ( %cid              = 'ZERO_PRICE'
                       ProcurementId     = '06'
                       MaterialName      = 'Aluminium Sheet'
                       SourceCurrency    = 'EUR'
                       PreferredCurrency = 'GBP'
                       Quantity          = '5'
                       UnitPrice         = '0' ) )   " invalid
     MAPPED   DATA(mapped)
     FAILED   DATA(failed_create)
     REPORTED DATA(reported_create).

    COMMIT ENTITIES
      RESPONSE OF zr_scmproc
      FAILED   DATA(failed_save)
      REPORTED DATA(reported_save).

    cl_abap_unit_assert=>assert_not_initial(
      act = failed_save-Procurement
      msg = 'Validation must reject zero unit price' ).

  ENDMETHOD.

  METHOD validation_reject_same_curr.

    MODIFY ENTITIES OF zr_scmproc IN LOCAL MODE
      ENTITY Procurement
        CREATE FIELDS (  MaterialName SourceCurrency PreferredCurrency
                        Quantity UnitPrice )
        WITH VALUE #( ( %cid               = 'SAME_CCY'
                        ProcurementId      = '04'
                        MaterialName       = 'Copper Wire'
                        SourceCurrency     = 'USD'
                        PreferredCurrency  = 'USD'    " same — must be rejected
                        Quantity           = '10'
                        UnitPrice          = '50' ) )
      MAPPED   DATA(mapped)
      FAILED   DATA(failed_create)
      REPORTED DATA(reported_create).

    COMMIT ENTITIES
      RESPONSE OF zr_scmproc
      FAILED   DATA(failed_save)
      REPORTED DATA(reported_save).

    cl_abap_unit_assert=>assert_not_initial(
      act = failed_save-Procurement
      msg = 'Validation must reject identical source and preferred currency' ).

  ENDMETHOD.

  METHOD validation_reject_zero_quan.
    MODIFY ENTITIES OF zr_scmproc IN LOCAL MODE
      ENTITY Procurement
        CREATE FIELDS (  MaterialName SourceCurrency PreferredCurrency
                        Quantity UnitPrice )
        WITH VALUE #( ( %cid              = 'ZERO_QTY'
                        ProcurementId     = '05'
                        MaterialName      = 'Steel Rod'
                        SourceCurrency    = 'USD'
                        PreferredCurrency = 'EUR'
                        Quantity          = '0'     " invalid
                        UnitPrice         = '25' ) )
      MAPPED   DATA(mapped)
      FAILED   DATA(failed_create)
      REPORTED DATA(reported_create).

    COMMIT ENTITIES
      RESPONSE OF zr_scmproc
      FAILED   DATA(failed_save)
      REPORTED DATA(reported_save).

    cl_abap_unit_assert=>assert_not_initial(
      act = failed_save-Procurement
      msg = 'Validation must reject zero quantity' ).
  ENDMETHOD.

  METHOD action_updates_fields.

    api_double->simulated_rate = '1.5'.

    DATA(uuid) = create_test_procurement(
      procurement_id  = '10'
      source_currency = 'USD'
      preferred_ccy   = 'GBP'
      quantity        = '20'
      unit_price      = '50' ).

    " Manually zero out ExchangeRate to simulate stale data
    MODIFY ENTITIES OF zr_scmproc IN LOCAL MODE
      ENTITY Procurement
        UPDATE FIELDS ( ExchangeRate TotalInPreferredCcy ApiMessage )
        WITH VALUE #( ( ProcurementUUID = uuid
                        ExchangeRate          = 0
                        TotalInPreferredCcy   = 0
                        ApiMessage            = 'old message' ) )
      REPORTED DATA(reported_zero).

    " Invoke the RefreshRate action
    MODIFY ENTITIES OF zr_scmproc IN LOCAL MODE
      ENTITY Procurement
        EXECUTE RefreshRate
          FROM VALUE #( ( ProcurementUuid = uuid ) )
      RESULT   DATA(action_result)
      REPORTED DATA(reported_action)
      FAILED   DATA(failed_action).

    cl_abap_unit_assert=>assert_initial(
      act = failed_action-Procurement
      msg = 'RefreshRate action must not fail for a valid procurement' ).

    " Verify the entity was updated
    READ ENTITIES OF zr_scmproc IN LOCAL MODE
      ENTITY Procurement
        FIELDS ( ExchangeRate TotalInPreferredCcy )
        WITH VALUE #( ( ProcurementUUID = uuid ) )
      RESULT DATA(lt_results).

    DATA(ls_result) = lt_results[ 1 ].
    cl_abap_unit_assert=>assert_equals(
      exp = CONV zscm_exchange_rate( '1.5' )
      act = ls_result-ExchangeRate
      msg = 'ExchangeRate must be updated to the simulated rate' ).

    cl_abap_unit_assert=>assert_equals(
      exp = CONV zscm_total_in_preferred_ccy( '1500' )   " 20 × 50 × 1.5
      act = ls_result-TotalInPreferredCcy
      msg = 'Total must be Qty × Price × Rate = 20 × 50 × 1.5 = 1500' ).

  ENDMETHOD.

  METHOD action_fails_on_error.

    api_double->should_fail = abap_true.

    DATA(uuid) = create_test_procurement(
      procurement_id  = '011'
      source_currency = 'EUR'
      preferred_ccy   = 'JPY'
      quantity        = '10'
      unit_price      = '100' ).

    MODIFY ENTITIES OF zr_scmproc IN LOCAL MODE
      ENTITY Procurement
        EXECUTE RefreshRate
          FROM VALUE #( ( ProcurementUUID = uuid ) )
      RESULT   DATA(action_result)
      REPORTED DATA(reported_action)
      FAILED   DATA(failed_action).

    cl_abap_unit_assert=>assert_not_initial(
      act = failed_action-Procurement
      msg = 'RefreshRate must fail and surface error when API is unavailable' ).

    cl_abap_unit_assert=>assert_not_initial(
      act = reported_action-Procurement
      msg = 'A user-visible error message must be reported' ).

  ENDMETHOD.

  METHOD approve_action_changes_status.

    api_double->simulated_rate = '1.2'.

    DATA(uuid) = create_test_procurement(
      procurement_id  = '012'
      source_currency = 'USD'
      preferred_ccy   = 'EUR'
      quantity        = '5'
      unit_price      = '200' ).

    " Approve the procurement
    MODIFY ENTITIES OF zr_scmproc IN LOCAL MODE
      ENTITY Procurement
        EXECUTE Approve
          FROM VALUE #( ( ProcurementUUID = uuid ) )
      RESULT   DATA(action_result)
      REPORTED DATA(reported_action)
      FAILED   DATA(failed_action).

    cl_abap_unit_assert=>assert_initial(
      act = failed_action-Procurement
      msg = 'Approve action must succeed when a valid rate is present' ).

    " Verify status changed to Approved
    READ ENTITIES OF zr_scmproc IN LOCAL MODE
      ENTITY Procurement
        FIELDS ( OverallStatus )
        WITH VALUE #( ( ProcurementUUID = uuid ) )
      RESULT DATA(results).

    cl_abap_unit_assert=>assert_equals(
      exp = lsc_procurement_status=>approved
      act = results[ 1 ]-OverallStatus
      msg = 'OverallStatus must be Approved after the Approve action' ).

  ENDMETHOD.

  METHOD approve_action_blocked_wo_rate.

    " Create a procurement but set ExchangeRate to 0 explicitly
    DATA(uuid) = create_test_procurement(
      procurement_id  = '013'
      source_currency = 'USD'
      preferred_ccy   = 'EUR'
      quantity        = '5'
      unit_price      = '100' ).

    MODIFY ENTITIES OF zr_scmproc IN LOCAL MODE
      ENTITY Procurement
        UPDATE FIELDS ( ExchangeRate )
        WITH VALUE #( ( ProcurementUuid = uuid  ExchangeRate = 0 ) )
      REPORTED DATA(reported_zero).

    MODIFY ENTITIES OF zr_scmproc IN LOCAL MODE
      ENTITY Procurement
        EXECUTE Approve
          FROM VALUE #( ( ProcurementUuid = uuid ) )
      RESULT   DATA(action_result)
      REPORTED DATA(reported_action)
      FAILED   DATA(failed_action).

    cl_abap_unit_assert=>assert_not_initial(
      act = failed_action-Procurement
      msg = 'Approve must be rejected when no exchange rate has been fetched' ).

  ENDMETHOD.

  METHOD feature_ctrl_open_enables_edit.

    DATA(uuid) = create_test_procurement(
    procurement_id  = '014'
    source_currency = 'USD'
    preferred_ccy   = 'EUR'
    quantity        = '1'
    unit_price      = '10' ).

    READ ENTITIES OF zr_scmproc IN LOCAL MODE
      ENTITY Procurement
        FIELDS ( OverallStatus )
        WITH VALUE #( ( ProcurementUUID = uuid ) )
      RESULT DATA(results).

    " Status should be Open (initial = Open in our model)
    cl_abap_unit_assert=>assert_true(
      act = COND abap_bool(
                  WHEN results[ 1 ]-OverallStatus = lsc_procurement_status=>open
                    OR results[ 1 ]-OverallStatus IS INITIAL
                  THEN abap_true ELSE abap_false )
      msg = 'Newly created procurement must have Open or initial status' ).

  ENDMETHOD.

  METHOD ft_ctrl_approved_locks_fields.

    api_double->simulated_rate = '1.1'.

    DATA(uuid) = create_test_procurement(
      procurement_id  = '15'
      source_currency = 'USD'
      preferred_ccy   = 'EUR'
      quantity        = '2'
      unit_price      = '50' ).

    " Approve it
    MODIFY ENTITIES OF zr_scmproc IN LOCAL MODE
      ENTITY Procurement
        EXECUTE Approve
          FROM VALUE #( ( ProcurementUUID = uuid ) )
      RESULT   DATA(action_result)
      FAILED   DATA(failed_action)
      REPORTED DATA(reported_action).

    cl_abap_unit_assert=>assert_initial(
      act = failed_action-Procurement
      msg = 'Approve must succeed' ).

    " Attempt to update UnitPrice after approval — should still be rejected
    " (the validation on save will catch it; feature control prevents UI entry)
    MODIFY ENTITIES OF zr_scmproc IN LOCAL MODE
      ENTITY Procurement
        UPDATE FIELDS ( OverallStatus )
        WITH VALUE #( ( ProcurementUUID = uuid  OverallStatus = lsc_procurement_status=>open ) )
      REPORTED DATA(reported_reopen).

    READ ENTITIES OF zr_scmproc IN LOCAL MODE
      ENTITY Procurement
        FIELDS ( OverallStatus )
        WITH VALUE #( ( ProcurementUUID = uuid ) )
      RESULT DATA(results).

    " OverallStatus is readonly in BDEF — the MODIFY above is silently ignored
    cl_abap_unit_assert=>assert_equals(
      exp = lsc_procurement_status=>approved
      act = results[ 1 ]-OverallStatus
      msg = 'Approved status must be immutable (field is readonly in BDEF)' ).

  ENDMETHOD.

ENDCLASS.
