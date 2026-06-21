@AccessControl.authorizationCheck: #MANDATORY
@Metadata.allowExtensions: true
@ObjectModel.sapObjectNodeType.name: 'ZSCM_A_PROC'
@EndUserText.label: '###GENERATED Core Data Service Entity'
define root view entity ZR_SCMPROC
  as select from zscm_a_proc as Procurement
{
  key procurement_uuid as ProcurementUUID,
  procurement_id as ProcurementID,
  material_name as MaterialName,
  supplier as Supplier,
  @Semantics.quantity.unitOfMeasure: 'UnitOfMeasure'
  quantity as Quantity,
  @Consumption.valueHelpDefinition: [ {
    entity.name: 'I_UnitOfMeasureStdVH', 
    entity.element: 'UnitOfMeasure', 
    useForValidation: true
  } ]
  unit_of_measure as UnitOfMeasure,
  @Semantics.amount.currencyCode: 'SourceCurrency'
  unit_price as UnitPrice,
  @Consumption.valueHelpDefinition: [ {
    entity.name: 'I_CurrencyStdVH', 
    entity.element: 'Currency', 
    useForValidation: true
  } ]
  source_currency as SourceCurrency,
  @Consumption.valueHelpDefinition: [ {
    entity.name: 'I_CurrencyStdVH', 
    entity.element: 'Currency', 
    useForValidation: true
  } ]
  preferred_currency as PreferredCurrency,
  exchange_rate as ExchangeRate,
  @Semantics.amount.currencyCode: 'PreferredCurrency'
  total_in_preferred_ccy as TotalInPreferredCcy,
  @Semantics.systemDateTime.createdAt: true
  rate_fetch_timestamp as RateFetchTimestamp,
  api_message as ApiMessage,
  overall_status as OverallStatus,
  @Semantics.user.createdBy: true
  created_by as CreatedBy,
  @Semantics.systemDateTime.createdAt: true
  created_at as CreatedAt,
  @Semantics.user.localInstanceLastChangedBy: true
  local_last_changed_by as LocalLastChangedBy,
  @Semantics.systemDateTime.localInstanceLastChangedAt: true
  local_last_changed_at as LocalLastChangedAt,
  @Semantics.systemDateTime.lastChangedAt: true
  last_changed_at as LastChangedAt
}
