/* ============================================================================
   Capture the authoritative DDL for the capacities slice.

   RUN THIS IN  DEVELOP  (the real dev database), NOT in the POC account.
   It is READ ONLY — GET_DDL only reads the catalogue.

   Paste the output into snowflake-dcm/ as the declared state. This output —
   not the repo, not SNOWFLAKE_TABLE_INVENTORY.md — is the target state.
   ============================================================================ */

USE DATABASE DEVELOP;

/* ---- the capacities slice, all three layers ---------------------------- */

SELECT 'LND."PBI_AllCapacities_RAW"'        AS OBJ,
       GET_DDL('TABLE','LND."PBI_AllCapacities_RAW"')        AS DDL
UNION ALL SELECT 'LND."PBI_AllCapacities"',
       GET_DDL('TABLE','LND."PBI_AllCapacities"')
UNION ALL SELECT 'LND."PBI_AllCapacities_parsed"',
       GET_DDL('TABLE','LND."PBI_AllCapacities_parsed"')
UNION ALL SELECT 'STG.DIM_PBI_CAPACITIES',
       GET_DDL('TABLE','STG.DIM_PBI_CAPACITIES')
UNION ALL SELECT 'STG.BRIDGE_PBI_CAPACITY_ADMIN',
       GET_DDL('TABLE','STG.BRIDGE_PBI_CAPACITY_ADMIN')
UNION ALL SELECT 'PRE.DIM_PBI_CAPACITIES',
       GET_DDL('TABLE','PRE.DIM_PBI_CAPACITIES')
UNION ALL SELECT 'PRE.BRIDGE_PBI_CAPACITY_ADMIN',
       GET_DDL('TABLE','PRE.BRIDGE_PBI_CAPACITY_ADMIN')
UNION ALL SELECT 'PRE.FACT_PBI_CAPACITY_OBSERVATION',
       GET_DDL('TABLE','PRE.FACT_PBI_CAPACITY_OBSERVATION');

/* ---- control tables: needed only if the POC runs a pipeline-like load ---
   Not part of the capacities slice proper. Uncomment if scope widens.

SELECT GET_DDL('TABLE','PRE.CTL_BATCH_SCHEDULE');
SELECT GET_DDL('TABLE','PRE.DIM_AUDIT');
                                                                          ---- */

/* ---- OPTIONAL: does the repo already disagree with the database? -------
   The nine PRE tables were verified against GET_DDL on 2026-08-21.
   The LND ones never were. Any difference found here is drift that nothing
   currently detects, and is a POC finding in its own right — record it.
                                                                          ---- */
