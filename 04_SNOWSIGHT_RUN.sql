/* ============================================================================
   THE WHOLE ACCEPTANCE TEST, AS SQL — for running in a Snowsight worksheet.

   Same five steps as 03_RUN_ACCEPTANCE_TEST.md, no CLI needed after setup.

   WHERE TO RUN: Snowsight, signed in to the PERSONAL account.
                 Check the top-right account switcher says LV16268 / YVTSYHL-PP80681.
                 If it says LF96743-NU71207 you are in the Snowy tenant — STOP.

   ROLE:         ACCOUNTADMIN
   WAREHOUSE:    COMPUTE_WH (any warehouse; DDL barely uses it)

   Work top to bottom. Each step says what to expect BEFORE you run it. If what
   you get differs, stop and read — a surprise here is information, not a nuisance.
   ============================================================================ */


/* ============================================================================
   ⚠️  THE ONE THING THAT WOULD RUIN THIS TEST

   Every PLAN below is written as  ... PLAN  — never  ... PLAN DELTA.

   PLAN DELTA is faster because it skips definitions it believes are unchanged.
   Snowflake's own words: it "doesn't detect changes that happened outside of
   DCM Projects on your account since the last deployment."

   Step 4 IS a change made outside DCM Projects. Run it with DELTA and it will
   cheerfully report nothing, and we would conclude DCM cannot detect drift when
   in fact we simply asked it not to look.

   Do not add the word DELTA anywhere in this file.
   ============================================================================ */


/* ============================================================================
   SECTION 0 — SETUP (once)
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

-- 0.1  Home for the project object. Deliberately NOT inside DEVELOP: a project
--      that lives in the database it manages can delete itself.
CREATE DATABASE IF NOT EXISTS DCM_ADMIN;
CREATE SCHEMA   IF NOT EXISTS DCM_ADMIN.PROJECTS;

-- 0.2  A stage to hold the definition files.
--      SQL DCM commands cannot read files off your laptop — the files have to
--      live in Snowflake first. This is that place.
CREATE STAGE IF NOT EXISTS DCM_ADMIN.PROJECTS.PBI_CAPACITIES_SRC
    DIRECTORY = (ENABLE = TRUE)
    COMMENT   = 'DCM POC — capacities definition files.';


/* ----------------------------------------------------------------------------
   0.3  GET THE FILES ONTO THAT STAGE.  Two ways — pick one.

   EASIEST — one command in your Mac terminal, from the repo root:

       snow stage copy ./snowflake-dcm/manifest.yml \
           @DCM_ADMIN.PROJECTS.PBI_CAPACITIES_SRC/ -c dcm_poc --overwrite

       snow stage copy "./snowflake-dcm/sources/definitions/*.sql" \
           @DCM_ADMIN.PROJECTS.PBI_CAPACITIES_SRC/sources/definitions/ \
           -c dcm_poc --overwrite

   ALL-BROWSER — Snowsight ▸ Ingestion ▸ Add Data ▸ "Load files into a Stage".
       Pick stage PBI_CAPACITIES_SRC, then upload in TWO batches, because the
       folder path matters and the uploader flattens what you give it:

         batch 1 → path: (leave blank)          file: manifest.yml
         batch 2 → path: sources/definitions    files: the five .sql files

   The layout is not a style choice. Snowflake requires definition files to sit
   under sources/definitions/ and will not find them anywhere else.
   -------------------------------------------------------------------------- */

-- 0.4  Confirm all six files arrived in the right places before going on.
LS @DCM_ADMIN.PROJECTS.PBI_CAPACITIES_SRC;
/*  EXPECT exactly these six:
      manifest.yml
      sources/definitions/00_database.sql
      sources/definitions/01_schemas.sql
      sources/definitions/10_lnd_capacities.sql
      sources/definitions/20_stg_capacities.sql
      sources/definitions/30_pre_capacities.sql

    If the .sql files show up at the top level instead of under
    sources/definitions/, the upload path was blank — remove them and redo
    batch 2.  REMOVE @DCM_ADMIN.PROJECTS.PBI_CAPACITIES_SRC/<filename>;        */

-- 0.5  The project object. Harmless if it already exists (the CLI made one
--      on 2026-08-22 with this exact name).
CREATE DCM PROJECT IF NOT EXISTS DCM_ADMIN.PROJECTS.PBI_CAPACITIES
    COMMENT = 'DCM POC — Power BI capacities slice, all three layers.';


/* ============================================================================
   STEP 1 — PLAN against an empty account.   READ-ONLY. Creates nothing.
   ============================================================================ */

EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.PBI_CAPACITIES
    PLAN
    FROM '@DCM_ADMIN.PROJECTS.PBI_CAPACITIES_SRC';

/*  EXPECT: 14 entities — 13 to create, 1 to alter, 0 to drop.

      1  database   DEVELOP
      4  schemas    LND, STG, PRE  + PUBLIC (Snowflake adds PUBLIC to every
                                    database automatically; DCM counts it)
      8  tables     the capacities slice
      1  "alter"    ROLE ACCOUNTADMIN — not a real change, just DCM recording
                    that ACCOUNTADMIN owns the new objects

    The output is one row of JSON. Click the cell to expand it.

    WHAT MATTERS: all 8 tables should say CREATE and nothing should say ALTER
    on a TABLE. Nothing exists yet, so a table ALTER would mean the declared
    DDL disagrees with itself — a bug in our translation, to fix before Step 2. */


/* ============================================================================
   STEP 2 — DEPLOY.  This is the first thing that writes anything.
   ============================================================================ */

EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.PBI_CAPACITIES
    DEPLOY AS "step2_initial"
    FROM '@DCM_ADMIN.PROJECTS.PBI_CAPACITIES_SRC';

-- Check for yourself rather than trusting the tool's own summary.
SELECT TABLE_SCHEMA, TABLE_NAME, COUNT(*) AS COLS
FROM   DEVELOP.INFORMATION_SCHEMA.COLUMNS
WHERE  TABLE_SCHEMA IN ('LND','STG','PRE')
GROUP  BY 1,2
ORDER  BY 1,2;

/*  EXPECT 8 rows, 53 columns total:
      LND  PBI_AllCapacities            6
      LND  PBI_AllCapacities_RAW        1
      LND  PBI_AllCapacities_parsed     8
      PRE  BRIDGE_PBI_CAPACITY_ADMIN    7
      PRE  DIM_PBI_CAPACITIES          11
      PRE  FACT_PBI_CAPACITY_OBSERVATION 8
      STG  BRIDGE_PBI_CAPACITY_ADMIN    4
      STG  DIM_PBI_CAPACITIES           8                                      */


/* ============================================================================
   STEP 3 — PLAN again. The idempotency proof.
   ============================================================================ */

EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.PBI_CAPACITIES
    PLAN
    FROM '@DCM_ADMIN.PROJECTS.PBI_CAPACITIES_SRC';

/*  EXPECT: zero changes. Nothing to create, alter or drop.

    Same bar as every audit run in this build: run it twice, second run does
    nothing.

    If it wants to change something here, a definition does not round-trip —
    Snowflake normalised something on creation that our file still declares
    differently. Not drift, but worth writing down, because it would make every
    future plan permanently noisy and a noisy plan is one nobody reads.        */


/* ============================================================================
   STEP 4 — THE ACTUAL TEST.

   Now we vandalise the schema by hand, exactly as a person with a worksheet
   would, and ask DCM whether it notices.
   ============================================================================ */

USE DATABASE DEVELOP;

-- 4a. THE CONTRACTED TEST — a column nobody declared.
ALTER TABLE PRE.DIM_PBI_CAPACITIES
    ADD COLUMN HAND_ADDED_BY_A_HUMAN VARCHAR(100);

-- 4b. EXTENSION — a widened type. VARCHAR(50) -> VARCHAR(100).
--     Does the changeset name the COLUMN, or just say "table differs"?
ALTER TABLE PRE.DIM_PBI_CAPACITIES
    MODIFY COLUMN SKU SET DATA TYPE VARCHAR(100);

-- 4c. EXTENSION — a column removed. Drift is not only additive, and a tool
--     that spots additions but not deletions still leaves the repo wrong.
ALTER TABLE STG.BRIDGE_PBI_CAPACITY_ADMIN
    DROP COLUMN INSERT_DATE;

-- Prove the damage is real before asking DCM about it.
SELECT 'PRE.DIM_PBI_CAPACITIES'        AS OBJ, GET_DDL('TABLE','PRE.DIM_PBI_CAPACITIES') AS DDL
UNION ALL
SELECT 'STG.BRIDGE_PBI_CAPACITY_ADMIN',       GET_DDL('TABLE','STG.BRIDGE_PBI_CAPACITY_ADMIN');


-- ...and now the question the whole POC exists to answer:

EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.PBI_CAPACITIES
    PLAN
    FROM '@DCM_ADMIN.PROJECTS.PBI_CAPACITIES_SRC';

/*  PASS — the changeset names all three:
        HAND_ADDED_BY_A_HUMAN   to be dropped
        SKU                     type to be put back to VARCHAR(50)
        INSERT_DATE             to be added back

      Then DCM does something CREATE TABLE IF NOT EXISTS cannot do at all, and
      the POC succeeds.

    FAIL — the plan reports no changes.

      Then DCM only tracks what it deployed itself, which is no better than
      what the pipelines already do, and the POC has answered its question in
      the negative. That is a real result and a useful one. Write it down in
      FINDINGS.md and stop — do not go looking for a way to make it pass.      */


/* ============================================================================
   STEP 5 — DEPLOY to put it all back.
   ============================================================================ */

EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.PBI_CAPACITIES
    DEPLOY AS "step5_revert"
    FROM '@DCM_ADMIN.PROJECTS.PBI_CAPACITIES_SRC';

SELECT TABLE_SCHEMA, TABLE_NAME, COUNT(*) AS COLS
FROM   DEVELOP.INFORMATION_SCHEMA.COLUMNS
WHERE  TABLE_SCHEMA IN ('LND','STG','PRE')
GROUP  BY 1,2
ORDER  BY 1,2;

/*  EXPECT: back to 53 columns. Drift reverted.

    NOTE WHAT JUST HAPPENED. Reverting the added column was a DROP COLUMN, and
    Snowflake is explicit: "any data contained in the column is lost (but can
    still be recovered with Time Travel)."

    Harmless here — this account holds no data. It is the reason DEPLOY must
    never run unattended against a database that does. PLAN is safe to schedule;
    DEPLOY is a decision a person makes after reading one.                     */


/* ============================================================================
   HISTORY — what was run, when, by whom
   ============================================================================ */

SHOW DEPLOYMENTS IN DCM PROJECT DCM_ADMIN.PROJECTS.PBI_CAPACITIES;
DESCRIBE DCM PROJECT DCM_ADMIN.PROJECTS.PBI_CAPACITIES;


/* ============================================================================
   TEARDOWN — only when finished. Deletes everything the POC made.
   ============================================================================ */
/*
EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.PBI_CAPACITIES PURGE;  -- drops the 12 objects
DROP DCM PROJECT DCM_ADMIN.PROJECTS.PBI_CAPACITIES;           -- drops the project
DROP DATABASE DCM_ADMIN;
DROP DATABASE DEVELOP;   -- the POC copy in YOUR account. Not Snowy's.
*/
