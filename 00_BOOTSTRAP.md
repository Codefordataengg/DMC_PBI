# Bootstrap — build the whole thing from nothing

**The order matters and is not obvious from the filenames.** `12_GIT_INTEGRATION.sql` has to be
run in *two halves*, with other files in between, because its task depends on a procedure
defined in `11_ALERTING.sql`.

This file is the only place that order is written down. If you change the dependency shape,
change it here.

---

## What you need before you start

| | |
|---|---|
| Account | `LV16268` / `YVTSYHL-PP80681`, role `ACCOUNTADMIN` |
| Warehouse | `COMPUTE_WH` |
| **GitHub PAT** | **classic, scope `repo`.** Stored in the secret; there is **no way to read the existing one back out of Snowflake** |
| Repo | `github.com/Codefordataengg/DMC_PBI` with `main` populated |

> ⚠️ **The token is the hard dependency.** `CREATE SECRET` needs the literal value. Snowflake
> will not reveal the stored one. If you no longer have it, generate a new PAT before you drop
> anything — otherwise the teardown is one-way.

---

## Teardown — only if rebuilding

**Export evidence first.** The drift log and deployment artifacts are destroyed with the
project object and cannot be recovered. See `evidence/` for the last export.

```sql
USE ROLE ACCOUNTADMIN;

EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.PBI_CAPACITIES PURGE;   -- drops DEVELOP + 12 objects
DROP DCM PROJECT    IF EXISTS DCM_ADMIN.PROJECTS.PBI_CAPACITIES;
DROP GIT REPOSITORY IF EXISTS DCM_ADMIN.PROJECTS.PBI_REPO;
DROP DATABASE       IF EXISTS DCM_ADMIN;                        -- takes the audit log with it
DROP INTEGRATION    IF EXISTS GIT_API_CODEFORDATAENGG;
DROP INTEGRATION    IF EXISTS NI_DCM_DRIFT_EMAIL;

SHOW DATABASES LIKE 'DEVELOP';                                  -- expect: nothing
```

---

## Build order

### 1 — Foundations

```sql
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

CREATE DATABASE IF NOT EXISTS DCM_ADMIN;
CREATE SCHEMA   IF NOT EXISTS DCM_ADMIN.PROJECTS;
```

### 2 — Git plumbing — `12_GIT_INTEGRATION.sql` §1–§4

Paste your token into §1 first. **Do not commit the file with a real token in it** — GitHub
auto-revokes leaked ones, and you would be back to step 0.

Creates: `GITHUB_PAT` · `GIT_API_CODEFORDATAENGG` · `PBI_REPO`, then `FETCH`.

Stop after §4's `LS`. **Expect 20+ files under `branches/main/`.**

### 3 — The project object

```sql
CREATE DCM PROJECT IF NOT EXISTS DCM_ADMIN.PROJECTS.PBI_CAPACITIES
    COMMENT = 'Power BI capacities slice, all three layers.';
```

### 4 — Build the estate

```sql
EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.PBI_CAPACITIES
    PLAN FROM '@DCM_ADMIN.PROJECTS.PBI_REPO/branches/main/';
```

**Expect 14 entities — 13 create, 1 alter.** Then deploy, and verify independently:

```sql
EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.PBI_CAPACITIES
    DEPLOY AS "bootstrap" FROM '@DCM_ADMIN.PROJECTS.PBI_REPO/branches/main/';

SELECT COUNT(*) AS COLS FROM DEVELOP.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA IN ('LND','STG','PRE');        -- expect 53
```

### 5 — Audit layer — run `10_AUDIT_AND_MONITOR.sql` whole

Creates: `AUDIT` schema · `CTL_DCM_DRIFT_LOG` · `SEQ_DCM_CHECK_ID` ·
`V_DCM_DRIFT_OBJECTS` · `V_DCM_DRIFT_COLUMNS` · `SP_DCM_DRIFT_CHECK`.

**Defines no task.** That is deliberate — see F9.

### 6 — Alerting — run `11_ALERTING.sql` whole

Creates: `NI_DCM_DRIFT_EMAIL` · `FN_DRIFT_ALERT_BODY` · `SP_DCM_DRIFT_CHECK_AND_ALERT` ·
`ACKNOWLEDGED_AT` columns · `V_DCM_MONITOR_HEALTH`.

**Also defines no task.**

### 7 — The task — `12_GIT_INTEGRATION.sql` §6

**Now**, because the task calls `SP_DCM_DRIFT_CHECK_FROM_GIT`, which wraps
`SP_DCM_DRIFT_CHECK_AND_ALERT` from step 6. Run it earlier and it fails.

Creates: `SP_DCM_DRIFT_CHECK_FROM_GIT` and **the only definition of** `TASK_DCM_DRIFT_CHECK`.

### 8 — Prove it before scheduling it

```sql
CALL DCM_ADMIN.AUDIT.SP_DCM_DRIFT_CHECK_FROM_GIT();     -- expect: CLEAN | entities=0
```

Then make it fail, because an untested monitor is not a monitor:

```sql
ALTER TABLE DEVELOP.PRE.DIM_PBI_CAPACITIES ADD COLUMN BOOTSTRAP_TEST VARCHAR(10);
CALL DCM_ADMIN.AUDIT.SP_DCM_DRIFT_CHECK_FROM_GIT();     -- expect: DRIFT | 1 | alert sent
```

**Check the email actually arrived.** Then revert:

```sql
EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.PBI_CAPACITIES
    DEPLOY AS "post_bootstrap_revert" FROM '@DCM_ADMIN.PROJECTS.PBI_REPO/branches/main/';
CALL DCM_ADMIN.AUDIT.SP_DCM_DRIFT_CHECK_FROM_GIT();     -- expect: CLEAN
```

### 9 — Schedule it

```sql
ALTER TASK DCM_ADMIN.AUDIT.TASK_DCM_DRIFT_CHECK RESUME;
SELECT * FROM DCM_ADMIN.AUDIT.V_DCM_MONITOR_HEALTH;     -- expect HEALTH = OK, NEXT_RUN_UTC set
```

`NEXT_RUN_UTC` being populated is the check. `NULL` means suspended, and a suspended monitor
reads exactly like a passing one (F9).

---

## Verify the whole thing

```sql
SELECT COUNT(*) AS COLS FROM DEVELOP.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA IN ('LND','STG','PRE');              -- 53

SELECT * FROM DCM_ADMIN.AUDIT.V_DCM_MONITOR_HEALTH;     -- OK, NEXT_RUN_UTC set

SELECT VERDICT, COUNT(*) FROM DCM_ADMIN.AUDIT.CTL_DCM_DRIFT_LOG GROUP BY 1;
```

Then wait one night and confirm `TASK_HISTORY` shows `SUCCEEDED` — the only proof that
matters (F11).

---

## Dependency order, at a glance

```
        foundations
             │
   12 §1-4  git plumbing ──── needs the PAT
             │
        DCM project
             │
      DEPLOY from git ─────── DEVELOP, 53 columns
             │
   10  audit layer ────────── log, views, SP_DCM_DRIFT_CHECK
             │
   11  alerting ───────────── needs 10's log and views
             │
   12 §6  the task ────────── needs 11's SP_DCM_DRIFT_CHECK_AND_ALERT
             │
        test, then RESUME
```

**The one rule this shape encodes:** `TASK_DCM_DRIFT_CHECK` is created in exactly one place. It
was briefly created in three, and the duplicates silently suspended the live task and repointed
it at a dropped stage. See F9 and its addendum.
