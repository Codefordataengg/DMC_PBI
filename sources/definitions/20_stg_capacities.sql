/* STG — staging layer, capacities slice.
   Translated verbatim from target-state/GET_DDL_2026-08-22.txt.

   STG objects are uppercase unquoted. Note these carry no NOT NULL — the
   constraints appear only at PRE. That asymmetry is in the live database and is
   reproduced here rather than corrected; the POC declares what IS, not what
   ought to be. */

DEFINE TABLE DEVELOP.STG.DIM_PBI_CAPACITIES (
    ID                VARCHAR(36),
    NAME              VARCHAR(500),
    SKU               VARCHAR(50),
    STATE             VARCHAR(50),
    REGION            VARCHAR(200),
    TENANT_KEY_ID     VARCHAR(36),
    INSERT_AUDIT_KEY  NUMBER(38,0),
    INSERT_DATE       TIMESTAMP_NTZ(9)
);

DEFINE TABLE DEVELOP.STG.BRIDGE_PBI_CAPACITY_ADMIN (
    CAPACITY_ID       VARCHAR(36),
    ADMIN_EMAIL       VARCHAR(500),
    INSERT_AUDIT_KEY  NUMBER(38,0),
    INSERT_DATE       TIMESTAMP_NTZ(9)
);
