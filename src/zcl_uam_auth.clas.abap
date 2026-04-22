class ZCL_UAM_AUTH definition
  public
  final
  create public .

public section.

  types:
    "------------------------------------------------------------------*
    " Type: GTY_INPUT
    "------------------------------------------------------------------*
    BEGIN OF gty_input,
        username TYPE rsau_buf_data-slguser,
        area     TYPE rsau_buf_data-area,
        id       TYPE rsau_buf_data-subid,
        system   TYPE rsau_buf_data-slgmand,
        time     TYPE rsau_buf_data-slgdattim,
        variable TYPE rsau_buf_data-sal_data,
        message  TYPE tsl1t-txt,
      END OF gty_input .
  types:
    "------------------------------------------------------------------*
    " Table Type: GTY_T_INPUT
    "------------------------------------------------------------------*
    gty_t_input TYPE STANDARD TABLE OF gty_input .
  types:
    "------------------------------------------------------------------*
    " Table Type: GTY_LOGOUT
    "------------------------------------------------------------------*
    BEGIN OF gty_logout,
        username TYPE rsau_buf_data-slguser,
        time     TYPE rsau_buf_data-slgdattim,
      END OF gty_logout .

    "------------------------------------------------------------------*
    " Method: CREATE_LOGIN_SUCCESS_LOG
    " Purpose:
    "   Log successful login events into custom audit table
    "------------------------------------------------------------------*
  class-methods CREATE_LOGIN_SUCCESS_LOG .
    "------------------------------------------------------------------*
    " Method: CREATE_LOGIN_FAIL_LOG
    " Purpose:
    "   Log failed login attempts
    "   Data is collected from Security Audit Log (RSAU_BUF_DATA)
    "------------------------------------------------------------------*
  class-methods CREATE_LOGIN_FAIL_LOG
    importing
      !IM_AUTH_FAIL_LOG type GTY_T_INPUT .
    "------------------------------------------------------------------*
    " Method: CONFIG_MESSAGE
    " Purpose:
    "   Generate formatted audit message based on event ID and
    "   input variable values
    "------------------------------------------------------------------*
  class-methods CONFIG_MESSAGE
    importing
      !IM_EVENT_ID type ZUAM_AUTH_LOG-EVENT_ID optional
      !IM_VARIABLE type RSAU_BUF_DATA-SAL_DATA optional
      !IM_MESSAGE type ZUAM_AUTH_LOG-LOGIN_MESSAGE optional
    returning
      value(RE_MESSAGE) type ZUAM_AUTH_LOG-LOGIN_MESSAGE .
    "------------------------------------------------------------------*
    " Method: CREATE_LOGOUT_LOG
    " Purpose:
    "   Update logout time in custom audit table
    "------------------------------------------------------------------*
  class-methods CREATE_LOGOUT_LOG
    importing
      !IM_AUTH_LOGOUT_LOG type GTY_LOGOUT .
protected section.
private section.
ENDCLASS.



CLASS ZCL_UAM_AUTH IMPLEMENTATION.


  METHOD config_message.
  "---------------------------------------------------------------------*
  " Method      : CONFIG_MESSAGE
  " Description : Build audit message based on event ID and variable.
  "               - Parse variable values
  "               - Select audit type/method/cause from config tables
  "               - Replace placeholders (&A, &B, &C, ...)
  "               - Return completed message text
  "---------------------------------------------------------------------*
    "---------------------------------------------------------------------*
    " Data declaration
    "---------------------------------------------------------------------*
    DATA: lv_type   TYPE zuam_msg_type-message,
          lv_method TYPE zuam_msg_method-message,
          lv_cause  TYPE zuam_msg_cause-message.

    re_message = im_message.

    "Wrong Password - Locked Account
    IF im_event_id = 'BU1' OR im_event_id = 'AUM'.
      DATA: lv_var_client   TYPE string,
            lv_var_username TYPE string.

      SPLIT im_variable AT '&' INTO lv_var_client lv_var_username.

      IF sy-subrc = 0.
        REPLACE '&B' IN re_message WITH lv_var_username.
        REPLACE '&A' IN re_message WITH lv_var_client.
      ENDIF.

      "Login Fail - Cause - Type - Method
    ELSEIF im_event_id = 'AU2'.
      DATA: lv_var_type   TYPE string,
            lv_var_method TYPE string,
            lv_var_cause  TYPE string.

      CLEAR: lv_type, lv_method, lv_cause.

      SPLIT im_variable AT '&' INTO lv_var_type lv_var_cause lv_var_method.

      "----------------------*
      " Select data
      "----------------------*
      SELECT SINGLE message
        INTO lv_type
        FROM zuam_msg_type
        WHERE id = lv_var_type.

      SELECT SINGLE message
        INTO lv_method
        FROM zuam_msg_method
        WHERE id = lv_var_method.

      SELECT SINGLE message
        INTO lv_cause
        FROM zuam_msg_cause
        WHERE id = lv_var_cause.

      IF sy-subrc = 0.
        REPLACE '&B' IN re_message WITH lv_cause.
        REPLACE '&A' IN re_message WITH lv_type.
        REPLACE '&C' IN re_message WITH lv_method.
      ENDIF.
    ENDIF.
  ENDMETHOD.


  METHOD create_login_fail_log.
  "---------------------------------------------------------------------*
  " Method      : CREATE_LOGIN_FAIL_LOG
  " Description : Log fail login event (AU2, BU1) for DEV users only
  "---------------------------------------------------------------------*
    "---------------------------------------------------------------------*
    " Data declaration
    "---------------------------------------------------------------------*
    DATA: ls_auth_fail_log TYPE zuam_auth_log,
          lv_session_id    TYPE zuam_auth_log-session_id.

    LOOP AT im_auth_fail_log INTO DATA(ls_input).
      "-------------------------------------------------------------------*
      " Build unique session ID (USER + TIMESTAMP)
      "-------------------------------------------------------------------*
      lv_session_id = |{ ls_input-username }_{ ls_input-time }_{ ls_input-area && ls_input-id }|.

      "-------------------------------------------------------------------*
      " Fill authentication log data
      "-------------------------------------------------------------------*
      CLEAR ls_auth_fail_log.

      ls_auth_fail_log-mandt          = sy-mandt.
      ls_auth_fail_log-username       = ls_input-username.
      ls_auth_fail_log-session_id     = lv_session_id.
      ls_auth_fail_log-login_date     = ls_input-time(8).
      ls_auth_fail_log-login_time     = ls_input-time+8(6).
      ls_auth_fail_log-login_result   = 'FAIL'.
      ls_auth_fail_log-mail_sent      = ''.
      ls_auth_fail_log-login_message  = ls_input-message.
      ls_auth_fail_log-erzet          = ls_input-time+8(6).
      ls_auth_fail_log-erdat          = ls_input-time(8).
      ls_auth_fail_log-event_id       = ls_input-area && ls_input-id.

      "-------------------------------------------------------------------*
      " Build final login message based on event configuration
      "-------------------------------------------------------------------*
      ls_auth_fail_log-login_message =
        zcl_uam_auth=>config_message(
          im_event_id = ls_auth_fail_log-event_id
          im_variable = ls_input-variable
          im_message  = ls_auth_fail_log-login_message ).


      "-------------------------------------------------------------------*
      " Insert authentication fail log record
      "-------------------------------------------------------------------*
      TRY.
          INSERT zuam_auth_log FROM ls_auth_fail_log.

          IF sy-subrc = 0.
            MESSAGE s010(zuam_msg).
          ENDIF.

        CATCH cx_sy_open_sql_db.
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.


  METHOD CREATE_LOGIN_SUCCESS_LOG.
  "---------------------------------------------------------------------*
  " Method      : CREATE_LOGIN_SUCCESS_LOG
  " Description : Log successful login event (AU1) for DEV users only
  "---------------------------------------------------------------------*

    "---------------------------------------------------------------------*
    " Data declaration
    "---------------------------------------------------------------------*
    DATA: ls_auth_log   TYPE zuam_auth_log,
          lv_session_id TYPE zuam_auth_log-session_id.

    DATA: lv_type   TYPE zuam_msg_type-message,
          lv_method TYPE zaudit_method-message.

    DATA: lv_datetime TYPE timestamp,
          lv_terminal TYPE usr41-terminal.

    IF sy-uname CP 'DEV*'.
      "-------------------------------------------------------------------*
      " Select data of type and method
      "-------------------------------------------------------------------*
      CLEAR: lv_type, lv_method.

      SELECT SINGLE message
        INTO lv_type
        FROM zuam_msg_type
        WHERE id = 'A'.

      SELECT SINGLE message
        INTO lv_method
        FROM zuam_msg_method
        WHERE id = 'A'.

      "-------------------------------------------------------------------*
      " Get system date and time
      "-------------------------------------------------------------------*
      GET TIME STAMP FIELD lv_datetime.

      "-------------------------------------------------------------------*
      " Build unique session ID (USER + TIMESTAMP)
      "-------------------------------------------------------------------*
      lv_session_id = |{ sy-uname }_{ lv_datetime }|.

      "-------------------------------------------------------------------*
      " GET SYSTEM INFORMATION
      "-------------------------------------------------------------------*
      CALL FUNCTION 'TERMINAL_ID_GET'
        IMPORTING
          terminal             = lv_terminal
        EXCEPTIONS
          no_terminal_found    = 1
          multiple_terminal_id = 2
          OTHERS               = 3.

      IF sy-subrc <> 0.
        CLEAR lv_terminal.
      ENDIF.

      "-------------------------------------------------------------------*
      " Fill authentication log data
      "-------------------------------------------------------------------*
      CLEAR: ls_auth_log.

      ls_auth_log-mandt          = sy-mandt.
      ls_auth_log-session_id     = lv_session_id.
      ls_auth_log-username       = sy-uname.
      ls_auth_log-login_date     = sy-datum.
      ls_auth_log-login_time     = sy-uzeit.
      ls_auth_log-event_id       = 'AU1'.
      ls_auth_log-login_result   = 'SUCCESS'.
      ls_auth_log-mail_sent      = ''.
      ls_auth_log-terminal_id    = lv_terminal.
      ls_auth_log-client         = sy-mandt.
      ls_auth_log-system_id      = sy-sysid.
      ls_auth_log-erzet          = sy-uzeit.
      ls_auth_log-erdat          = sy-datum.

      "-------------------------------------------------------------------*
      " Read login success message text from TSL1T
      "-------------------------------------------------------------------*
      SELECT SINGLE txt
        INTO ls_auth_log-login_message
        FROM tsl1t
        WHERE area  = ls_auth_log-event_id(2)
          AND subid = ls_auth_log-event_id+2(1)
          AND spras = sy-langu.

      IF sy-subrc = 0.
        REPLACE '&A' IN ls_auth_log-login_message WITH lv_type.
        REPLACE '&C' IN ls_auth_log-login_message WITH lv_method.
      ENDIF.

      "-------------------------------------------------------------------*
      " Insert authentication log record
      "-------------------------------------------------------------------*
      TRY.
          INSERT zuam_auth_log FROM ls_auth_log.
        CATCH cx_sy_open_sql_db.
      ENDTRY.
    ELSE.
      RETURN.
    ENDIF.
  ENDMETHOD.


  METHOD create_logout_log.
  "---------------------------------------------------------------------*
  " Method      : CREATE_LOGOUT_LOG
  " Description : Log logout event (AUC) for DEV users only
  "---------------------------------------------------------------------*

    "---------------------------------------------------------------------*
    " Data declaration
    "---------------------------------------------------------------------*
    DATA(lv_date) = im_auth_logout_log-time(8).
    DATA(lv_time) = im_auth_logout_log-time+8(6).


    DATA: ls_oldest TYPE zuam_auth_log.

    TRY.
        "-------------------------------------------------------------------*
        " Select the latest login_time in table zuam_auth_log
        "-------------------------------------------------------------------*
        SELECT  *
        FROM zuam_auth_log
         WHERE username     = @im_auth_logout_log-username
           AND logout_time  = '000000'
           AND login_result = 'SUCCESS'
           AND login_date   <= @lv_date
           AND login_time   <= @lv_time
         ORDER BY login_time ASCENDING
         INTO @ls_oldest
         UP TO 1 ROWS.
        ENDSELECT.

        "-------------------------------------------------------------------*
        " Update zuam_auth_log
        "-------------------------------------------------------------------*
        IF sy-subrc = 0.
          UPDATE zuam_auth_log
            SET logout_date = @lv_date,
                logout_time = @lv_time
            WHERE session_id = @ls_oldest-session_id.

          IF sy-subrc = 0.
            MESSAGE s017(zua_msg) WITH im_auth_logout_log-username lv_time.
          ENDIF.
        ENDIF.
      CATCH cx_sy_open_sql_db.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
