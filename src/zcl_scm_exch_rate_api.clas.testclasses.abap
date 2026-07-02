CLASS ltc_exch_rate_api DEFINITION DEFERRED.
CLASS zcl_scm_exch_rate_api DEFINITION LOCAL FRIENDS ltc_exch_rate_api.
CLASS ltc_exch_rate_api DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS:
      first_test FOR TESTING RAISING cx_static_check.
ENDCLASS.


CLASS ltc_exch_rate_api  IMPLEMENTATION.

  METHOD first_test.
    cl_abap_unit_assert=>fail( 'Implement your first test here' ).
  ENDMETHOD.

ENDCLASS.
