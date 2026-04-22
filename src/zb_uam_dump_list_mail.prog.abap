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
  TRY.
      "---------------------------------------------------------------------"
      " Data declaration
      "---------------------------------------------------------------------"
      DATA: lo_send_request TYPE REF TO cl_bcs,
            lo_document     TYPE REF TO cl_document_bcs,
            lo_recipient    TYPE REF TO if_recipient_bcs.

      DATA lt_text TYPE soli_tab.
      DATA: lv_html TYPE string.

      "---------------------------------------------------------------------
      " Build HTML email
      "---------------------------------------------------------------------
      DATA: lt_html_lines TYPE TABLE OF string.
      DATA: lv_line       TYPE string.

      lv_line = '<html><body>'. APPEND lv_line TO lt_html_lines.
      lv_line = '<h2>SAP Dump Alert</h2>'. APPEND lv_line TO lt_html_lines.
      lv_line = '<table border="1" cellpadding="5" cellspacing="0" style="border-collapse:collapse">'. APPEND lv_line TO lt_html_lines.
      lv_line = '<tr style="background-color:#f2f2f2"><th>User</th><th>System</th><th>Client</th><th>Time</th><th>Message</th></tr>'. APPEND lv_line TO lt_html_lines.

      DATA: lv_time_formatted TYPE string.

      LOOP AT lt_log INTO ls_log.
        lv_time_formatted = |{ ls_log-act_tims+0(2) }:{ ls_log-act_tims+2(2) }:{ ls_log-act_tims+4(2) }|.

        lv_line = '<tr>' &&
                  '<td>' && ls_log-username     && '</td>' &&
                  '<td>S40</td>'                &&
                  '<td>' && ls_log-mandt        && '</td>' &&
                  '<td>' && lv_time_formatted   && '</td>' &&
                  '<td>' && ls_log-message_text && '</td>' &&
                  '</tr>'.
        APPEND lv_line TO lt_html_lines.
      ENDLOOP.

      lv_line = '</table></body></html>'. APPEND lv_line TO lt_html_lines.

      " Gộp lại vào lt_text để gửi email
      LOOP AT lt_html_lines INTO lv_line.
        APPEND lv_line TO lt_text.
      ENDLOOP.
      "---------------------------------------------------------------------"
      " Create email document
      "---------------------------------------------------------------------"
      lo_document = cl_document_bcs=>create_document(
                      i_type    = 'HTM'
                      i_text    = lt_text
                      i_subject = TEXT-001 ).

      "---------------------------------------------------------------------"
      " Send request and Attach document into Email
      "---------------------------------------------------------------------"
      lo_send_request = cl_bcs=>create_persistent( ).

      lo_send_request->set_document( lo_document ).

      "---------------------------------------------------------------------"
      " Add recipient
      "---------------------------------------------------------------------"
      lo_recipient = cl_cam_address_bcs=>create_internet_address(
                        'anhtmse180745@fpt.edu.vn'
                      ).

      lo_send_request->add_recipient( lo_recipient ).

      "---------------------------------------------------------------------"
      " Send mail
      "---------------------------------------------------------------------"
      lo_send_request->set_send_immediately( abap_true ).
      lo_send_request->send( ).
      COMMIT WORK.

      "---------------------------------------------------------------------"
      " Update mail_sent in table zuam_act_log
      "---------------------------------------------------------------------"
      LOOP AT lt_log INTO ls_log.
        UPDATE zuam_act_log
          SET mail_sent = 'X'
          WHERE act_id = ls_log-act_id.
      ENDLOOP.

      COMMIT WORK.

    CATCH cx_send_req_bcs
      cx_address_bcs
      cx_document_bcs
      cx_bcs INTO DATA(lx_error).
      MESSAGE lx_error->get_text( ) TYPE 'E'.
  ENDTRY.
ENDFORM.
