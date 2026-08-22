/* ============================================================================
   DCM AUDIT + DRIFT MONITOR

   WHY THIS EXISTS
   ---------------
   DCM records DEPLOY operations and never records PLAN operations (FINDINGS.md
   F6, verified: 7+ plans and 4 deploys produced 4 rows, all DEPLOY). The drift
   check is therefore the one operation Snowflake does not remember — and drift
   detection is the entire reason we adopted DCM.

   Native trail also caps at 12 months with no ACCOUNT_USAGE equivalent.

   So this file adds the missing half: a durable record of every drift check,
   and an alert that distinguishes the three outcomes.

   THE THREE OUTCOMES (FINDINGS.md F4)
   -----------------------------------
     CLEAN  changeset empty                    database matches the repo
     DRIFT  changeset non-empty                someone changed something
     ERROR  PLAN itself failed to compile      drift exists, CANNOT be auto-reverted,
                                               and it is HIDING any other drift

   A monitor that only asks "did the changeset have rows?" reads ERROR as a broken
   job rather than the worst of the three. That is alert-then-succeed wearing a
   different hat, and it is what hid the dashboard freeze for seven months.

   RUN AS: ACCOUNTADMIN in the POC account (LV16268).
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

CREATE SCHEMA IF NOT EXISTS DCM_ADMIN.AUDIT
    COMMENT = 'Durable record of DCM drift checks. Fills the gap left by F6.';


/* ============================================================================
   1. THE LOG — one row per drift check, forever
   ============================================================================ */

CREATE TABLE IF NOT EXISTS DCM_ADMIN.AUDIT.CTL_DCM_DRIFT_LOG (
    CHECK_ID          NUMBER(38,0)  IDENTITY START 1 INCREMENT 1,
    PROJECT_NAME      VARCHAR(500)  NOT NULL,
    SOURCE_PATH       VARCHAR(1000) NOT NULL,
    CHECKED_AT_UTC    TIMESTAMP_NTZ(9) NOT NULL,
    DURATION_MS       NUMBER(38,0),
    VERDICT           VARCHAR(10)   NOT NULL,   -- CLEAN | DRIFT | ERROR
    ENTITIES_CHANGED  NUMBER(38,0)  NOT NULL DEFAULT 0,
    CHANGESET         VARIANT,                  -- full plan changeset, NULL on ERROR
    ERROR_MESSAGE     VARCHAR(5000),            -- populated only on ERROR
    PLAN_QUERY_ID     VARCHAR(100),
    NOTIFIED          BOOLEAN       DEFAULT FALSE
);

COMMENT ON TABLE DCM_ADMIN.AUDIT.CTL_DCM_DRIFT_LOG IS
  'Append-only. One row per PLAN executed as a drift check. Answers "when did this drift start?" - the question the dashboard-freeze incident turned on, and the one DCM cannot answer natively.';


/* ============================================================================
   2. VIEWS — turn the changeset JSON into something a human reads

   Object grain and column grain. The column grain is the one that matters:
   F5 proved DCM names the column and its datatype, and an alert that says
   "someone added HAND_ADDED_BY_A_HUMAN to DIM_PBI_CAPACITIES" is actionable
   at 3am in a way that "2 entities differ" is not.
   ============================================================================ */

CREATE OR REPLACE VIEW DCM_ADMIN.AUDIT.V_DCM_DRIFT_OBJECTS AS
SELECT  l.CHECK_ID,
        l.PROJECT_NAME,
        l.CHECKED_AT_UTC,
        l.VERDICT,
        c.value:type::VARCHAR              AS ACTION,
        c.value:object_id:domain::VARCHAR  AS OBJECT_DOMAIN,
        c.value:object_id:fqn::VARCHAR     AS OBJECT_FQN
FROM    DCM_ADMIN.AUDIT.CTL_DCM_DRIFT_LOG l,
        LATERAL FLATTEN(input => l.CHANGESET, outer => TRUE) c
WHERE   l.CHANGESET IS NOT NULL;

CREATE OR REPLACE VIEW DCM_ADMIN.AUDIT.V_DCM_DRIFT_COLUMNS AS
SELECT  l.CHECK_ID,
        l.PROJECT_NAME,
        l.CHECKED_AT_UTC,
        obj.value:object_id:fqn::VARCHAR    AS OBJECT_FQN,
        col.value:item_id::VARCHAR          AS COLUMN_NAME,
        col.value:kind::VARCHAR             AS PLAN_ACTION,  -- what DCM would DO
        /* PLAN_ACTION is written from the plan's point of view, which is the
           OPPOSITE of what the human did: DCM says "removed" about a column a
           person ADDED. An alert phrased in plan language reads backwards to
           whoever is woken up by it, so translate it here, once. */
        CASE col.value:kind::VARCHAR
             WHEN 'removed'  THEN 'ADDED BY HAND'
             WHEN 'added'    THEN 'DROPPED BY HAND'
             WHEN 'modified' THEN 'ALTERED BY HAND'
             ELSE col.value:kind::VARCHAR
        END                                 AS WHAT_A_HUMAN_DID,
        /* On 'removed' the attribute carries prev_value; on 'added' it carries value.
           COALESCE so one column reads for both directions. */
        COALESCE(attr.value:value::VARCHAR,
                 attr.value:prev_value::VARCHAR) AS DATATYPE
FROM    DCM_ADMIN.AUDIT.CTL_DCM_DRIFT_LOG l,
        LATERAL FLATTEN(input => l.CHANGESET,           outer => TRUE) obj,
        LATERAL FLATTEN(input => obj.value:changes,     outer => TRUE) coll,
        LATERAL FLATTEN(input => coll.value:changes,    outer => TRUE) col,
        LATERAL FLATTEN(input => col.value:changes,     outer => TRUE) attr
WHERE   l.CHANGESET IS NOT NULL
  AND   coll.value:collection_name::VARCHAR = 'columns'
  AND   attr.value:attribute_name::VARCHAR  = 'datatype';

/* outer => TRUE on every flatten, per the house rule. Without it an object with
   no column-level changes vanishes from the view entirely, and a silently
   missing row in a drift report is worse than a noisy one. */


/* ============================================================================
   3. THE DRIFT CHECK PROCEDURE
   ============================================================================ */

CREATE OR REPLACE PROCEDURE DCM_ADMIN.AUDIT.SP_DCM_DRIFT_CHECK(
    PROJECT_NAME STRING,
    SOURCE_PATH  STRING
)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_start    TIMESTAMP_NTZ DEFAULT SYSDATE();
    v_sql      STRING;
    v_json     STRING  DEFAULT NULL;
    v_verdict  STRING;
    v_n        INTEGER DEFAULT 0;
    v_err      STRING  DEFAULT NULL;
    v_qid      STRING  DEFAULT NULL;
BEGIN
    /* NOTE: plain PLAN, never PLAN DELTA. DELTA skips definitions it believes
       unchanged and by documentation cannot see out-of-band edits - which is
       exactly what a drift check is looking for. It would report CLEAN over a
       drifted database. Do not "optimise" this. */
    v_sql := 'EXECUTE DCM PROJECT ' || PROJECT_NAME || ' PLAN FROM ''' || SOURCE_PATH || '''';

    BEGIN
        EXECUTE IMMEDIATE :v_sql;
        v_qid := SQLID;

        SELECT $1::STRING INTO :v_json
        FROM TABLE(RESULT_SCAN(:v_qid));

        v_n := ARRAY_SIZE(PARSE_JSON(:v_json):changeset);
        v_verdict := IFF(:v_n = 0, 'CLEAN', 'DRIFT');

    EXCEPTION
        WHEN OTHER THEN
            /* An un-revertible drift makes PLAN fail to compile (F4). This is
               the MOST serious outcome, not a broken job - it means drift
               exists, cannot be auto-reverted, and may be hiding other drift. */
            v_verdict := 'ERROR';
            v_err     := SQLERRM;
            v_json    := NULL;
            v_n       := -1;
    END;

    INSERT INTO DCM_ADMIN.AUDIT.CTL_DCM_DRIFT_LOG
        (PROJECT_NAME, SOURCE_PATH, CHECKED_AT_UTC, DURATION_MS,
         VERDICT, ENTITIES_CHANGED, CHANGESET, ERROR_MESSAGE, PLAN_QUERY_ID)
    SELECT :PROJECT_NAME, :SOURCE_PATH, :v_start,
           DATEDIFF('millisecond', :v_start, SYSDATE()),
           :v_verdict, :v_n,
           /* Store ONLY the changeset array, not the whole plan result. The
              result object wraps it as {version, metadata, changeset}; storing
              the wrapper makes every downstream FLATTEN start one level too
              high and silently return nothing. */
           IFF(:v_json IS NULL, NULL, PARSE_JSON(:v_json):changeset),
           :v_err, :v_qid;

    RETURN :v_verdict || ' | entities=' || :v_n::STRING
           || COALESCE(' | ' || :v_err, '');
END;
$$;


/* ============================================================================
   4. THE SCHEDULE

   Deliberately NOT a deploy. PLAN is safe to automate; DEPLOY reverts drift by
   dropping columns and destroying their data (F3), so it stays a decision a
   person makes after reading a plan.

   05:00 UTC daily - after the governance chain's 03:00 master and its 04:00
   heartbeat monitor, so a drift check never races a deployment.
   ============================================================================ */

CREATE OR REPLACE TASK DCM_ADMIN.AUDIT.TASK_DCM_DRIFT_CHECK
    WAREHOUSE = COMPUTE_WH
    SCHEDULE  = 'USING CRON 0 5 * * * UTC'
    COMMENT   = 'Nightly DCM drift check. Writes CTL_DCM_DRIFT_LOG. Never deploys.'
AS
    CALL DCM_ADMIN.AUDIT.SP_DCM_DRIFT_CHECK(
        'DCM_ADMIN.PROJECTS.PBI_CAPACITIES',
        '@DCM_ADMIN.PROJECTS.PBI_CAPACITIES_SRC'
    );

-- Tasks are created suspended. Enable deliberately:
--   ALTER TASK DCM_ADMIN.AUDIT.TASK_DCM_DRIFT_CHECK RESUME;
