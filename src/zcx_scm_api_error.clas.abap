CLASS zcx_scm_api_error DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    DATA error_message TYPE string READ-ONLY.
    DATA http_status TYPE i READ-ONLY.

    INTERFACES if_t100_message .
    INTERFACES if_t100_dyn_msg .

    METHODS constructor
      IMPORTING
        error_message TYPE string OPTIONAL
        http_status   TYPE i OPTIONAL
*        !textid   LIKE if_t100_message=>t100key OPTIONAL
        !previous     LIKE previous OPTIONAL .

    METHODS get_text REDEFINITION.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zcx_scm_api_error IMPLEMENTATION.


  METHOD constructor ##ADT_SUPPRESS_GENERATION.
    super->constructor(
    previous = previous
    ).
    me->error_message = error_message.
    me->http_status = http_status.
*    CLEAR me->textid.
*    IF textid IS INITIAL.
*      if_t100_message~t100key = if_t100_message=>default_textid.
*    ELSE.
*      if_t100_message~t100key = textid.
*    ENDIF.
  ENDMETHOD.


  METHOD get_text.

    result = COND string(
        WHEN http_status IS NOT INITIAL
        THEN |Exchange rate API error (HTTP { http_status }): { error_message } |
        ELSE |Exchange rate API error: { error_message }|
     ).

  ENDMETHOD.

ENDCLASS.
