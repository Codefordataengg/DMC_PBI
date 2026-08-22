/* ============================================================================
   DCM availability gate.

   RUN THIS IN THE POC ACCOUNT (personal account, ACCOUNTADMIN).
   NOT in DEVELOP. NOT in the Snowy tenant.

   Snowflake's documentation states DCM Projects are "available for all Snowflake
   editions" but the feature is in PREVIEW (announced 2026-03-20) and the docs
   name no cloud, region or trial restrictions either way. So the docs cannot
   answer the question. The account can.

   If CREATE DCM PROJECT below fails, the POC stops here and that failure IS the
   answer. Record it in FINDINGS.md and do not translate the DDL.
   ============================================================================ */

USE ROLE ACCOUNTADMIN;

/* ---- 1. Context -------------------------------------------------------- */

SELECT CURRENT_VERSION()  AS SNOWFLAKE_VERSION,
       CURRENT_ACCOUNT()  AS ACCOUNT,
       CURRENT_REGION()   AS REGION,
       CURRENT_ROLE()     AS ROLE;

/* ---- 2. Edition and trial expiry ---------------------------------------
   Needs ORGADMIN. If the role is not granted, skip it — read the edition off
   the Snowsight account page instead. The README asks for the trial expiry
   because a trial that lapses mid-POC looks exactly like a broken feature.  */

USE ROLE ORGADMIN;
SHOW ORGANIZATION ACCOUNTS;
SELECT "account_name", "edition", "created_on", "account_locator"
FROM   TABLE(RESULT_SCAN(LAST_QUERY_ID()));

USE ROLE ACCOUNTADMIN;

/* ---- 3. Somewhere to put the probe ------------------------------------- */

CREATE DATABASE IF NOT EXISTS DCM_PROBE;
CREATE SCHEMA   IF NOT EXISTS DCM_PROBE.PROBE;
USE SCHEMA DCM_PROBE.PROBE;

/* ---- 4. THE GATE -------------------------------------------------------
   One statement. It either works on this account or it does not.           */

CREATE DCM PROJECT IF NOT EXISTS DCM_PROBE.PROBE.AVAILABILITY_PROBE
  COMMENT = 'Throwaway probe for the DCM POC availability gate. Safe to drop.';

SHOW DCM PROJECTS IN ACCOUNT;

/* ---- 5. Clean up -------------------------------------------------------
   The probe proves nothing beyond availability. Do not build on it — the real
   project is created against the declared sources.                          */

DROP DCM PROJECT IF EXISTS DCM_PROBE.PROBE.AVAILABILITY_PROBE;
DROP DATABASE    IF EXISTS DCM_PROBE;

/* ============================================================================
   Report back: the version/region row from (1), the edition from (2), and
   whether (4) succeeded or the exact error text it raised.
   ============================================================================ */
