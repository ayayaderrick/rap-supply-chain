@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Value Help for Material Name'
@Metadata.ignorePropagatedAnnotations: true
@Search.searchable: true
define view entity zscm_i_material_vh as select from ZR_SCMPROC
{
    @UI.hidden: true
    key ProcurementUUID,
    @Search.defaultSearchElement: true
    @Search.fuzzinessThreshold: 0.8
    MaterialName
}
