@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'CDS View - Activity Count Perday'
@Metadata.ignorePropagatedAnnotations: true

define view entity ZI_ACTIVITY_COUNT_PERDAY
  as select from ZI_ACTIVITY_LOG
{
  key ActDate,
  key Username,
      count ( * ) as ActivityCount
}
group by
  ActDate,
  Username
