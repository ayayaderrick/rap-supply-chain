@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Value Help for Orders'
@Metadata.ignorePropagatedAnnotations: true
@Search.searchable: true
define view entity ZSCM_I_ORDER as select from ZR_SCMPROC
{
    @UI.hidden: true
    key ProcurementUUID,
    @Search.defaultSearchElement: true
    ProcurementID,
    @Search.defaultSearchElement: true
    MaterialName
    
}
