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
      parse_compact_json_gbp      FOR TESTING
        RAISING
          zcx_scm_api_error,
      parse_pretty_printed_json   FOR TESTING
        RAISING
          zcx_scm_api_error,
      parse_rate_at_end_of_block  FOR TESTING
        RAISING
          zcx_scm_api_error,

      " ── Same-currency short-circuit ────────────────────────────────────────
      same_currency_returns_one   FOR TESTING
        RAISING
          zcx_scm_api_error,

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

  "──────────────────────────────────────────────────────────────────────────
  " Missing "rates" object → zcx_scm_api_error must be raised
  "──────────────────────────────────────────────────────────────────────────
  METHOD missing_rates_block_raises.

    CONSTANTS json TYPE string VALUE
      `{"result":"success","base_code":"USD","data":{"EUR":0.91}}`.

    TRY.
        parse_json( json_body = json target_currency = 'EUR' ).
        cl_abap_unit_assert=>fail(
          msg = 'Expected zcx_scm_api_error for missing rates block' ).
      CATCH zcx_scm_api_error INTO DATA(api_error).
        cl_abap_unit_assert=>assert_not_initial(
          act = api_error->error_message
          msg = 'Error message must not be empty' ).
    ENDTRY.

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

    CONSTANTS json TYPE string VALUE
      `{"result":"success","base_code":"USD",` &
      `"rates":{"AED":3.67,"EUR":0.91,"GBP":0.79,"JPY":150.23}}`.

    DATA(rate) = parse_json( json_body = json target_currency = 'GBP' ).

    cl_abap_unit_assert=>assert_equals(
      exp = CONV decfloat34( '0.79' )
      act = rate
      msg = 'GBP rate from compact JSON should be 0.79' ).

  ENDMETHOD.

  METHOD parse_pretty_printed_json.

    CONSTANTS json TYPE string VALUE
      `{"result": "success", "base_code": "USD",` &
      ` "rates": { "EUR": 0.91, "GBP": 0.79 }}`.

    DATA(rate) = parse_json( json_body = json target_currency = 'GBP' ).

    cl_abap_unit_assert=>assert_equals(
      exp = CONV decfloat34( '0.79' )
      act = rate
      msg = 'GBP rate from pretty-printed JSON should be 0.79' ).
  ENDMETHOD.

  METHOD parse_rate_at_end_of_block.

    CONSTANTS json TYPE string VALUE
      `{"result":"success","base_code":"USD","rates":{"EUR":0.91,"ZAR":18.75}}`.

    DATA(rate) = parse_json( json_body = json target_currency = 'ZAR' ).

    cl_abap_unit_assert=>assert_equals(
      exp = CONV decfloat34( '18.75' )
      act = rate
      msg = 'ZAR rate at end of rates block should be 18.75' ).

  ENDMETHOD.

  "──────────────────────────────────────────────────────────────────────────
  " Same source and target currency — must return 1 without any HTTP call
  "──────────────────────────────────────────────────────────────────────────
  METHOD same_currency_returns_one.

    DATA(rate) = cut->zif_scm_exch_rate_api~get_exchange_rate(
      source_currency = 'USD'
      target_currency = 'USD' ).

    cl_abap_unit_assert=>assert_equals(
      exp = CONV decfloat34( '1' )
      act = rate
      msg = 'Same currency must always return rate 1 without an API call' ).

  ENDMETHOD.

  "──────────────────────────────────────────────────────────────────────────
  " Currency not in the rates object → zcx_scm_api_error
  "──────────────────────────────────────────────────────────────────────────
   METHOD unknown_currency_raises.

    CONSTANTS json TYPE string VALUE
      `{"result":"success","base_code":"USD","rates":{"EUR":0.91,"GBP":0.79}}`.

    TRY.
        parse_json( json_body = json target_currency = 'XYZ' ).
        cl_abap_unit_assert=>fail(
          msg = 'Expected zcx_scm_api_error for unknown currency XYZ' ).
      CATCH zcx_scm_api_error INTO DATA(api_error).
        cl_abap_unit_assert=>assert_not_initial(
          act = api_error->error_message
          msg = 'Error message must not be empty' ).
    ENDTRY.

  ENDMETHOD.

ENDCLASS.
