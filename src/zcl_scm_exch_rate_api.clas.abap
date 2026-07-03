CLASS zcl_scm_exch_rate_api DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    INTERFACES zif_scm_exch_rate_api .
    CLASS-METHODS create RETURNING VALUE(result) TYPE REF TO zif_scm_exch_rate_api.
  PROTECTED SECTION.
  PRIVATE SECTION.
    CONSTANTS c_api_base_url TYPE string VALUE 'https://open.er-api.com'.

    METHODS extract_rate_from_json
      IMPORTING
                json_body       TYPE string
                target_currency TYPE waers
      RETURNING VALUE(result)   TYPE decfloat34
      RAISING   zcx_scm_api_error.
ENDCLASS.



CLASS zcl_scm_exch_rate_api IMPLEMENTATION.


  METHOD create.
    result = NEW zcl_scm_exch_rate_api(  ).
  ENDMETHOD.


  METHOD zif_scm_exch_rate_api~get_exchange_rate.

    " Short-circuit: same currency always has rate = 1
    IF source_currency = target_currency.
      result = 1.
      RETURN.
    ENDIF.

    TRY.
        DATA(destination) = cl_http_destination_provider=>create_by_url( i_url = |{ c_api_base_url }/v6/latest/{ source_currency }| ).
        DATA(web_client) = cl_web_http_client_manager=>create_by_http_destination( destination ).
        DATA(http_request) = web_client->get_http_request(  ).
        http_request->set_header_field( i_name = 'Accept' i_value = 'application/json' ).
        DATA(http_response) = web_client->execute( if_web_http_client=>get ).
        DATA(status) = http_response->get_status(  ).

        IF status-code <> 200.
          RAISE EXCEPTION NEW zcx_scm_api_error( error_message = |API returned HTTP { status-code } ({ status-reason }).|
                                                                 & |Verify that currency code '{ source_currency }' is ISO 4217 compliant. |
                                                 http_status   = status-code
                                                 ).
        ENDIF.

        result = extract_rate_from_json(
            json_body = http_response->get_text(  )
            target_currency = target_currency
         ).

      CATCH cx_web_http_client_error INTO DATA(http_error).
        " Catches execution, communication, and protocol issues
        RAISE EXCEPTION NEW zcx_scm_api_error( error_message = |Cannot reach the exchange rate API: { http_error->get_text(  ) }.|
                                                               & |Check that internet egress is allowed for this BTP subaccount.|
                                               previous      = http_error
                                               ).
      CATCH cx_http_dest_provider_error INTO DATA(dest_error).
        " Catches destination creation or URL parsing failures
        RAISE EXCEPTION NEW zcx_scm_api_error( error_message = |Failed to establish destination for URL: { dest_error->get_text(  ) }.|
                                               previous      = dest_error
                                               ).
    ENDTRY.

  ENDMETHOD.


  METHOD extract_rate_from_json.
    " ── Step 1: Locate the "rates" block ──────────────────────────────────
    DATA(json_len) = strlen( json_body ).

    DATA(rates_key_compact)  = `"rates":{`.
    DATA(rates_key_spaced)   = `"rates": {`.

    DATA(rates_pos) = find( val = json_body sub = rates_key_compact ).
    DATA(rates_key_len) = strlen( rates_key_compact ).

    IF rates_pos < 0.
      rates_pos    = find( val = json_body sub = rates_key_spaced ).
      rates_key_len = strlen( rates_key_spaced ).
    ENDIF.

    IF rates_pos < 0.
      DATA(snippet_len) = COND i( WHEN json_len > 120 THEN 120 ELSE json_len ).
      RAISE EXCEPTION NEW zcx_scm_api_error( error_message = |Unexpected API response: "rates" object not found. |
                                                             & |Raw snippet: { substring( val = json_body off = 0 len = snippet_len ) }| ).
    ENDIF.

    " Work only within the rates block from here on
    DATA(rates_start) = rates_pos + rates_key_len.
    DATA(rates_section) = substring( val = json_body off = rates_start ).

    " ── Step 2: Locate the target currency key ────────────────────────────
    DATA(search_key) = |"{ target_currency }":|.
    DATA(key_pos)    = find( val = rates_section sub = search_key ).

    IF key_pos < 0.
      " Try the pretty-printed variant with a space after the colon
      search_key = |"{ target_currency }": |.
      key_pos    = find( val = rates_section sub = search_key ).
    ENDIF.

    IF key_pos < 0.
      RAISE EXCEPTION NEW zcx_scm_api_error( error_message = |Currency '{ target_currency }' not found in the rates list. |
                                                             & |Verify the ISO 4217 code is correct and supported by the API.| ).
    ENDIF.

    " ── Step 3: Extract the value token — bounds-safe ─────────────────────
    DATA(value_start) = key_pos + strlen( search_key ).
    DATA(remaining)   = strlen( rates_section ) - value_start.

    IF remaining <= 0.
      RAISE EXCEPTION NEW zcx_scm_api_error( error_message = |No value found after currency key '{ target_currency }' |
                                                             & |in the rates block.| ).
    ENDIF.

    " Take only what is available — never assume 30 chars remain
    DATA(extract_len) = COND i( WHEN remaining > 30 THEN 30 ELSE remaining ).
    DATA(value_fragment) = condense(
      substring( val = rates_section off = value_start len = extract_len ) ).

    " ── Step 4: Clip at the first delimiter (, or }) ──────────────────────
    DATA(delim_pos) = find_any_of( val = value_fragment sub = `,}` ).
    DATA(rate_string) = COND string(
      WHEN delim_pos > 0
      THEN condense( substring( val = value_fragment off = 0 len = delim_pos ) )
      ELSE condense( value_fragment ) ).

    " Strip any surrounding whitespace or quotes left by pretty-printed JSON
    rate_string = replace( val = rate_string sub = `"` with = `` occ = 0 ).
    rate_string = condense( rate_string ).

    " ── Step 5: Convert to numeric ────────────────────────────────────────
    IF rate_string IS INITIAL.
      RAISE EXCEPTION NEW zcx_scm_api_error( error_message = |Empty rate value extracted for '{ target_currency }'. |
                                                             & |Check the API response format.| ).
    ENDIF.

    TRY.
        result = CONV decfloat34( rate_string ).
      CATCH cx_sy_conversion_no_number INTO DATA(conv_error).
        RAISE EXCEPTION NEW zcx_scm_api_error( error_message = |Cannot parse rate value '{ rate_string }' |
                                                               & |for { target_currency } as a number.|
                                               previous      = conv_error ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
