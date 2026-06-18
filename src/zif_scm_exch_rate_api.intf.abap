INTERFACE zif_scm_exch_rate_api
  PUBLIC .

  METHODS get_exchange_rate
    IMPORTING
      source_currency TYPE waers
      target_currency TYPE waers
    RETURNING
      VALUE(result)   TYPE decfloat34
    RAISING
      zcx_scm_api_error.


ENDINTERFACE.
