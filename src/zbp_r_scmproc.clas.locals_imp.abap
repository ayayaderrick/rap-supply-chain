CLASS lhc_zr_scmproc DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS:
      get_global_authorizations FOR GLOBAL AUTHORIZATION
        IMPORTING
        REQUEST requested_authorizations FOR Procurement
        RESULT result,
      setProcurementId FOR DETERMINE ON MODIFY
        IMPORTING keys FOR Procurement~setProcurementId.
ENDCLASS.

CLASS lhc_zr_scmproc IMPLEMENTATION.
  METHOD get_global_authorizations.
  ENDMETHOD.
  METHOD setProcurementId.

    " Exit early if no keys are provided
    if keys is initial.
        return.
    endif.

    " Read the newly created instances
    READ ENTITIES OF zr_scmproc IN LOCAL MODE
    ENTITY Procurement
    FIELDS ( ProcurementID ) WITH CORRESPONDING #( keys )
    RESULT DATA(procurements).

    " Filter out any records that already have a ProcurementID assigned
    DATA(procurements_wo_id) = procurements.
    DELETE procurements_wo_id WHERE ProcurementID IS NOT INITIAL.

    DATA(lv_quantity) = lines( procurements_wo_id ).
    DATA lv_start_id TYPE zscm_procurement_id.

    TRY.
        cl_numberrange_runtime=>number_get(
          EXPORTING
            nr_range_nr       = '01'
            object            = 'ZSCM_PRNR'
            quantity          = CONV #( lv_quantity )
          IMPORTING
            number            = DATA(lv_returned_number)
            returned_quantity = DATA(lv_returned_qty)
        ).

        " Calculate starting point (Assuming interval returns the last number of the block)
        lv_start_id = lv_returned_number - lv_returned_qty.

      CATCH cx_number_ranges INTO DATA(lx_number_ranges).
        " Modern RAP message handling from exception
        reported-procurement = VALUE #( FOR proc IN procurements_wo_id (
          procurementuuid = proc-ProcurementUUID
          %is_draft       = proc-%is_draft
          %msg            = new_message_with_text(
                              severity = if_abap_behv_message=>severity-error
                              text     = lx_number_ranges->get_text( )
                            )
        ) ).
        RETURN.
    ENDTRY.

    " Prepare the update sequence using EML
    DATA lt_update TYPE TABLE FOR UPDATE zr_scmproc.

    lt_update = VALUE #( FOR proc IN procurements_wo_id INDEX INTO lv_index (
      procurementuuid        = proc-ProcurementUUID
      %is_draft              = proc-%is_draft
      procurementid          = |{ ( lv_start_id + lv_index ) WIDTH = 8 PAD = '0' ALIGN = RIGHT }| " Ensures NUMC8 format
      %control-procurementid = if_abap_behv=>mk-on
    ) ).

    MODIFY ENTITIES OF zr_scmproc IN LOCAL MODE
    ENTITY Procurement
    UPDATE FIELDS ( ProcurementID ) WITH lt_update.

  ENDMETHOD.

ENDCLASS.

















