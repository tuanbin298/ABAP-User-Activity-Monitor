@AccessControl.authorizationCheck: #CHECK
@AbapCatalog.viewEnhancementCategory: [#NONE]
@EndUserText.label: 'Activity Log'
@Metadata.ignorePropagatedAnnotations: true
@Metadata.allowExtensions: true

define view entity ZI_ACTIVITY_LOG
  as select from zuam_act_log
  association        to parent ZIR_AUTH_LOG as _User      on  $projection.SessionId = _User.SessionId
  association [0..1] to tstct               as _TCodeText on  $projection.TCode = _TCodeText.tcode
                                                          and _TCodeText.sprsl  = $session.system_language
{
  key act_id           as ActId,
      session_id       as SessionId,
      username         as Username,
      act_type         as ActType,
      tcode            as Tcode,
      _TCodeText.ttext as TCodeName,
      act_date         as ActDate,
      act_tims         as ActTims,
      message_text     as MessageText,
      mail_sent        as MailSent,

      _User,
      _TCodeText
}
