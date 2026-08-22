/* PRE — presentation layer, capacities slice.
   Translated verbatim from target-state/GET_DDL_2026-08-22.txt.

   These three are the merge targets. In the real estate they hold data that is
   not re-derivable from a single API call, which is why FINDINGS.md F3 matters:
   removing a DEFINE statement here would drop the object on the next deploy. */

DEFINE TABLE DEVELOP.PRE.DIM_PBI_CAPACITIES (
    ID                VARCHAR(36)       NOT NULL,
    NAME              VARCHAR(500),
    SKU               VARCHAR(50),
    STATE             VARCHAR(50),
    REGION            VARCHAR(200),
    TENANT_KEY_ID     VARCHAR(36),
    INSERT_AUDIT_KEY  NUMBER(38,0),
    INSERT_DATE       TIMESTAMP_NTZ(9),
    UPDATE_AUDIT_KEY  NUMBER(38,0),
    UPDATE_DATE       TIMESTAMP_NTZ(9),
    IS_CURRENT_FLAG   NUMBER(1,0)       DEFAULT 1
);

DEFINE TABLE DEVELOP.PRE.BRIDGE_PBI_CAPACITY_ADMIN (
    CAPACITY_ID       VARCHAR(36)   NOT NULL,
    ADMIN_EMAIL       VARCHAR(500)  NOT NULL,
    INSERT_AUDIT_KEY  NUMBER(38,0),
    INSERT_DATE       TIMESTAMP_NTZ(9),
    UPDATE_AUDIT_KEY  NUMBER(38,0),
    UPDATE_DATE       TIMESTAMP_NTZ(9),
    IS_CURRENT_FLAG   NUMBER(1,0)   DEFAULT 1
);

DEFINE TABLE DEVELOP.PRE.FACT_PBI_CAPACITY_OBSERVATION (
    OBSERVED_DATE     DATE          NOT NULL,
    CAPACITY_ID       VARCHAR(36)   NOT NULL,
    SKU               VARCHAR(50),
    STATE             VARCHAR(50),
    REGION            VARCHAR(200),
    ADMIN_COUNT       NUMBER(38,0),
    INSERT_AUDIT_KEY  NUMBER(38,0),
    INSERT_DATE       TIMESTAMP_NTZ(9)
);
