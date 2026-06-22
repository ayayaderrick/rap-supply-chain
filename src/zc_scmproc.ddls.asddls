@Metadata.allowExtensions: true
@Metadata.ignorePropagatedAnnotations: true
@EndUserText: {
  label: 'Procurement Orders'
}
@ObjectModel: {
  sapObjectNodeType.name: 'ZSCM_A_PROC'
}
@AccessControl.authorizationCheck: #MANDATORY
@UI.headerInfo: { typeName: 'Procurement Order',
                  typeNamePlural: 'Procurement Orders' }
@Search.searchable: true
define root view entity ZC_SCMPROC
  provider contract transactional_query
  as projection on ZR_SCMPROC
  association [1..1] to ZR_SCMPROC as _BaseEntity on $projection.ProcurementUUID = _BaseEntity.ProcurementUUID
{
  key ProcurementUUID,
  @Search.defaultSearchElement: true
  @Search.fuzzinessThreshold: 0.8
  ProcurementID,
  @Search.defaultSearchElement: true
  @Search.fuzzinessThreshold: 0.8
  MaterialName,
  @Search.defaultSearchElement: true
  @Search.fuzzinessThreshold: 0.8
  Supplier,
  @Semantics: {
    quantity.unitOfMeasure: 'UnitOfMeasure'
  }
  Quantity,
  @Consumption: {
    valueHelpDefinition: [ {
      entity.element: 'UnitOfMeasure', 
      entity.name: 'I_UnitOfMeasureStdVH', 
      useForValidation: true
    } ]
  }
  UnitOfMeasure,
  @Semantics: {
    amount.currencyCode: 'SourceCurrency'
  }
  UnitPrice,
  @Consumption: {
    valueHelpDefinition: [ {
      entity.element: 'Currency', 
      entity.name: 'I_CurrencyStdVH', 
      useForValidation: true
    } ]
  }
  SourceCurrency,
  @Consumption: {
    valueHelpDefinition: [ {
      entity.element: 'Currency', 
      entity.name: 'I_CurrencyStdVH', 
      useForValidation: true
    } ]
  }
  PreferredCurrency,
  ExchangeRate,
  @Semantics: {
    amount.currencyCode: 'PreferredCurrency'
  }
  TotalInPreferredCcy,
  @Semantics: {
    systemDateTime.createdAt: true
  }
  RateFetchTimestamp,
  ApiMessage,
  OverallStatus,
  @Semantics: {
    user.createdBy: true
  }
  CreatedBy,
  @Semantics: {
    systemDateTime.createdAt: true
  }
  CreatedAt,
  @Semantics: {
    user.localInstanceLastChangedBy: true
  }
  LocalLastChangedBy,
  @Semantics: {
    systemDateTime.localInstanceLastChangedAt: true
  }
  LocalLastChangedAt,
  @Semantics: {
    systemDateTime.lastChangedAt: true
  }
  LastChangedAt,
  _BaseEntity
}
