**---------------------------------------------------------*
** Program ID: ZB_UAM_READ_LOGIN_FAIL
** Program name: ZB_UAM_READ_LOGIN_FAIL
** Created date: 2026-04-16
** Content explanation:
** This program reads login failure logs from Security Audit Log
** (RSAU_BUF_DATA) based on a checkpoint stored in TVARVC.
**
** On first execution, it initializes the checkpoint with the current timestamp.
** On subsequent runs, it retrieves only new log entries after the last checkpoint.
** Finally, updates the checkpoint in TVARTC to ensure incremental processing.
**---------------------------------------------------------*
** <Modification tracking>
** Modification number:
** Modification day:
** Modification reason:
**---------------------------------------------------------*

REPORT zuam_read_login_fail.

*---------------------------------------------------------------------*
* Data declaration
*---------------------------------------------------------------------*
TYPES: BEGIN OF lty_t_buff_data,
         username TYPE rsau_buf_data-slguser,
         area     TYPE rsau_buf_data-area,
         id       TYPE rsau_buf_data-subid,
         system   TYPE rsau_buf_data-slgmand,
         time     TYPE rsau_buf_data-slgdattim,
         variable TYPE rsau_buf_data-sal_data,
         message  TYPE tsl1t-txt,
       END OF lty_t_buff_data.

DATA: lv_low      TYPE tvarvc-low,
      lv_max_time TYPE tvarvc-low.

DATA: lt_buf_data TYPE STANDARD TABLE OF lty_t_buff_data,
      lt_log_fail TYPE STANDARD TABLE OF lty_t_buff_data.

START-OF-SELECTION.
  PERFORM read_checkpoint.
  PERFORM init_first_run.
  PERFORM read_login_fail.
  PERFORM save_checkpoint.
  PERFORM output_result.

*&---------------------------------------------------------------------*
*& Form READ_CHECKPOINT>
*&---------------------------------------------------------------------*
* Read Checkpoint from table TVARTC
*----------------------------------------------------------------------*
FORM read_checkpoint .
  SELECT SINGLE low
    INTO lv_low
    FROM tvarvc
    WHERE name = 'ZUAM_LOGIN_FAIL_TIME'
    AND type = 'P'.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form INIT_FIRST_RUN
*&---------------------------------------------------------------------*
*& First run → save current timestamp & exit
*&---------------------------------------------------------------------*
FORM init_first_run .
  DATA: lv_date TYPE dats,
        lv_time TYPE tims.

  "If lv_low is existed
  IF lv_low IS NOT INITIAL.
    MESSAGE s008(zuam_msg) WITH lv_low.

    RETURN.
  ENDIF.

  "If lv_low does not exist
  GET TIME.
  lv_date = sy-datum.
  lv_time = sy-uzeit.

  lv_low = lv_date && lv_time && '00'.

  lv_max_time = lv_low.

  UPDATE tvarvc
    SET low = lv_low
    WHERE name = 'ZUAM_LOGIN_FAIL_TIME'
    AND type = 'P'.

  IF sy-subrc = 0.
    COMMIT WORK.

    MESSAGE s002(zuam_msg) WITH lv_low.
  ELSE.
    MESSAGE e003(zuam_msg).
  ENDIF.

  LEAVE PROGRAM.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form READ_LOGIN_FAIL
*&---------------------------------------------------------------------*
*& Get data from RSAU_BUF_DATA
*&---------------------------------------------------------------------*
FORM read_login_fail .
  SELECT slguser   AS username
         area
         subid     AS id
         slgmand   AS system
         slgdattim AS time
         sal_data  AS variable
  FROM rsau_buf_data
  INTO CORRESPONDING FIELDS OF TABLE lt_buf_data
  PACKAGE SIZE 1000
  WHERE slgdattim > lv_low
    AND (
        ( area = 'AU' AND subid IN ('2', 'M') )
     OR ( area = 'BU' AND subid = '1' )
  ).

    LOOP AT lt_buf_data INTO DATA(ls_buf_data).
      IF ls_buf_data-username CP 'DEV*'
        AND ls_buf_data-username <> 'DEV-999'
        AND ls_buf_data-time > lv_low.

        "Get message from TSL1T
        SELECT SINGLE txt
          FROM tsl1t
          INTO ls_buf_data-message
          WHERE area = ls_buf_data-area
           AND subid = ls_buf_data-id
           AND spras = 'E'.

        APPEND ls_buf_data TO lt_log_fail.

        "Set new checkpoint
        IF ls_buf_data-time > lv_max_time.
          lv_max_time = ls_buf_data-time.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDSELECT.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form SAVE_CHECKPOINT
*&---------------------------------------------------------------------*
*& Update checkpoint
*&---------------------------------------------------------------------*
FORM save_checkpoint .

  IF lv_max_time IS NOT INITIAL.
    UPDATE tvarvc
      SET low = lv_max_time
      WHERE name = 'ZAUM_LOGIN_FAIL_TIME'
      AND type = 'P'.

    COMMIT WORK.

    MESSAGE s009(zuam_msg) WITH lv_max_time.
  ELSE.
    RETURN.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form OUTPUT_RESULT
*&---------------------------------------------------------------------*
*& Insert data into Table
*&---------------------------------------------------------------------*
FORM output_result .
  zcl_uam_auth=>create_login_fail_log(
    im_auth_fail_log = lt_log_fail
  ).

*  cl_demo_output=>display( lt_log_fail ).
ENDFORM.
