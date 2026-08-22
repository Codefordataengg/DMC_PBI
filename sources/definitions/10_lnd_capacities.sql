/* LND — landing layer, capacities slice.

   Translated verbatim from target-state/GET_DDL_2026-08-22.txt (precedence rank 1).
   Types are written in the expanded form GET_DDL emits (NUMBER(38,0), not NUMBER;
   TIMESTAMP_TZ(9), not TIMESTAMP_TZ) so that PLAN compares like with like and a
   reported ALTER means a real difference, not a formatting one.

   The mixed-case identifiers here are DELIBERATE and must stay quoted. The legacy
   parsed layer has two naming conventions; this is the one it uses. Do not "tidy"
   them to uppercase — that would be a rename, and CREATE OR ALTER cannot rename.
   It would drop and re-add instead.

   JSON is unquoted below because that is how GET_DDL renders it. Unquoted JSON and
   quoted "JSON" resolve to the same identifier. */

DEFINE TABLE DEVELOP.LND."PBI_AllCapacities_RAW" (
    JSON VARIANT
);

DEFINE TABLE DEVELOP.LND."PBI_AllCapacities" (
    AUDIT_KEY         NUMBER(38,0)     NOT NULL,
    ROUTE             VARCHAR(200)     NOT NULL,
    PAGE_SEQ          NUMBER(38,0)     NOT NULL,
    IS_FINAL_PAGE     BOOLEAN          NOT NULL,
    EXTRACTED_AT_UTC  TIMESTAMP_TZ(9)  NOT NULL,
    PAYLOAD           VARIANT
);

DEFINE TABLE DEVELOP.LND."PBI_AllCapacities_parsed" (
    CAPACITY_ID          VARCHAR(36),
    CAPACITY_NAME        VARCHAR(500),
    SKU                  VARCHAR(50),
    STATE                VARCHAR(50),
    REGION               VARCHAR(200),
    CALLER_ACCESS_RIGHT  VARCHAR(50),
    TENANT_KEY_ID        VARCHAR(36),
    ADMIN_EMAIL          VARCHAR(500)
);
