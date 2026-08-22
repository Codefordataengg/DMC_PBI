/* ============================================================================
   STEP 4 OF THE ACCEPTANCE TEST — the one the POC is judged on.

   RUN IN THE POC ACCOUNT (personal, locator LV16268), AFTER step 3 has proven
   PLAN reports zero changes.

   This makes changes OUTSIDE the DCM project, exactly as a person with a
   worksheet would. The question is whether PLAN then reports them.

   Run step 4a alone first and record the result — that is the contracted test.
   4b and 4c are extensions: they cost one more PLAN and tell you whether the
   changeset is granular or merely detects "something differs".
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE DATABASE DEVELOP;

/* ---- 4a. THE CONTRACTED TEST: a hand-added column ----------------------- */

ALTER TABLE PRE.DIM_PBI_CAPACITIES
    ADD COLUMN HAND_ADDED_BY_A_HUMAN VARCHAR(100);

/* ---- 4b. WITHDRAWN --------------------------------------------------------
   This step widened SKU from VARCHAR(50) to VARCHAR(100). Do not reinstate it.

   Reverting a widening is a NARROWING, which Snowflake does not support, so PLAN
   could not compile the definition and ABORTED — hiding 4a and 4c along with it.
   The table had to be dropped and redeployed to recover. See FINDINGS.md F4.

   It tested Snowflake's ALTER limits, not DCM's detection. Wrong probe.
                                                                          ---- */

/* ---- 4c. EXTENSION: a dropped column ------------------------------------
   The inverse of 4a. Drift is not only additive, and a tool that reports adds
   but not removals would still leave the repo quietly wrong. */

ALTER TABLE STG.BRIDGE_PBI_CAPACITY_ADMIN
    DROP COLUMN INSERT_DATE;

/* ---- Confirm the drift is really there before running PLAN -------------- */

SELECT 'PRE.DIM_PBI_CAPACITIES'         AS OBJ, GET_DDL('TABLE','PRE.DIM_PBI_CAPACITIES')
UNION ALL
SELECT 'STG.BRIDGE_PBI_CAPACITY_ADMIN', GET_DDL('TABLE','STG.BRIDGE_PBI_CAPACITY_ADMIN');

/* ============================================================================
   NOW RUN:   snow dcm plan DCM_ADMIN.PROJECTS.PBI_CAPACITIES -c dcm_poc --save-output

   PASS if the changeset names:
     - HAND_ADDED_BY_A_HUMAN  as a column to drop   (from 4a)
     - INSERT_DATE            as a column to re-add (from 4c)

   VERIFIED 2026-08-23: it does, naming datatype and nullability for both.

   FAIL if PLAN reports no changes. That is a real result: it would mean DCM
   detects only what it deployed and offers nothing over CREATE TABLE IF NOT
   EXISTS. Record it in FINDINGS.md and stop.

   Do NOT use `EXECUTE DCM PROJECT ... PLAN DELTA` here. DELTA skips unchanged
   definitions and by documentation cannot see out-of-band edits — it would
   report nothing and look like a failure of DCM rather than of the method.
   `snow dcm plan` exposes no delta flag, so the CLI path is safe by default.
   ============================================================================ */
