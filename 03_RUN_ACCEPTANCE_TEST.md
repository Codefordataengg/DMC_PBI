# Running the acceptance test

Every command below names its connection explicitly with `-c dcm_poc`.

> **The default `snow` connection on this machine is `org_snowflake` →
> `LF96743-NU71207`, the Snowy tenant.** These definitions create a database called
> `DEVELOP`. A `snow dcm deploy` without `-c` would aim that at the corporate account.
> Never omit the flag.

CLI flags below were read from `snow --help` on Snowflake CLI 3.22.0, not from memory.

---

## Step 0 — one-time setup

**0a. Add a connection for the personal account.** Run it yourself — it prompts:

```
! snow connection add -n dcm_poc -a YVTSYHL-PP80681 -u <your-personal-account-user> \
    -r ACCOUNTADMIN -A externalbrowser
```

`YVTSYHL-PP80681` is `<ORGNAME>-<ACCOUNTNAME>`, confirmed 2026-08-22. It is **not** the
locator `LV16268`, which is what `CURRENT_ACCOUNT()` returns. `externalbrowser` matches the
existing connection's auth style and keeps a password out of `config.toml`; swap `-A` for
`-p` if the personal account uses password auth. No `-w` — DDL needs no warehouse. Add one
if a command complains.

Then verify it points where you think:

```
snow sql -c dcm_poc -q "SELECT CURRENT_ACCOUNT(), CURRENT_REGION(), CURRENT_ROLE()"
```

Expect `LV16268` / `AWS_AP_SOUTHEAST_2`. **If it returns anything else, stop.**

**0b.** ~~Put the real account identifier into `manifest.yml`.~~ **Done 2026-08-22** —
`account_identifier: YVTSYHL-PP80681`.

**0c. Create the home for the project object.** It lives outside `DEVELOP` on purpose —
a project that owns the database containing itself can take itself out with a `DEFINE`
removal:

```sql
USE ROLE ACCOUNTADMIN;
CREATE DATABASE IF NOT EXISTS DCM_ADMIN;
CREATE SCHEMA   IF NOT EXISTS DCM_ADMIN.PROJECTS;
```

**0d. Create the project:**

```
snow dcm create DCM_ADMIN.PROJECTS.PBI_CAPACITIES -c dcm_poc --if-not-exists \
  --from ./snowflake-dcm
```

---

## Step 1 — PLAN against an empty account

```
snow dcm plan DCM_ADMIN.PROJECTS.PBI_CAPACITIES -c dcm_poc \
  --from ./snowflake-dcm --save-output
```

**Expect: 12 creates, 0 alters, 0 drops** — 1 database, 3 schemas, 8 tables.

Any `ALTER` here means the translation from `GET_DDL` to `DEFINE` is wrong, because
nothing exists yet to alter. Find it before step 2. Per `FINDINGS.md` F1 the repo and
the live database agreed on all 53 columns, so a surprise here is mine, not the estate's.

---

## Step 2 — DEPLOY

```
snow dcm deploy DCM_ADMIN.PROJECTS.PBI_CAPACITIES -c dcm_poc \
  --from ./snowflake-dcm --alias step2_initial --save-output
```

Confirm independently, not just from the tool's own output:

```sql
SELECT TABLE_SCHEMA, TABLE_NAME, COUNT(*) AS COLS
FROM   DEVELOP.INFORMATION_SCHEMA.COLUMNS
WHERE  TABLE_SCHEMA IN ('LND','STG','PRE')
GROUP  BY 1,2 ORDER BY 1,2;
```

Expect 8 rows totalling **53 columns**: `PBI_AllCapacities_RAW` 1, `PBI_AllCapacities` 6,
`PBI_AllCapacities_parsed` 8, `STG.DIM` 8, `STG.BRIDGE` 4, `PRE.DIM` 11, `PRE.BRIDGE` 7,
`PRE.FACT` 8.

---

## Step 3 — PLAN again: the idempotency proof

```
snow dcm plan DCM_ADMIN.PROJECTS.PBI_CAPACITIES -c dcm_poc \
  --from ./snowflake-dcm --save-output
```

**Expect: zero changes.** Same standard as every audit run in this build.

A non-empty changeset here means a definition does not round-trip — Snowflake normalised
something on create that the definition still declares differently. That is worth recording
even though it is not drift, because it would produce a permanently noisy plan.

---

## Step 4 — induce drift by hand *(this is the test)*

Run `90_INDUCE_DRIFT.sql` in the POC account, then:

```
snow dcm plan DCM_ADMIN.PROJECTS.PBI_CAPACITIES -c dcm_poc \
  --from ./snowflake-dcm --save-output
```

**PASS:** the changeset names `HAND_ADDED_BY_A_HUMAN` (drop), `SKU` (type revert),
`INSERT_DATE` (re-add).

**FAIL:** PLAN reports nothing. Then DCM detects only its own deployments, gives nothing
over `CREATE TABLE IF NOT EXISTS`, and the POC has answered its question in the negative.
Record it and stop — that is a valid result, not a setback.

---

## Step 5 — DEPLOY to revert the drift

```
snow dcm deploy DCM_ADMIN.PROJECTS.PBI_CAPACITIES -c dcm_poc \
  --from ./snowflake-dcm --alias step5_revert --save-output
```

Re-run the `INFORMATION_SCHEMA` query from step 2 — back to 53 columns.

**This step is destructive by design** and is the finding that governs whether the approach
can ever point at real data: reverting an added column is a `DROP COLUMN`, and per
`FINDINGS.md` F3 the data in it is gone (Time Travel aside). Fine here — the POC holds no
data. Not fine unattended against `DEVELOP`.

---

## Teardown

```
snow dcm drop DCM_ADMIN.PROJECTS.PBI_CAPACITIES -c dcm_poc
```

`drop` leaves the deployed objects behind; `purge` drops the objects but keeps the project.
To remove everything: `snow dcm purge` first, then `snow dcm drop`, then drop `DCM_ADMIN`.

---

## Record as you go

Write each step's result into `FINDINGS.md` as it happens, including the `out/` artifacts
from `--save-output`. A POC that produces a verdict nobody wrote down has to be run twice.
