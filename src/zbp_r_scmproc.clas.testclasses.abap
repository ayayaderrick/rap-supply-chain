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
      RAISE EXCEPTION NEW zcx_scm_api_error(
        error_message = 'Simulated API failure' ).
    ENDIF.
    result = simulated_rate.
  ENDMETHOD.
ENDCLASS.

"! @testing BDEF:ZR_SCMPROC
CLASS ltc_procurement DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.


ENDCLASS.


CLASS ltc_procurement IMPLEMENTATION.



ENDCLASS.
