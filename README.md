# Snowflake DCM — POC

**This directory is a proof of concept and is separate from the Power BI migration.**
Nothing here touches the `DEVELOP` database, the Matillion project, or any pipeline.

## The problem it is testing

Schema DDL for the governance estate currently lives **inside ETL orchestration** — 64
`CREATE TABLE IF NOT EXISTS` statements spread across 9 pipeline files in `PowerBI Governance/`.

`IF NOT EXISTS` is a **no-op against a table that already exists**. So the repo can stand up
an empty environment, but it cannot tell you whether an existing environment still matches it.
Add a column by hand and every pipeline runs green forever while the repo is quietly wrong.

> **Two different guarantees, and only the first one is real today:**
> 1. "This repo can build the database." ✅
> 2. "The database matches this repo." ❌

Closing (2) is the entire point of the POC.

## Where it runs

A **personal Snowflake account** where the operator is `ACCOUNTADMIN`. No Matillion, no data,
no shared objects. The POC is purely structural — which is what DCM manages.

## Scope

Capacities only, all three layers, then widen. **Eight objects, 53 columns** — plus the
database and three schemas, which DCM needs declared because it requires fully qualified names:

| Layer | Object | Cols |
|---|---|---|
| `LND` | `PBI_AllCapacities_RAW` — drop zone, truncated per run, no `AUDIT_KEY` | 1 |
| `LND` | `PBI_AllCapacities` — envelope, append-only, carries `AUDIT_KEY` | 6 |
| `LND` | `PBI_AllCapacities_parsed` | 8 |
| `STG` | `DIM_PBI_CAPACITIES` | 8 |
| `STG` | `BRIDGE_PBI_CAPACITY_ADMIN` | 4 |
| `PRE` | `DIM_PBI_CAPACITIES` — merge target | 11 |
| `PRE` | `BRIDGE_PBI_CAPACITY_ADMIN` — merge target | 7 |
| `PRE` | `FACT_PBI_CAPACITY_OBSERVATION` — merge target | 8 |

## Where the target state lives

**There is no single target-state document.** Three sources, in precedence order — they do not agree,
and treating the third as the first will produce tables with wrong types.

| Rank | Source | What it gives | Trust |
|---|---|---|---|
| **1** | **`GET_DDL` against `DEVELOP`** | Types, nullability, keys, defaults | **Authoritative — this *is* the target state.** |
| 2 | The 64 `CREATE TABLE IF NOT EXISTS` in `../PowerBI Governance/*.orch.yaml` | Full DDL, but only where a pipeline creates the table | Nine `PRE` tables were verified against `GET_DDL` on 2026-08-21. The `LND` ones were hand-written; for the **capacities slice they were diffed on 2026-08-22 and match exactly** (`FINDINGS.md` F1). The other `LND` tables still have not been. |
| 3 | [`../docs/matillion/SNOWFLAKE_TABLE_INVENTORY.md`](../docs/matillion/SNOWFLAKE_TABLE_INVENTORY.md) | All 52 tables — purpose, grain, key columns, load pattern, gotchas | **The map, not the blueprint.** Column *names* only. Only 3 of 52 entries carry a `CREATE TABLE`. |

**Read the inventory to understand the estate. Take the DDL from `GET_DDL`.**

If sources 1 and 2 disagree for a table, that is **drift the repo cannot currently see** — which is
precisely what this POC exists to detect. Record it as a finding rather than quietly reconciling it.

## The acceptance test

The POC is judged on **step 4**, not on whether the tool installs.

1. Declare the DDL → `PLAN` → expect *n* creates
2. `DEPLOY` → schema exists
3. `PLAN` again → **expect zero changes** — the idempotency proof
4. **Add a column by hand** → `PLAN` → **it must report that column**
5. `DEPLOY` → drift reverted

If step 4 does not report the drift, DCM offers nothing that `IF NOT EXISTS` does not
already offer, and the POC has answered its question in the negative. That is a valid result.

## Files here

| File | |
|---|---|
| `00_BOOTSTRAP.md` | **Start here to rebuild from nothing.** The run order, which is not obvious from the filenames — `12_GIT_INTEGRATION.sql` runs in two halves with `10` and `11` in between. |
| `evidence/` | Exported drift log, deployment and task history. Evidence for F5, F7, F9, F11 — destroyed by teardown, so exported first. |
| `01_CAPTURE_TARGET_STATE.sql` | **Run in `DEVELOP`, not the POC account.** Read-only `GET_DDL` for the capacities slice. |
| `target-state/GET_DDL_2026-08-22.txt` | The captured output, verbatim. **Evidence — do not edit.** Precedence rank 1: if the `DEFINE` files disagree with this, this wins. |
| `02_VERIFY_DCM_AVAILABLE.sql` | The availability gate. Run in the POC account. **Passed 2026-08-22.** |
| `manifest.yml` | `manifest_version: 2`. Needs the real account identifier filling in. |
| `sources/definitions/*.sql` | The declared state as `DEFINE` statements. Location is fixed by Snowflake — definition files **must** sit under `sources/definitions/`. |
| `03_RUN_ACCEPTANCE_TEST.md` | The five steps via the `snow` CLI. |
| `04_SNOWSIGHT_RUN.sql` | **Superseded 2026-08-25.** Stage-based; the stage was dropped when git became the source of truth. Kept for its commentary on what each acceptance step proves. |
| `10_AUDIT_AND_MONITOR.sql` | Drift log, column-grain views, check procedure. **Does not define the task.** |
| `11_ALERTING.sql` | Email integration, alert body, health view. **Does not define the task.** |
| `12_GIT_INTEGRATION.sql` | Secret, API integration, git clone, git-sourced procedure — and **the only definition of `TASK_DCM_DRIFT_CHECK`**. |
| `docs/PPT_PROMPT.md` | Slide-deck generation prompt — 18 slides, Modern Minimalist theme, with every figure pre-filled so a generator cannot invent them. |
| `docs/DCM_ARCHITECTURE.md` | Diagrams, the **three copies of the definitions** (§3), verdict decision tree, failure modes, findings index. |
| `target-state/` | The `GET_DDL` capture, verbatim. Evidence — never edit. |
| `90_INDUCE_DRIFT.sql` | Step 4. The hand edits the POC is judged on. |
| `FINDINGS.md` | Dated results. Write to it as you go. |
| `DEMO_RUNSHEET.md` | **Live demo script** — 12 sections, timings, talking points, expected output, and what to do when a step misbehaves in front of an audience. |

## Before building — verify, do not assume

- [x] **DCM projects available on this account** — confirmed 2026-08-22 by `CREATE DCM PROJECT`
      succeeding on `LV16268` (Snowflake 10.29.101, AWS ap-southeast-2). DCM Projects are in
      **preview** (announced 2026-03-20); the docs claim all editions but name no cloud or
      region scope, so the account itself is the only trustworthy answer. `TABLE`, `SCHEMA`
      and `DATABASE` are GA *within* DCM.
- [x] **Which `CREATE OR ALTER TABLE` changes are supported** — add column at end, drop column,
      compatible type change, default, nullability, comment, constraints, clustering, table
      params. **Not** supported: column reorder, rename, incompatible type change, `AS SELECT`,
      tags/policies, search optimization, virtual columns. It errors rather than silently
      rebuilding, though Snowflake documents a rare partial-application failure.
- [ ] **Trial expiry** — still unknown. `SHOW ORGANIZATION ACCOUNTS` returned nothing (no
      `ORGADMIN` grant). Read the edition off the Snowsight account page. A trial lapsing
      mid-POC looks exactly like a broken feature.

Take these from Snowflake's own documentation or from the account itself, not from memory.
This project has already been bitten once by a plausible-but-unverified platform assumption.

## The one that nearly cost the POC

`EXECUTE DCM PROJECT ... PLAN DELTA` **cannot** see out-of-band changes — Snowflake:
*"Because it skips unchanged definitions, it doesn't detect changes that happened outside of
DCM Projects on your account since the last deployment."*

Step 4 **is** an out-of-band change. Run it with `DELTA` and it reports nothing, and the POC
returns a false negative on its central question. Use full `PLAN`. `snow dcm plan` exposes no
delta flag, so the CLI path is safe by default.

## Wrong account risk

The only `snow` connection on this machine is `org_snowflake` → `LF96743-NU71207`, the **Snowy
tenant**. These definitions create a database named `DEVELOP`. Every command in
`03_RUN_ACCEPTANCE_TEST.md` therefore passes `-c dcm_poc` explicitly. Never omit it.

## Portability notes

DDL lifted from `DEVELOP` will not transplant unedited:

| Thing | Count | Why it breaks |
|---|---|---|
| `SNOWUTILS_RO` | 73 refs | Role does not exist in a personal account. **Dropped from the POC** — grants are not the structural question being tested, and DCM simply leaves undeclared grants unmanaged. |
| `SNOWUTILS_ADMIN` | 8 refs in the capacities pipeline | Same. Dropped. |
| `COMPUTE_WH` | 1 ref | May be absent or differently named. Not referenced by the POC — DCM needs no warehouse for DDL. |
| `LND."..."` | all | Schema-qualified, **not** database-qualified — resolves against the session's current database |

The quoted mixed-case identifiers in `LND` are deliberate and must stay quoted. `PRE` objects
are uppercase unquoted. Do not "tidy" either.
