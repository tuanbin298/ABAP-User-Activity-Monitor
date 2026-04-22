**---------------------------------------------------------*
** Program ID: ZB_UAM_READ_ACT_TIME
** Program name: ZB_UAM_READ_ACT_TIME
** Created by: DEV-058
** Created date: 2026-04-16
** Content explanation: Synchronize Security Audit Log and Dump
** to ZUSR_ACT_LOG table.
**---------------------------------------------------------*
** <Modification tracking>
** Modification number:
** Modification day:
** Modification reason:
**
**---------------------------------------------------------*
REPORT zb_uam_read_act_time.

*---------------------------------------------------------------------*
* Data declaration
*-------------------------------------------------------
DATA: lv_low      TYPE tvarvc-low,  " Lower limit time from TVARVC
      lv_max_time TYPE tvarvc-low.  " Maximum time of processed logs

DATA: lt_sal TYPE TABLE OF rsau_buf_data, " Internal table for Audit Log
      lt_log TYPE TABLE OF zuam_act_log,  " Internal table for Activity Log
      ls_log TYPE zuam_act_log.           " Work area for Activity Log

START-OF-SELECTION.
  " Read last sync time from TVARVC
  PERFORM read_checkpoint.

  " Initialize timestamp for the first run
  PERFORM init_first_run.

  " Extract and parse Security Audit Logs
  PERFORM process_sal_log.

  " Extract and parse Short Dumps (SNAP)
  PERFORM process_snap_dump.

  " Save synchronized logs to custom DB table
  PERFORM save_to_database.

  " Update max sync time back to TVARVC
  PERFORM save_checkpoint.

*&---------------------------------------------------------------------*
*& Form <READ_CHECKPOINT>
*&---------------------------------------------------------------------*
* Read checkpoint from TVARVC table
*----------------------------------------------------------------------*
* No parameters
*----------------------------------------------------------------------*
FORM read_checkpoint .
  SELECT SINGLE low
  INTO lv_low
  FROM tvarvc
  WHERE name = 'ZUAM_ACT_TIME'
  AND type = 'P'.
ENDFORM.
*&---------------------------------------------------------------------*
*& Form <INIT_FIRST_RUN>
*&---------------------------------------------------------------------*
* Update highest timestamp to TVARVC table
*----------------------------------------------------------------------*
* No parameters
*----------------------------------------------------------------------*
FORM init_first_run .
  DATA: lv_date TYPE dats,
        lv_time TYPE tims.

  IF lv_low IS NOT INITIAL.
    MESSAGE s011(zuam_msg) WITH lv_low.
  ELSE.

    GET TIME.
    lv_date = sy-datum.
    lv_time = sy-uzeit.

    lv_low = lv_date && lv_time && '00'.

    lv_max_time = lv_low.

    UPDATE tvarvc
      SET low = lv_low
      WHERE name = 'ZUAM_ACT_TIME'
        AND type = 'P'.

    IF sy-subrc = 0.
      COMMIT WORK.

      MESSAGE s006(zuam_msg) WITH lv_low.
    ELSE.
      MESSAGE e007(zuam_msg).
    ENDIF.
    LEAVE PROGRAM.
  ENDIF.
ENDFORM.
*&---------------------------------------------------------------------*
*& Form <PROCESS_SAL_LOG>
*&---------------------------------------------------------------------*
* Get data from RSAU_BUF_DATA
*----------------------------------------------------------------------*
* No parameters
*----------------------------------------------------------------------*
FORM process_sal_log .
  SELECT *
    FROM rsau_buf_data
    WHERE slgmand = @sy-mandt
      AND slgdattim > @lv_low
      AND ( ( area IN ('AU', 'CU', 'DU') AND subid <> '2')
         OR ( area = 'BU' AND subid = '4' ) )
      AND slgtc <> 'S000'
      AND slgtc <> 'SEU_INT'
      AND slgtc <> 'SESSION_MANAGER'
      AND slgtc IS NOT INITIAL
    INTO TABLE @lt_sal.

  LOOP AT lt_sal INTO DATA(ls_sal).

    CLEAR ls_log.

    DATA(lv_act_date) = ls_sal-slgdattim(8).
    DATA(lv_act_time) = ls_sal-slgdattim+8(6).
    IF ls_sal-slgdattim > lv_max_time.
      lv_max_time = ls_sal-slgdattim.
    ENDIF.
    " Find active session
    SELECT session_id
    FROM zuam_auth_log
    WHERE username = @ls_sal-slguser
      AND (
            ( login_date <  @lv_act_date )
         OR ( login_date =  @lv_act_date
              AND login_time <= @lv_act_time )
          )
      AND (
            logout_date IS INITIAL
         OR logout_date >  @lv_act_date
         OR ( logout_date = @lv_act_date
              AND logout_time >= @lv_act_time )
          )
      AND login_result = 'SUCCESS'
      ORDER BY login_date DESCENDING, login_time DESCENDING
      INTO TABLE @DATA(lt_active_session)
      UP TO 1 ROWS.

    IF sy-subrc = 0.
      ls_log-session_id = lt_active_session[ 1 ]-session_id.
    ELSE.
      CONTINUE.
    ENDIF.

    " Calculate MD5 Hash to generate unique Activity Id (Prevent duplicates)
    DATA(lv_raw_data) = |{ ls_sal-slgdattim }{ ls_sal-slguser }{ ls_sal-slgtc }{ ls_sal-area }{ ls_sal-subid }{ ls_sal-sal_data }|.
    DATA lv_guid TYPE sysuuid_c32.
    CALL FUNCTION 'MD5_CALCULATE_HASH_FOR_CHAR'
      EXPORTING
        data = lv_raw_data
      IMPORTING
        hash = lv_guid.

    " Map Security Audit Log (SAL) data to Activity Log
    ls_log-act_id         = lv_guid.
    ls_log-mandt          = sy-mandt.
    ls_log-username       = ls_sal-slguser.
    ls_log-tcode          = ls_sal-slgtc.
    ls_log-act_tims       = lv_act_time.
    ls_log-act_date       = lv_act_date.
    ls_log-act_type       = 'TCODE'.
    ls_log-message_text   = zcl_uam_act=>parse_audit_message( im_area     = ls_sal-area
                                                              im_subid    = ls_sal-subid
                                                              im_sal_data = ls_sal-sal_data
                                                             ).

    IF ls_log-message_text CS '====CM' OR
       ls_log-message_text CS '====CC' OR
       ls_log-message_text CS '====CU'.
      CONTINUE.
    ENDIF.
    APPEND ls_log TO lt_log.

  ENDLOOP.

ENDFORM.
*&---------------------------------------------------------------------*
*& Form <PROCESS_SNAP_DUMP>
*&---------------------------------------------------------------------*
* Get data from SNAP (Dump)
*----------------------------------------------------------------------*
* No parameters
*----------------------------------------------------------------------*
FORM process_snap_dump .

  DATA: lt_dump TYPE TABLE OF snap,
        ls_dump TYPE snap.
  DATA(lv_cp_date) = lv_low(8).
  DATA(lv_cp_time) = lv_low+8(6).

  SELECT *
    INTO TABLE @lt_dump
    FROM snap
    WHERE mandt = @sy-mandt
      AND seqno = '000'
      AND ( datum > @lv_cp_date
         OR ( datum = @lv_cp_date
              AND uzeit > @lv_cp_time ) ).

  IF lt_dump IS NOT INITIAL.
    SORT lt_dump BY datum uzeit uname.
    DELETE ADJACENT DUPLICATES FROM lt_dump
           COMPARING datum uzeit uname.
  ENDIF.

  LOOP AT lt_dump INTO ls_dump.

    CLEAR ls_log.

    " Build dump timestamp
    DATA lv_dump_ts TYPE tvarvc-low.
    lv_dump_ts = ls_dump-datum && ls_dump-uzeit && '00'.

    " Update checkpoint max time
    IF lv_dump_ts > lv_max_time.
      lv_max_time = lv_dump_ts.
    ENDIF.

    DATA(lv_dump_date) = ls_dump-datum.
    DATA(lv_dump_time) = ls_dump-uzeit.

    " Find active session at dump time (date + time)
    SELECT session_id
      FROM zuam_auth_log
      WHERE username = @ls_dump-uname
        AND (
              ( login_date <  @lv_dump_date )
           OR ( login_date =  @lv_dump_date
                AND login_time <= @lv_dump_time )
            )
        AND (
              logout_date IS INITIAL
           OR logout_date >  @lv_dump_date
           OR ( logout_date = @lv_dump_date
                AND logout_time >= @lv_dump_time )
            )
      AND login_result = 'SUCCESS'
      ORDER BY login_date DESCENDING, login_time DESCENDING
      INTO TABLE @DATA(lt_active_session)
      UP TO 1 ROWS.

    IF sy-subrc = 0.
      ls_log-session_id = lt_active_session[ 1 ]-session_id.
    ELSE.
      CONTINUE.
    ENDIF.

    " Calculate MD5 Hash to generate unique Activity Id (Prevent duplicates)
    DATA(lv_raw_dump) = |{ lv_dump_ts }{ ls_dump-uname }{ ls_dump-ahost }{ ls_dump-modno }|.
    DATA lv_guid_dump TYPE sysuuid_c32.

    CALL FUNCTION 'MD5_CALCULATE_HASH_FOR_CHAR'
      EXPORTING
        data = lv_raw_dump
      IMPORTING
        hash = lv_guid_dump.
    DATA: lv_dump_tcode TYPE string.

    " Map Dump details to Activity Log
    ls_log-act_id        = lv_guid_dump.
    ls_log-mandt         = sy-mandt.
    ls_log-username      = ls_dump-uname.
    ls_log-act_tims      = lv_dump_time.
    ls_log-act_date      = lv_dump_date.
    ls_log-act_type      = 'DUMP'.
    ls_log-message_text  = zcl_uam_act=>parse_dump_message( EXPORTING im_flist = CONV string( ls_dump-flist )
                                                            IMPORTING ex_tcode = lv_dump_tcode
                                                           ).
    ls_log-tcode = lv_dump_tcode.

    APPEND ls_log TO lt_log.

  ENDLOOP.

ENDFORM.
*&---------------------------------------------------------------------*
*&---------------------------------------------------------------------*
*& Form <SAVE_CHECKPOINT>
*&---------------------------------------------------------------------*
* <Update checkpoint>
*----------------------------------------------------------------------*
* No parameters
*----------------------------------------------------------------------*
FORM save_checkpoint .

  IF lv_max_time IS NOT INITIAL.

    UPDATE tvarvc
      SET low = lv_max_time
      WHERE name = 'ZUAM_ACT_TIME'
      AND type = 'P'.

    COMMIT WORK.

    MESSAGE s009(zuam_msg) WITH lv_max_time.
  ELSE.
    RETURN.
  ENDIF.

ENDFORM.
*&---------------------------------------------------------------------*
*& Form <SAVE_TO_DATABASE>
*&---------------------------------------------------------------------*
* Save to database
*----------------------------------------------------------------------*
* No parameters
*----------------------------------------------------------------------*
FORM save_to_database .

  IF lt_log IS NOT INITIAL.
    SORT lt_log BY act_date DESCENDING act_tims DESCENDING.
    INSERT zuam_act_log FROM TABLE lt_log ACCEPTING DUPLICATE KEYS.
  ENDIF.

ENDFORM.
