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
      determination_calculate_total    FOR TESTING,
      "! Check returned API message in case of api error
      determination_handle_api_error   FOR TESTING,
      "! Check empty currency field
      determination_skip_empty_field   FOR TESTING,
      "! Check source and target currency are not same
      validation_reject_same_curr      FOR TESTING,
      "! Check quantity field is not zero
      validation_reject_zero_quan      FOR TESTING,
      "! Check price field is not zero
      validation_rejects_zero_price    FOR TESTING.

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

    MODIFY ENTITIES OF zr_scmproc
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

     READ ENTITIES OF zr_scmproc in local mode
     ENTITY Procurement
     FIELDS ( TotalInPreferredCcy ExchangeRate ApiMessage )
     WITH VALUE #( ( ProcurementUUID = uuid ) )
     RESULT data(lt_results).

     data(ls_result) = lt_results[ 1 ].
     cl_abap_unit_assert=>assert_equals(
     msg = 'Total should be Qty × Price × Rate = 10 × 100 × 1.2 = 1200'
     exp = conv zscm_total_in_preferred_ccy( '1200' )
     act = ls_result-TotalInPreferredCcy ).

     cl_abap_unit_assert=>assert_equals(
     msg = 'ExchangeRate should reflect the simulated rate'
     exp = conv zscm_exchange_rate( '1.2' )
     act = ls_result-ExchangeRate ).

     cl_abap_unit_assert=>assert_not_initial(
     msg = 'ApiMessage should contain the rate description'
     act = ls_result-ApiMessage ).

  ENDMETHOD.

  METHOD determination_handle_api_error.

  ENDMETHOD.

  METHOD determination_skip_empty_field.

  ENDMETHOD.

  METHOD validation_rejects_zero_price.

  ENDMETHOD.

  METHOD validation_reject_same_curr.

  ENDMETHOD.

  METHOD validation_reject_zero_quan.

  ENDMETHOD.

ENDCLASS.
