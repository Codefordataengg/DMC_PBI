/* ============================================================================
   GIT INTEGRATION — make GitHub the source of truth

   Replaces the stage (@PBI_CAPACITIES_SRC) with a live clone of the repo, so
   the nightly drift check reads what is on main rather than whatever someone
   last uploaded by hand. That difference is the whole point: a stage can drift
   from the repo too, and then the drift checker itself is checking the wrong
   thing.

   PREREQUISITE — a GitHub personal access token (classic), scope: repo.
   Create at  https://github.com/settings/tokens
   The same token does both jobs: pushing from the laptop, and letting Snowflake
   pull. There is no way around needing one; GitHub stopped accepting passwords.

   RUN AS: ACCOUNTADMIN in the POC account (LV16268).
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE SCHEMA DCM_ADMIN.PROJECTS;


/* ---- 1. The credential -------------------------------------------------
   USERNAME is the GitHub account name, PASSWORD is the token - not the GitHub
   password. Snowflake stores this encrypted and it is not readable back.

   A long-lived PAT in a personal account is acceptable for a POC. If this ever
   points at the Snowy tenant, the credential belongs to whoever owns that
   policy, not to this file.                                                */

CREATE OR REPLACE SECRET DCM_ADMIN.PROJECTS.GITHUB_PAT
    TYPE     = password
    USERNAME = 'Codefordataengg'
    PASSWORD = '<<<PASTE_TOKEN_HERE>>>'
    COMMENT  = 'GitHub PAT for the DCM POC repo. Rotate or drop when the POC ends.';


/* ---- 2. Permission to reach github.com ---------------------------------
   API_ALLOWED_PREFIXES is a whitelist. Scoped to the account, not the single
   repo, so a second POC repo works without another integration - and nothing
   outside that account is reachable.                                        */

CREATE OR REPLACE API INTEGRATION GIT_API_CODEFORDATAENGG
    API_PROVIDER = git_https_api
    API_ALLOWED_PREFIXES = ('https://github.com/Codefordataengg')
    ALLOWED_AUTHENTICATION_SECRETS = (DCM_ADMIN.PROJECTS.GITHUB_PAT)
    ENABLED = TRUE
    COMMENT = 'Git access for DCM POC repositories.';


/* ---- 3. The clone ------------------------------------------------------- */

CREATE OR REPLACE GIT REPOSITORY DCM_ADMIN.PROJECTS.PBI_REPO
    API_INTEGRATION = GIT_API_CODEFORDATAENGG
    GIT_CREDENTIALS = DCM_ADMIN.PROJECTS.GITHUB_PAT
    ORIGIN          = 'https://github.com/Codefordataengg/DMC_PBI.git'
    COMMENT         = 'Live clone of the DCM POC repo. Source of truth for PLAN and DEPLOY.';


/* ---- 4. Pull, and confirm the files are actually there ------------------
   FETCH is not automatic. Nothing here notices a new commit on its own - a
   drift check against a stale clone would compare the database to yesterday's
   repo and call it clean. So FETCH runs immediately before every PLAN in
   section 6.                                                                */

ALTER GIT REPOSITORY DCM_ADMIN.PROJECTS.PBI_REPO FETCH;

SHOW GIT BRANCHES IN DCM_ADMIN.PROJECTS.PBI_REPO;

LS @DCM_ADMIN.PROJECTS.PBI_REPO/branches/main/;
/*  EXPECT manifest.yml at the top level and sources/definitions/*.sql beneath.
    The repo root IS the DCM project root - git init was run inside
    snowflake-dcm/, so there is no extra folder level to path through.       */


/* ---- 5. Prove the git path produces the same result as the stage --------
   If this reports anything other than "no changes", the clone and the stage
   disagree, and that must be understood before the schedule is repointed.   */

EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.PBI_CAPACITIES
    PLAN FROM '@DCM_ADMIN.PROJECTS.PBI_REPO/branches/main/';


/* ---- 6. Repoint the nightly check at git -------------------------------- */

CREATE OR REPLACE PROCEDURE DCM_ADMIN.AUDIT.SP_DCM_DRIFT_CHECK_FROM_GIT()
RETURNS STRING
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_result STRING;
BEGIN
    /* Pull first. A check against a stale clone compares the database to an old
       version of the repo and calls the difference drift - or worse, misses real
       drift because the old repo happens to match. */
    ALTER GIT REPOSITORY DCM_ADMIN.PROJECTS.PBI_REPO FETCH;

    CALL DCM_ADMIN.AUDIT.SP_DCM_DRIFT_CHECK_AND_ALERT(
        'DCM_ADMIN.PROJECTS.PBI_CAPACITIES',
        '@DCM_ADMIN.PROJECTS.PBI_REPO/branches/main/',
        'amitbhopte099@gmail.com'
    ) INTO :v_result;

    RETURN :v_result;
END;
$$;

CREATE OR REPLACE TASK DCM_ADMIN.AUDIT.TASK_DCM_DRIFT_CHECK
    WAREHOUSE = COMPUTE_WH
    SCHEDULE  = 'USING CRON 0 5 * * * UTC'
    COMMENT   = 'Nightly: fetch main, PLAN, log, alert on DRIFT or ERROR. Never deploys.'
AS
    CALL DCM_ADMIN.AUDIT.SP_DCM_DRIFT_CHECK_FROM_GIT();


/* ---- 7. Turn it on ------------------------------------------------------
   Run this only after section 5 came back clean.                            */

-- ALTER TASK DCM_ADMIN.AUDIT.TASK_DCM_DRIFT_CHECK RESUME;
-- SHOW TASKS IN SCHEMA DCM_ADMIN.AUDIT;


/* ---- 8. Retire the stage ------------------------------------------------
   Two sources of truth is one too many. Once git is proven, the stage is a
   copy that nothing updates and that anyone could deploy from by accident.   */

-- DROP STAGE DCM_ADMIN.PROJECTS.PBI_CAPACITIES_SRC;
