**---------------------------------------------------------*
** Program ID: ZR_UAM_CREATE_CHECKPOINT
** Program name: ZR_UAM_CREATE_CHECKPOINT
** Created date: 2026-04-16
** Content explanation:
** This program initialize required variables in TVARVC table
** for checkpoint and time control purposes in the system.
** It ensures that predefined variables are created if not existing,
** avoiding duplicate entries and supporting UAM processing logic.
**---------------------------------------------------------*
** <Modification tracking>
** Modification number:
** Modification day:
** Modification reason:
**---------------------------------------------------------*

REPORT zr_uam_create_checkpoint.

*---------------------------------------------------------------------*
* Data declaration
*---------------------------------------------------------------------*
TYPES: BEGIN OF ty_var,
         name        TYPE tvarvc-name,
         type        TYPE tvarvc-type,
         msg_success TYPE symsgno,
         msg_exist   TYPE symsgno,
       END OF ty_var.

DATA: ls_tvarvc TYPE tvarvc,
      lt_var    TYPE STANDARD TABLE OF ty_var.

*---------------------------------------------------------------------*
* Define variables to be initialized
*---------------------------------------------------------------------*
lt_var = VALUE #(
  ( name = 'ZUAM_LOGIN_FAIL_TIME'
    type = 'P'
    msg_success = '000'
    msg_exist   = '001' )

  ( name = 'ZUAM_ACT_TIME'
    type = 'P'
    msg_success = '004'
    msg_exist   = '005' )

  ( name = 'ZUAM_LOGOUT_TIME'
    type = 'P'
    msg_success = '012'
    msg_exist   = '013' )
 ).

*---------------------------------------------------------------------*
* Init TVARVC
*---------------------------------------------------------------------*
LOOP AT lt_var INTO DATA(ls_var).
  CLEAR: ls_tvarvc.

  SELECT SINGLE *
  FROM tvarvc
  WHERE name = @ls_var-name
    AND type = @ls_var-type
  INTO @ls_tvarvc.

  IF sy-subrc <> 0.

    ls_tvarvc-name = ls_var-name.
    ls_tvarvc-type = ls_var-type.
    ls_tvarvc-low  = ''.

    INSERT tvarvc FROM ls_tvarvc.

    MESSAGE ID 'ZUAM_MSG' TYPE 'S' NUMBER ls_var-msg_success.
  ELSE.
    MESSAGE ID 'ZUAM_MSG' TYPE 'S' NUMBER ls_var-msg_exist.
  ENDIF.
ENDLOOP.

COMMIT WORK.
