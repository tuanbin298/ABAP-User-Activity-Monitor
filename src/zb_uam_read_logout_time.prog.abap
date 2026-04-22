**---------------------------------------------------------*
** Program ID: ZB_UAM_READ_LOGOUT_TIME
** Program name: ZB_UAM_READ_LOGOUT_TIME
** Created date: 2026-04-16
** Content explanation:
** This program reads user logout logs from Security Audit Log
**(RSAU_BUF_DATA) based on a checkpoint stored in TVARVC .
**
** On first execution, it initializes the checkpoint with the current timestamp.
** On subsequent runs, it reads only new logout logs (Area 'AU', Subid 'C') after the last checkpoint.
** Finally, updates the checkpoint after processing to ensure incremental processing.
**---------------------------------------------------------*
** <Modification tracking>
** Modification number:
** Modification day:
** Modification reason:
**---------------------------------------------------------*

REPORT zb_uam_read_logout_time.

*---------------------------------------------------------------------*
* Data declaration
*---------------------------------------------------------------------*
TYPES: BEGIN OF lty_t_buff_data,
         username TYPE rsau_buf_data-slguser,
         time     TYPE rsau_buf_data-slgdattim,
       END OF lty_t_buff_data.

DATA: lv_low      TYPE tvarvc-low,
      lv_max_time TYPE tvarvc-low.

DATA: lt_logout TYPE STANDARD TABLE OF lty_t_buff_data.

START-OF-SELECTION.
  PERFORM read_checkpoint.
  PERFORM init_first_run.
  PERFORM read_logout.
  PERFORM save_checkpoint.

*&---------------------------------------------------------------------*
*& Form READ_CHECKPOINT
*&---------------------------------------------------------------------*
*& Read checkpoint from TVARVC
*&---------------------------------------------------------------------*
FORM read_checkpoint .
  SELECT SINGLE low
    FROM tvarvc
    INTO lv_low
    WHERE name = 'ZUAM_LOGOUT_TIME'
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

  IF lv_low IS NOT INITIAL.
    MESSAGE s014(zuam_msg) WITH lv_low.

    RETURN.
  ENDIF.

  GET TIME.
  lv_date = sy-datum.
  lv_time = sy-uzeit.

  lv_low = lv_date && lv_time && '00'.

  lv_max_time = lv_low.

  UPDATE tvarvc
    SET low = lv_low
    WHERE name = 'ZUAM_LOGOUT_TIME'
    AND type = 'P'.

  IF sy-subrc = 0.
    COMMIT WORK.

    MESSAGE s015(zuam_msg) WITH lv_low.
  ELSE.
    MESSAGE e016(zuam_msg).
  ENDIF.

  LEAVE PROGRAM.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form READ_LOGOUT
*&---------------------------------------------------------------------*
*& Get data from RSAU_BUF_DATA
*&---------------------------------------------------------------------*
FORM read_logout .
  SELECT slguser   AS username
         slgdattim AS time
  FROM rsau_buf_data
  INTO TABLE lt_logout
  WHERE slgmand   = sy-mandt
   AND slgdattim > lv_low
   AND area      = 'AU'
   AND subid     = 'C'
  ORDER BY slgdattim ASCENDING.

  LOOP AT lt_logout INTO DATA(ls_logout).
    "Set new checkpoint
    IF ls_logout-time > lv_max_time.
      lv_max_time = ls_logout-time.
    ENDIF.

    "Update logout time into zuam_auth_log
    zcl_uam_auth=>create_logout_log(
      im_auth_logout_log = ls_logout
    ).

  ENDLOOP.

*    cl_demo_output=>display( lt_logout ).
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
      WHERE name = 'ZAUM_LOGOUT_TIME'
      AND type = 'P'.

    COMMIT WORK.

    MESSAGE s009(zuam_msg) WITH lv_max_time.
  ELSE.
    RETURN.
  ENDIF.
ENDFORM.
