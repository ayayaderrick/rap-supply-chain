@Metadata.allowExtensions: true
@Metadata.ignorePropagatedAnnotations: true
@Endusertext: {
  Label: '###GENERATED Core Data Service Entity'
}
@Objectmodel: {
  Sapobjectnodetype.Name: 'ZSCM_A_PROC'
}
@AccessControl.authorizationCheck: #MANDATORY
define root view entity ZC_SCMPROC
  provider contract TRANSACTIONAL_QUERY
  as projection on ZR_SCMPROC
  association [1..1] to ZR_SCMPROC as _BaseEntity on $projection.PROCUREMENTUUID = _BaseEntity.PROCUREMENTUUID
{
  key ProcurementUUID,
  ProcurementID,
  MaterialName,
  Supplier,
  @Semantics: {
    Quantity.Unitofmeasure: 'UnitOfMeasure'
  }
  Quantity,
  @Consumption: {
    Valuehelpdefinition: [ {
      Entity.Element: 'UnitOfMeasure', 
      Entity.Name: 'I_UnitOfMeasureStdVH', 
      Useforvalidation: true
    } ]
  }
  UnitOfMeasure,
  @Semantics: {
    Amount.Currencycode: 'SourceCurrency'
  }
  UnitPrice,
  @Consumption: {
    Valuehelpdefinition: [ {
      Entity.Element: 'Currency', 
      Entity.Name: 'I_CurrencyStdVH', 
      Useforvalidation: true
    } ]
  }
  SourceCurrency,
  @Consumption: {
    Valuehelpdefinition: [ {
      Entity.Element: 'Currency', 
      Entity.Name: 'I_CurrencyStdVH', 
      Useforvalidation: true
    } ]
  }
  PreferredCurrency,
  ExchangeRate,
  @Semantics: {
    Amount.Currencycode: 'PreferredCurrency'
  }
  TotalInPreferredCcy,
  @Semantics: {
    Systemdatetime.Createdat: true
  }
  RateFetchTimestamp,
  ApiMessage,
  OverallStatus,
  @Semantics: {
    User.Createdby: true
  }
  CreatedBy,
  @Semantics: {
    Systemdatetime.Createdat: true
  }
  CreatedAt,
  @Semantics: {
    User.Localinstancelastchangedby: true
  }
  LocalLastChangedBy,
  @Semantics: {
    Systemdatetime.Localinstancelastchangedat: true
  }
  LocalLastChangedAt,
  @Semantics: {
    Systemdatetime.Lastchangedat: true
  }
  LastChangedAt,
  _BaseEntity
}
