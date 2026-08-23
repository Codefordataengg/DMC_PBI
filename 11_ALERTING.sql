/* ============================================================================
   DCM DRIFT ALERTING

   Depends on 10_AUDIT_AND_MONITOR.sql.

   DESIGN RULE: the audit row is written BEFORE any attempt to notify, and the
   notify is wrapped in its own handler. A mail failure must never cost us the
   record of what was found. Losing the alert is recoverable - someone reads the
   log. Losing the log is not.

   RUN AS: ACCOUNTADMIN in the POC account.
   ============================================================================ */

USE ROLE ACCOUNTADMIN;

/* ---- 1. Where alerts go ------------------------------------------------
   ALLOWED_RECIPIENTS must be the verified email of a user in THIS account.
   Snowflake silently refuses to mail anywhere else - a useful safety rail and
   an easy thing to be confused by when nothing arrives.                    */

CREATE NOTIFICATION INTEGRATION IF NOT EXISTS NI_DCM_DRIFT_EMAIL
    TYPE    = EMAIL
    ENABLED = TRUE
    ALLOWED_RECIPIENTS = ('amitbhopte099@gmail.com')
    COMMENT = 'DCM drift alerts.';


/* ---- 2. The message body -----------------------------------------------
   Written for someone reading it on a phone with no context. It answers, in
   order: how bad, which database, what changed, what to do.

   The column detail comes from V_DCM_DRIFT_COLUMNS, which already translates
   the plan's point of view into what a person actually did.                */

CREATE OR REPLACE FUNCTION DCM_ADMIN.AUDIT.FN_DRIFT_ALERT_BODY(CHECK_ID NUMBER)
RETURNS VARCHAR
AS
$$
SELECT
    CASE l.VERDICT
      WHEN 'ERROR' THEN
        'DCM DRIFT CHECK: ERROR - drift exists and CANNOT be auto-reverted.'
        || '\n\nThis is the most serious outcome, not a broken job. PLAN failed to'
        || '\ncompile, which means a hand-made change cannot be undone by DEPLOY'
        || '\n(a dropped middle column, or a widened VARCHAR). It also means any'
        || '\nother drift behind it in the same file went unchecked.'
        || '\n\nProject : ' || l.PROJECT_NAME
        || '\nChecked : ' || l.CHECKED_AT_UTC::VARCHAR || ' UTC'
        || '\nQuery   : ' || COALESCE(l.PLAN_QUERY_ID,'-')
        || '\n\nError:\n' || COALESCE(l.ERROR_MESSAGE,'-')
        || '\n\nRecovery is manual: unload the table, drop it, redeploy, reload.'
        || '\nSee snowflake-dcm/FINDINGS.md F4 and F7.'
      WHEN 'DRIFT' THEN
        'DCM DRIFT CHECK: ' || l.ENTITIES_CHANGED::VARCHAR
        || ' object(s) no longer match the repo.'
        || '\n\nProject : ' || l.PROJECT_NAME
        || '\nChecked : ' || l.CHECKED_AT_UTC::VARCHAR || ' UTC'
        || '\n\nWhat changed:\n'
        || COALESCE(
             (SELECT LISTAGG('  - ' || c.OBJECT_FQN || '.' || c.COLUMN_NAME
                             || '  ' || c.WHAT_A_HUMAN_DID
                             || '  (' || COALESCE(c.DATATYPE,'?') || ')',
                             '\n') WITHIN GROUP (ORDER BY c.OBJECT_FQN, c.COLUMN_NAME)
              FROM DCM_ADMIN.AUDIT.V_DCM_DRIFT_COLUMNS c
              WHERE c.CHECK_ID = l.CHECK_ID),
             '  (object-level change, no column detail)')
        || '\n\nThis is revertible. Review the plan, then DEPLOY to restore.'
        || '\nDEPLOY drops columns and destroys their data - read before running.'
      ELSE
        'DCM DRIFT CHECK: CLEAN. ' || l.PROJECT_NAME
    END
FROM DCM_ADMIN.AUDIT.CTL_DCM_DRIFT_LOG l
WHERE l.CHECK_ID = CHECK_ID
$$;


/* ---- 3. Check-and-alert -------------------------------------------------
   Wraps the drift check. Alerts on DRIFT and ERROR; stays silent on CLEAN.

   Silence on CLEAN is deliberate. A nightly "all good" mail trains people to
   filter the sender, and then the one that matters is filtered too. The
   never-ran case is covered by the freshness query in section 5, not by noise.  */

CREATE OR REPLACE PROCEDURE DCM_ADMIN.AUDIT.SP_DCM_DRIFT_CHECK_AND_ALERT(
    PROJECT_NAME STRING,
    SOURCE_PATH  STRING,
    RECIPIENT    STRING
)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_result   STRING;
    v_check_id NUMBER;
    v_verdict  STRING;
    v_body     STRING;
    v_subject  STRING;
BEGIN
    /* 1. Do the check. This writes the durable row. */
    CALL DCM_ADMIN.AUDIT.SP_DCM_DRIFT_CHECK(:PROJECT_NAME, :SOURCE_PATH) INTO :v_result;

    /* Take the id the check itself reports. Do NOT look up "the latest row":
       CHECK_ID is not monotonic across sessions (F8), so ORDER BY CHECK_ID DESC
       can return an older row - which silently suppressed a DRIFT alert while
       returning 'no alert sent' as though nothing was wrong. */
    v_check_id := SPLIT_PART(:v_result, '|', 1)::NUMBER;
    v_verdict  := SPLIT_PART(:v_result, '|', 2);
    v_result   := :v_verdict || ' | entities=' || SPLIT_PART(:v_result, '|', 3);

    IF (:v_verdict = 'CLEAN') THEN
        RETURN :v_result || ' | no alert sent';
    END IF;

    /* 2. Only now attempt to notify. If this throws, the audit row survives. */
    BEGIN
        SELECT DCM_ADMIN.AUDIT.FN_DRIFT_ALERT_BODY(:v_check_id) INTO :v_body;
        v_subject := '[' || :v_verdict || '] Snowflake schema drift - ' || :PROJECT_NAME;

        CALL SYSTEM$SEND_EMAIL('NI_DCM_DRIFT_EMAIL', :RECIPIENT, :v_subject, :v_body);

        UPDATE DCM_ADMIN.AUDIT.CTL_DCM_DRIFT_LOG
           SET NOTIFIED = TRUE
         WHERE CHECK_ID = :v_check_id;

        RETURN :v_result || ' | alert sent';
    EXCEPTION
        WHEN OTHER THEN
            /* NOTIFIED stays FALSE. Section 5 surfaces unnotified findings, so a
               mail outage degrades to "nobody was told" rather than "nobody knows". */
            RETURN :v_result || ' | ALERT FAILED: ' || SQLERRM;
    END;
END;
$$;


/* ---- 4. THE TASK IS NOT DEFINED HERE ------------------------------------

   It lives in 12_GIT_INTEGRATION.sql section 6, and NOWHERE ELSE.

   This file used to carry its own CREATE OR REPLACE TASK. Re-running it to add
   a column silently did two things: repointed the task at a stage that had since
   been dropped, and reset it to SUSPENDED - because CREATE OR REPLACE TASK
   always creates suspended, whatever the previous state was.

   The task then missed its 05:00 run and nothing noticed for 22 hours.
   See FINDINGS.md F9.

   Rule: one object, one owning file. If you need to change the task, change it
   where it is defined.
                                                                          ---- */

/* ---- 5. The watcher's watcher -------------------------------------------
   Everything above alerts when the check RUNS and finds something. Nothing
   above alerts when the check STOPS RUNNING - and a suspended task is silent
   in exactly the way a passing one is.

   That distinction is the whole reason PRE.CTL_PBI_GOVERNANCE_HEARTBEAT exists
   in the governance chain: Matillion alerts on failure, nothing alerted on
   never-started, and that silence hid the dashboard freeze for seven months.

   Query this from outside, or schedule it on a different cadence.           */

/* A finding stays outstanding until someone deals with it. ACKNOWLEDGED_AT is
   how a human closes one WITHOUT claiming an alert was sent - marking a test row
   NOTIFIED=TRUE would be a lie, and lying to the audit trail to silence a
   dashboard is how monitors stop meaning anything. */
ALTER TABLE DCM_ADMIN.AUDIT.CTL_DCM_DRIFT_LOG
    ADD COLUMN IF NOT EXISTS ACKNOWLEDGED_AT TIMESTAMP_NTZ(9);
ALTER TABLE DCM_ADMIN.AUDIT.CTL_DCM_DRIFT_LOG
    ADD COLUMN IF NOT EXISTS ACKNOWLEDGED_NOTE VARCHAR(1000);

CREATE OR REPLACE VIEW DCM_ADMIN.AUDIT.V_DCM_MONITOR_HEALTH AS
WITH last_check AS (
    /* Recency comes from the timestamp, never from CHECK_ID - see F8. */
    SELECT VERDICT, CHECKED_AT_UTC
    FROM   DCM_ADMIN.AUDIT.CTL_DCM_DRIFT_LOG
    ORDER  BY CHECKED_AT_UTC DESC
    LIMIT  1
), next_run AS (
    /* A RESUMED task has a future SCHEDULED row here. A SUSPENDED task has
       nothing at all - which is precisely the state that previously read as OK.
       Log recency alone cannot tell "ran and found nothing" from "did not run". */
    SELECT MIN(SCHEDULED_TIME) AS NEXT_SCHEDULED_TIME
    FROM   TABLE(DCM_ADMIN.INFORMATION_SCHEMA.TASK_HISTORY(
                 TASK_NAME => 'TASK_DCM_DRIFT_CHECK', RESULT_LIMIT => 20))
    WHERE  STATE = 'SCHEDULED'
), outstanding AS (
    SELECT COUNT(*) AS N
    FROM   DCM_ADMIN.AUDIT.CTL_DCM_DRIFT_LOG
    WHERE  VERDICT <> 'CLEAN' AND NOT NOTIFIED AND ACKNOWLEDGED_AT IS NULL
)
SELECT
    lc.CHECKED_AT_UTC                                          AS LAST_CHECK_UTC,
    DATEDIFF('hour', lc.CHECKED_AT_UTC, SYSDATE())             AS HOURS_SINCE_LAST_CHECK,
    lc.VERDICT                                                 AS LAST_VERDICT,
    nr.NEXT_SCHEDULED_TIME                                     AS NEXT_RUN_UTC,
    o.N                                                        AS UNNOTIFIED_FINDINGS,
    CASE
      /* Ordered by severity. "Not scheduled" outranks everything, because a
         suspended monitor makes every other field on this row meaningless. */
      WHEN nr.NEXT_SCHEDULED_TIME IS NULL          THEN 'TASK_NOT_SCHEDULED'
      WHEN lc.CHECKED_AT_UTC IS NULL               THEN 'NEVER_RUN'
      /* 26h, not 30h. A daily task may run a little late; it may not miss a
         whole day. The old 30h window let a fully missed run read as OK. */
      WHEN DATEDIFF('hour', lc.CHECKED_AT_UTC, SYSDATE()) > 26 THEN 'STALE'
      WHEN o.N > 0                                 THEN 'FINDINGS_UNNOTIFIED'
      WHEN lc.VERDICT <> 'CLEAN'                   THEN 'DRIFT_OPEN'
      ELSE 'OK'
    END                                                        AS HEALTH
FROM last_check lc, next_run nr, outstanding o;
