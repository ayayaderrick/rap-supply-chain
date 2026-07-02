CLASS ltc_exch_rate_api DEFINITION DEFERRED.
CLASS zcl_scm_exch_rate_api DEFINITION LOCAL FRIENDS ltc_exch_rate_api.

"══════════════════════════════════════════════════════════════════════════════
" Unit tests for zcl_scm_exch_rate_api
" Focus: the JSON parsing logic in extract_rate_from_json.
" HTTP calls are not exercised here (that would be an integration test).
"══════════════════════════════════════════════════════════════════════════════
CLASS ltc_exch_rate_api DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    " Class under test — instantiated via FRIENDS access to private constructor
    DATA cut TYPE REF TO zcl_scm_exch_rate_api.
    METHODS:
      setup,
      parse_compact_json_eur      FOR TESTING
        RAISING
          zcx_scm_api_error,
      parse_compact_json_gbp      FOR TESTING,
      parse_pretty_printed_json   FOR TESTING,
      parse_rate_at_end_of_block  FOR TESTING,

      " ── Same-currency short-circuit ────────────────────────────────────────
      same_currency_returns_one   FOR TESTING,

      " ── Error cases ────────────────────────────────────────────────────────
      missing_rates_block_raises  FOR TESTING,
      unknown_currency_raises     FOR TESTING,
      non_numeric_value_raises    FOR TESTING.

    " ── Helper: call private method via FRIENDS ────────────────────────────
    METHODS parse_json
      IMPORTING
        json_body       TYPE string
        target_currency TYPE waers
      RETURNING
        VALUE(result)   TYPE decfloat34
      RAISING
        zcx_scm_api_error.

ENDCLASS.


CLASS ltc_exch_rate_api  IMPLEMENTATION.

  METHOD setup.

    " FRIENDS allows direct instantiation of the private constructor
    cut = NEW zcl_scm_exch_rate_api(  ).

  ENDMETHOD.

  " Delegate to the private method via FRIENDS
  METHOD parse_json.
    result = cut->extract_rate_from_json(
        json_body = json_body
        target_currency = target_currency ).
  ENDMETHOD.

  METHOD missing_rates_block_raises.

  ENDMETHOD.

  METHOD non_numeric_value_raises.

  ENDMETHOD.

  METHOD parse_compact_json_eur.

    CONSTANTS json TYPE string VALUE
      `{"result":"success","base_code":"USD",` &
      `"rates":{"AED":3.67,"EUR":0.91,"GBP":0.79,"JPY":150.23}}`.

    DATA(rate) = parse_json( json_body = json target_currency = 'EUR' ).

    cl_abap_unit_assert=>assert_equals(
      exp = CONV decfloat34( '0.91' )
      act = rate
      msg = 'EUR rate from compact JSON should be 0.91' ).

  ENDMETHOD.

  METHOD parse_compact_json_gbp.

  ENDMETHOD.

  METHOD parse_pretty_printed_json.

  ENDMETHOD.

  METHOD parse_rate_at_end_of_block.

  ENDMETHOD.

  METHOD same_currency_returns_one.

  ENDMETHOD.

  METHOD unknown_currency_raises.

  ENDMETHOD.

ENDCLASS.
