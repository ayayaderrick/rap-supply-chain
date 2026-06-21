CLASS zcl_create_nr_interval DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    INTERFACES if_oo_adt_classrun .
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zcl_create_nr_interval IMPLEMENTATION.


  METHOD if_oo_adt_classrun~main.

    " Define interval configuration parameters
    DATA lt_intervals TYPE cl_numberrange_intervals=>nr_interval.

    lt_intervals = VALUE #( (
      nrrangenr  = '01'         " The interval ID matching your RAP code
      fromnumber = '00000001'   " Numeric range bottom edge
      tonumber   = '99999999'   " Numeric range top edge
      procind    = 'I'          " Internal allocation indicator
    ) ).

    try.
        " Create the interval configuration inside the object
        cl_numberrange_intervals=>create(
          EXPORTING
            interval  = lt_intervals
            object    = 'ZSCM_PRNR'
          IMPORTING
            error     = DATA(lv_error)
            error_inf = DATA(ls_error_info)
        ).

        IF lv_error IS INITIAL.
          out->write( 'Interval 01 created successfully.' ).
        ELSE.
          out->write( |Failed to create interval: { ls_error_info-msgnr }| ).
        ENDIF.

    " Catch the specific missing object exception
      CATCH cx_nr_object_not_found INTO DATA(lx_not_found).
        out->write( |Error: The Number Range Object ZSCM_PRNR does not exist. { lx_not_found->get_text( ) }| ).

      " Catch all other generic number range interface errors
      CATCH cx_number_ranges INTO DATA(lx_nr_error).
        out->write( |Error: A general number range exception occurred. { lx_nr_error->get_text( ) }| ).
    ENDTRY.

  ENDMETHOD.
ENDCLASS.
