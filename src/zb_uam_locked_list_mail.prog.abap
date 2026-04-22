**---------------------------------------------------------*
** Program ID: ZB_UAM_LOCKED_LIST_MAIL
** Program name: ZB_UAM_LOCKED_LIST_MAIL
** Created date: 2026-04-16
** Content explanation:
** This program retrieves locked user records from zuam_AUTH_LOG
** (EVENT_ID = 'AUM' and MAIL_SENT = '').
**
** It builds an HTML email listing all locked users and sends it
** via CL_BCS. After successful sending, the program updates
** MAIL_SENT = 'X' to avoid duplicate notifications.
**---------------------------------------------------------*
** <Modification tracking>
** Modification number:
** Modification day:
** Modification reason:
**---------------------------------------------------------*
REPORT zb_uam_locked_list_mail.

DATA: lt_auth_log TYPE STANDARD TABLE OF zuam_auth_log,
      ls_auth_log TYPE zuam_auth_log.

DATA: lv_user_count TYPE i.

START-OF-SELECTION.
  PERFORM get_auth.
  PERFORM sent_mail.

*&---------------------------------------------------------------------*
*& Form GET_AUTH
*&---------------------------------------------------------------------*
*& Read data of Table zuam_auth_log
*&---------------------------------------------------------------------*
FORM get_auth .
  SELECT * FROM zuam_auth_log
    INTO TABLE @lt_auth_log
    WHERE event_id = 'AUM'
      AND mail_sent = ''.

  IF lt_auth_log IS INITIAL.
    MESSAGE s018(zuam_msg).

    LEAVE PROGRAM.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form SENT_MAIL
*&---------------------------------------------------------------------*
*& Create mail and sent it
*&---------------------------------------------------------------------*
FORM sent_mail .
  "---------------------------------------------------------------------"
  " Data declaration
  "---------------------------------------------------------------------"
  DATA: lo_bcs       TYPE REF TO cl_bcs,               "Object mail
        lo_document  TYPE REF TO cl_document_bcs,      "Content mail
        lo_recipient TYPE REF TO if_recipient_bcs,     "Receiver
        lt_html      TYPE soli_tab,
        lv_html      TYPE string.

  DATA: lv_time TYPE string,
        lv_date TYPE string.

  DATA: lv_sent TYPE os_boolean.

  TRY.
      "---------------------------------------------------------------------"
      " Build HTML email
      "---------------------------------------------------------------------"
      lv_html =
        | <html>                                                                                           | &&
        | <body style="font-family:Arial;background:#f6f6f6;padding:20px;">                                | &&
        | <div style="background:white;padding:20px;border-radius:6px;width:700px;border:1px solid #ddd;"> | &&
        | <h2 style="color:#2c3e50;">🚨User Lock Report</h2>                                               | &&
        | <p style="color:#555;">The following users have been locked:</p>                                 | &&
        | <table style="border-collapse:collapse;width:100%;margin-top:10px;">                             | &&
        | <tr style="background:#2c3e50;color:white;">                                                     | &&
        | <th style="padding:8px;border:1px solid #ddd;">User</th>                                         | &&
        | <th style="padding:8px;border:1px solid #ddd;">System</th>                                       | &&
        | <th style="padding:8px;border:1px solid #ddd;">Client</th>                                       | &&
        | <th style="padding:8px;border:1px solid #ddd;">Lock reason</th>                                  | &&
        | <th style="padding:8px;border:1px solid #ddd;width:100px;">Date</th>                             | &&
        | <th style="padding:8px;border:1px solid #ddd;">Time</th>                                         | &&
        | </tr>                                                                                            |.

      LOOP AT lt_auth_log INTO ls_auth_log.
        lv_time = |{ ls_auth_log-erzet+0(2) }:{ ls_auth_log-erzet+2(2) }:{ ls_auth_log-erzet+4(2) }|.
        lv_date = |{ ls_auth_log-erdat+0(4) }-{ ls_auth_log-erdat+4(2) }-{ ls_auth_log-erdat+6(2) }|.

        lv_html = lv_html &&
          | <tr>                                                                                  | &&
          |  <td style="padding:8px;border:1px solid #ddd;">🔒{ ls_auth_log-username }</td>       | &&
          |  <td style="padding:8px;border:1px solid #ddd;">S40</td>                              | &&
          |  <td style="padding:8px;border:1px solid #ddd;">{ ls_auth_log-mandt }</td>            | &&
          |  <td style="padding:8px;border:1px solid #ddd;">{ ls_auth_log-login_message }</td>    | &&
          |  <td style="padding:8px;border:1px solid #ddd;width:100px;">{ lv_date }</td>          | &&
          |  <td style="padding:8px;border:1px solid #ddd;">{ lv_time }</td>                      | &&
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
                      i_subject = TEXT-001
                    ).

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
      " Update mail_sent in table zuam_auth_log
      "---------------------------------------------------------------------"
      IF lv_sent = abap_true.
        UPDATE zuam_auth_log
          SET mail_sent = 'X'
          WHERE event_id = 'AUM'
            AND mail_sent = ''.

        COMMIT WORK.

        lv_user_count = lines( lt_auth_log ).

        MESSAGE s019(zuam_msg) WITH lv_user_count.
      ENDIF.

    CATCH cx_send_req_bcs
          cx_address_bcs
          cx_document_bcs
          cx_bcs INTO DATA(lx_error).

      MESSAGE lx_error->get_text( ) TYPE 'E'.
  ENDTRY.

ENDFORM.
