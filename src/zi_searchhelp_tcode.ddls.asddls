@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Search Help TCode'
@Metadata.ignorePropagatedAnnotations: true

define view entity ZI_SEARCHHELP_TCODE
  as select distinct from ZI_ACTIVITY_LOG
{
  key Tcode,
  key ActDate,
  key Username
}
where
      Tcode is not null
  and Tcode <> ''
