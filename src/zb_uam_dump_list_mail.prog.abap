**---------------------------------------------------------*
** Program ID: ZB_UAM_DUMP_LIST_MAIL
** Program name: ZB_UAM_DUMP_LIST_MAIL
** Created date: 2026-04-17
** Content explanation:
** This program retrieves dump records from ZUAM_ACT_LOG
** (ACTIVITY_TYPE = 'DUMP' and MAIL_SENT = '').
**
** It builds an HTML email listing all dump logs and sends it
** via CL_BCS. After successful sending, the program updates
** MAIL_SENT = 'X' to avoid duplicate notifications.
**---------------------------------------------------------*
** <Modification tracking>
** Modification number:
** Modification day:
** Modification reason:
**---------------------------------------------------------*

REPORT ZB_UAM_DUMP_LIST_MAIL.

DATA: lt_log TYPE TABLE OF zuam_act_log,
      ls_log TYPE zuam_act_log.

START-OF-SELECTION.
  PERFORM get_dump.
  PERFORM sent_mail.

*&---------------------------------------------------------------------*
*& Form get_dump
*&---------------------------------------------------------------------*
*& Read data of table zuam_act_log
*&---------------------------------------------------------------------*
FORM get_dump .
  SELECT * FROM zuam_act_log
    WHERE act_type = 'DUMP'
      AND mail_sent IS INITIAL
    INTO TABLE @lt_log.

  IF lt_log IS INITIAL.
    MESSAGE s020(zuam_msg).

    LEAVE PROGRAM.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form sent_mail
*&---------------------------------------------------------------------*
*& Create mail and sent it
*&---------------------------------------------------------------------*
FORM sent_mail.
  "---------------------------------------------------------------------"
  " Data declaration
  "---------------------------------------------------------------------"
  DATA: lo_bcs       TYPE REF TO cl_bcs,               "Object mail
        lo_document  TYPE REF TO cl_document_bcs,      "Content mail
        lo_recipient TYPE REF TO if_recipient_bcs,     "Receiver
        lt_html      TYPE soli_tab,
        lv_html      TYPE string.

  DATA: lv_time TYPE string.
  DATA: lv_date TYPE string.

  DATA: lv_sent TYPE os_boolean.

  TRY.
      "---------------------------------------------------------------------"
      " Build HTML email
      "---------------------------------------------------------------------"
      lv_html =
        | <html>                                                                                           | &&
        | <body style="font-family:Arial;background:#f6f6f6;padding:20px;">                                | &&
        | <div style="background:white;padding:20px;border-radius:6px;width:700px;border:1px solid #ddd;"> | &&
        | <h2 style="color:#2c3e50;">🚨 SAP Dump Alert</h2>                                                | &&
        | <p style="color:#555;">The following dump records have been detected:</p>                        | &&
        | <table style="border-collapse:collapse;width:100%;margin-top:10px;">                             | &&
        | <tr style="background:#2c3e50;color:white;">                                                     | &&
        | <th style="padding:8px;border:1px solid #ddd;">User</th>                                         | &&
        | <th style="padding:8px;border:1px solid #ddd;">System</th>                                       | &&
        | <th style="padding:8px;border:1px solid #ddd;">Client</th>                                       | &&
        | <th style="padding:8px;border:1px solid #ddd;">Date</th>                                          | &&
        | <th style="padding:8px;border:1px solid #ddd;">Time</th>                                         | &&
        | <th style="padding:8px;border:1px solid #ddd;">Message</th>                                      | &&
        | </tr>                                                                                            |.

      LOOP AT lt_log INTO ls_log.
        lv_time = |{ ls_log-act_tims+0(2) }:{ ls_log-act_tims+2(2) }:{ ls_log-act_tims+4(2) }|.
        lv_date = |{ ls_log-act_date+0(4) }-{ ls_log-act_date+4(2) }-{ ls_log-act_date+6(2) }|.

        lv_html = lv_html &&
          | <tr>                                                                                  | &&
          |  <td style="padding:8px;border:1px solid #ddd;">{ ls_log-username }</td>              | &&
          |  <td style="padding:8px;border:1px solid #ddd;">S40</td>                              | &&
          |  <td style="padding:8px;border:1px solid #ddd;">{ ls_log-mandt }</td>                 | &&
          |  <td style="padding:8px;border:1px solid #ddd;">{ lv_date }</td>                      | &&
          |  <td style="padding:8px;border:1px solid #ddd;">{ lv_time }</td>                      | &&
          |  <td style="padding:8px;border:1px solid #ddd;">{ ls_log-message_text }</td>          | &&
          | </tr>                                                                                 |.
      ENDLOOP.

      lv_html = lv_html &&
          | </table>                                                                                         | &&
          | <p style="margin-top:15px;font-size:12px;color:#888;">This is an automated message from SAP.</p> | &&
          | </div></body></html>                                                                             |.

      "---------------------------------------------------------------------"
      " Convert string -> table
      "---------------------------------------------------------------------"
      CALL FUNCTION 'SCMS_STRING_TO_FTEXT'
        EXPORTING
          text      = lv_html
        TABLES
          ftext_tab = lt_html.

      "---------------------------------------------------------------------"
      " Create email document
      "---------------------------------------------------------------------"
      lo_document = cl_document_bcs=>create_document(
                      i_type    = 'HTM'
                      i_text    = lt_html
                      i_subject = TEXT-001 ).

      "---------------------------------------------------------------------"
      " Send request and Attach document into Email
      "---------------------------------------------------------------------"
      lo_bcs = cl_bcs=>create_persistent( ).

      lo_bcs->set_document( lo_document ).

      "---------------------------------------------------------------------"
      " Add recipient
      "---------------------------------------------------------------------"
      lo_recipient = cl_cam_address_bcs=>create_internet_address(
                       'anhtmse180745@fpt.edu.vn'
                     ).

      lo_bcs->add_recipient( lo_recipient ).

      "---------------------------------------------------------------------"
      " Send mail
      "---------------------------------------------------------------------"
      lo_bcs->set_send_immediately( abap_true ).
      lv_sent = lo_bcs->send( ).

      "---------------------------------------------------------------------"
      " Update mail_sent in table zuam_act_log
      "---------------------------------------------------------------------"
      IF lv_sent = abap_true.
        LOOP AT lt_log INTO ls_log.
          UPDATE zuam_act_log
            SET mail_sent = 'X'
            WHERE act_id = ls_log-act_id.
        ENDLOOP.

        COMMIT WORK.
      ENDIF.

    CATCH cx_send_req_bcs
          cx_address_bcs
          cx_document_bcs
          cx_bcs INTO DATA(lx_error).
      MESSAGE lx_error->get_text( ) TYPE 'E'.
  ENDTRY.
ENDFORM.
