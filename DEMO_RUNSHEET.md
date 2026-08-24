# Demo run sheet — schema drift, caught live

**Runtime: ~35 minutes + questions. Short version: ~12 minutes (marked ⏩).**

Everything runs in Snowsight in the personal account. Nothing touches Snowy's `DEVELOP`
or any Matillion pipeline.

> **The one thing the audience should leave with:**
> *"Our repo can build the database. It cannot prove the database still matches it.
> That second guarantee is the one that was missing, and here is what it costs."*

---

## Contents

| | Section | Min | |
|---|---|---|---|
| — | [Pre-flight](#pre-flight-30-minutes-before) | 10 | do this alone, before anyone joins |
| 1 | [The problem, in 90 seconds](#1--the-problem-in-90-seconds) | 3 | ⏩ |
| 2 | [Where the truth lives](#2--where-the-truth-lives) | 2 | |
| 3 | [Plan against an empty account](#3--plan-against-an-empty-account) | 3 | ⏩ |
| 4 | [Deploy](#4--deploy) | 3 | ⏩ |
| 5 | [Run it twice](#5--run-it-twice) | 1 | ⏩ |
| 6 | [**The reveal**](#6--the-reveal) | 5 | ⏩ |
| 7 | [Put it back](#7--put-it-back) | 2 | ⏩ |
| 8 | [The one that surprises people](#8--the-one-that-surprises-people) | 4 | |
| 9 | [What Snowflake forgets](#9--what-snowflake-forgets) | 5 | |
| 10 | [Watching the watcher](#10--watching-the-watcher) | 3 | |
| 11 | [The full loop](#11--the-full-loop-git--snowflake) | 4 | |
| 12 | [Close honestly](#12--close-honestly) | 2 | ⏩ |
| — | [If something breaks live](#if-something-breaks-live) | — | read this first |

---

## Pre-flight (30 minutes before)

Do this alone. Never in front of the audience.

```sql
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

-- 1. Clean slate: drop every object the project manages.
--    Keeps DCM_ADMIN, the project, the secret, the API integration and the git
--    clone. Those are the plumbing - rebuilding them live means typing a token
--    in front of an audience, which is a demo that fails.
EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.PBI_CAPACITIES PURGE;

-- 2. Confirm it is really empty. Expect: does not exist / no rows.
SHOW DATABASES LIKE 'DEVELOP';

-- 3. Pull the latest commit. Do this now, not live - the first FETCH after a
--    while can take a few seconds and dead air is expensive.
ALTER GIT REPOSITORY DCM_ADMIN.PROJECTS.PBI_REPO FETCH;
LS @DCM_ADMIN.PROJECTS.PBI_REPO/branches/main/;      -- expect 19 files

-- 4. Clear the drift log so the audit story reads cleanly.
--    Say so if asked: a real deployment would never truncate this.
TRUNCATE TABLE DCM_ADMIN.AUDIT.CTL_DCM_DRIFT_LOG;

-- 5. Make sure the task is scheduled, so section 10 has something to break.
ALTER TASK DCM_ADMIN.AUDIT.TASK_DCM_DRIFT_CHECK RESUME;
SELECT * FROM DCM_ADMIN.AUDIT.V_DCM_MONITOR_HEALTH;
```

After step 4 the health view will read `NEVER_RUN` — correct, and it becomes `OK` once
section 6 runs a check. If you want it green from the start, run one check by hand.

**Also before you start:**

- [ ] Snowsight zoom at **150%** — result grids are unreadable at default on a projector
- [ ] Have this file open in a second window
- [ ] Confirm the account switcher says **`LV16268`**, not the Snowy tenant
- [ ] Email client open on `amitbhopte099@gmail.com` for section 9
- [ ] Warehouse resumed — the first query of a demo shouldn't be a cold start

---

## 1 — The problem, in 90 seconds

> **Say:** "Our pipelines create tables with `CREATE TABLE IF NOT EXISTS`. Let me show you
> exactly what that does when the table is already there."

```sql
CREATE DATABASE DEMO_SCRATCH;
CREATE SCHEMA DEMO_SCRATCH.S;

CREATE TABLE IF NOT EXISTS DEMO_SCRATCH.S.CUSTOMER (ID VARCHAR(36), NAME VARCHAR(200));

-- someone, on a Tuesday, without telling anyone:
ALTER TABLE DEMO_SCRATCH.S.CUSTOMER ADD COLUMN SALARY VARCHAR(100);

-- now run the pipeline's DDL again, exactly as written:
CREATE TABLE IF NOT EXISTS DEMO_SCRATCH.S.CUSTOMER (ID VARCHAR(36), NAME VARCHAR(200));
```

Result: **`Table CUSTOMER successfully created.`** — green, successful, and a lie by omission.

```sql
DESC TABLE DEMO_SCRATCH.S.CUSTOMER;    -- three columns. SALARY is still there.
```

> **Say:** "The statement succeeded. It never looked inside. It cannot. Multiply that by
> **64 of these statements across 9 pipeline files** and you have a repo that can build the
> database but can never tell you whether the database still matches it. Every pipeline runs
> green forever while the repo is quietly wrong."

Leave `DEMO_SCRATCH` on screen for a beat, then:

```sql
DROP DATABASE DEMO_SCRATCH;
```

---

## 2 — Where the truth lives

Snowsight → **Projects → Workspaces** → the DCM workspace.

Open `sources/definitions/20_stg_capacities.sql`:

```sql
DEFINE TABLE DEVELOP.STG.BRIDGE_PBI_CAPACITY_ADMIN (
    CAPACITY_ID       VARCHAR(36),
    ADMIN_EMAIL       VARCHAR(500),
    INSERT_AUDIT_KEY  NUMBER(38,0),
    INSERT_DATE       TIMESTAMP_NTZ(9)
);
```

> **Say:** "`DEFINE`, not `CREATE`. It is a description of what should be true, not an
> instruction. Snowflake works out the difference. These files came from `GET_DDL` against the
> real dev database, so this is not an idealised schema — it is what is actually there."

Point out: **8 tables, 53 columns**, and that this is a git repo — the workspace is a view
onto GitHub, not a copy.

---

## 3 — Plan against an empty account

```sql
EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.PBI_CAPACITIES
    PLAN FROM '@DCM_ADMIN.PROJECTS.PBI_REPO/branches/main/';
```

**Expect: 14 entities — 13 create, 1 alter.** Click the cell to expand the JSON.

> **Say:** "Nothing has happened yet. This is a dry run — it tells you what it would do and
> changes nothing. The one 'alter' is Snowflake recording object ownership, and the extra
> schema is `PUBLIC`, which every database gets automatically."

⚠️ **Never type the word `DELTA` here.** `PLAN DELTA` skips definitions it believes unchanged
and cannot see hand-made edits. It would report clean over a drifted database and destroy the
entire point of section 6.

---

## 4 — Deploy

```sql
EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.PBI_CAPACITIES
    DEPLOY AS "demo_initial" FROM '@DCM_ADMIN.PROJECTS.PBI_REPO/branches/main/';
```

Then show it independently — not the tool marking its own homework:

```sql
SELECT TABLE_SCHEMA, TABLE_NAME, COUNT(*) AS COLS
FROM   DEVELOP.INFORMATION_SCHEMA.COLUMNS
WHERE  TABLE_SCHEMA IN ('LND','STG','PRE')
GROUP  BY 1,2 ORDER BY 1,2;
```

**Expect 8 rows, 53 columns.** Landing, staging, presentation — all three layers.

> **Say:** "That is the whole estate for capacities, built from a git commit. If someone new
> joins and needs an environment, this is the entire onboarding step."

---

## 5 — Run it twice

```sql
EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.PBI_CAPACITIES
    PLAN FROM '@DCM_ADMIN.PROJECTS.PBI_REPO/branches/main/';
```

**Expect: no changes.**

> **Say:** "Same standard we hold every audit run to — run it twice, the second run does
> nothing. It is not appending or rebuilding. It compared and found nothing to do."

---

## 6 — The reveal

**This is the demo. Slow down.**

> **Say:** "Now I'm going to do what a colleague does on a Tuesday afternoon."

```sql
ALTER TABLE DEVELOP.PRE.DIM_PBI_CAPACITIES
    ADD COLUMN QUICK_FIX_DONT_ASK VARCHAR(100);
```

> **Say (before running the plan):** "Nothing in our current pipelines would ever notice this.
> Not tonight, not next month. Watch."

```sql
CALL DCM_ADMIN.AUDIT.SP_DCM_DRIFT_CHECK_FROM_GIT();
```

**Expect: `DRIFT | entities=1 | alert sent`.** Then the part that matters:

```sql
SELECT OBJECT_FQN, COLUMN_NAME, WHAT_A_HUMAN_DID, DATATYPE
FROM   DCM_ADMIN.AUDIT.V_DCM_DRIFT_COLUMNS
ORDER  BY CHECK_ID DESC;
```

```
"DEVELOP"."PRE"."DIM_PBI_CAPACITIES"   QUICK_FIX_DONT_ASK   ADDED BY HAND   VARCHAR(100)
```

> **Say:** "Not 'a table differs'. The column name, the datatype, and what a person actually
> did. That is the difference between an alert worth waking up for and one people mute."

---

## 7 — Put it back

```sql
EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.PBI_CAPACITIES
    DEPLOY AS "demo_revert" FROM '@DCM_ADMIN.PROJECTS.PBI_REPO/branches/main/';

SELECT COUNT(*) AS COLS FROM DEVELOP.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA IN ('LND','STG','PRE');       -- back to 53
```

> **Say, and do not skip this:** "Reverting that column was a `DROP COLUMN`. If it had held
> data, that data is gone. Which is exactly why the nightly job only ever runs `PLAN`.
> **Deploying is a decision a person makes after reading a plan.** We never schedule it."

---

## 8 — The one that surprises people

> **Say:** "You'd assume dropping a column is the easy case. It is the hard one."

```sql
-- REGION is column 5 of 8 in this table
ALTER TABLE DEVELOP.STG.DIM_PBI_CAPACITIES DROP COLUMN REGION;

CALL DCM_ADMIN.AUDIT.SP_DCM_DRIFT_CHECK_FROM_GIT();
```

**Expect: `ERROR`**, not `DRIFT`:

```
Unsupported feature 'CREATE OR ALTER TABLE column add before end of column list'.
```

> **Say:** "Snowflake can only *append* columns. Putting `REGION` back in position 5 is a
> reorder, and that is unsupported. So this cannot be auto-reverted at all — and the plan
> didn't report drift, it failed outright, which means **any other drift in that file went
> unchecked behind it.**
>
> **45 of our 53 columns are not the last column in their table.** So this is not the edge
> case. It is the common case. Any monitor that only asks 'was the changeset empty?' reads the
> worst outcome as a broken job."

Recovery — do it on screen, it makes the point:

```sql
DROP TABLE DEVELOP.STG.DIM_PBI_CAPACITIES;
EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.PBI_CAPACITIES
    DEPLOY AS "demo_recover" FROM '@DCM_ADMIN.PROJECTS.PBI_REPO/branches/main/';
```

> **Say:** "Empty table, so that was two statements. On a table with data it is unload, drop,
> redeploy, reload. That is planned maintenance, not a 3am fix."

---

## 9 — What Snowflake forgets

```sql
SELECT PHASE, COUNT(*) AS N
FROM   TABLE(DCM_ADMIN.INFORMATION_SCHEMA.DCM_DEPLOYMENT_HISTORY(
             project_name => 'DCM_ADMIN.PROJECTS.PBI_CAPACITIES', result_limit => 100))
GROUP  BY 1;
```

**Expect: `DEPLOY` rows only. No `PLAN` rows — ever.**

> **Say:** "We have run several plans this morning. Snowflake recorded none of them. It keeps
> a full immutable record of every *deployment* — and the drift check is the one operation it
> does not remember. Which is awkward, because drift detection is the entire reason we are
> here. Native history also caps at 12 months and has no `ACCOUNT_USAGE` view."

```sql
SELECT CHECK_ID, CHECKED_AT_UTC, VERDICT, ENTITIES_CHANGED, NOTIFIED
FROM   DCM_ADMIN.AUDIT.CTL_DCM_DRIFT_LOG
ORDER  BY CHECKED_AT_UTC;
```

> **Say:** "So we keep our own. Every check, forever, with the full changeset. This answers
> *'when did this drift start?'* — which is the question you actually ask during an incident,
> and the one that took seven months to answer last time."

**Then show the email.** Open the inbox on screen — subject `[DRIFT] Snowflake schema drift`,
naming the column, in plain English.

---

## 10 — Watching the watcher

> **Say:** "A monitor that stops running looks exactly like a monitor finding nothing wrong.
> Both are silence."

```sql
ALTER TASK DCM_ADMIN.AUDIT.TASK_DCM_DRIFT_CHECK SUSPEND;
SELECT * FROM DCM_ADMIN.AUDIT.V_DCM_MONITOR_HEALTH;
```

**Expect: `HEALTH = TASK_NOT_SCHEDULED`, `NEXT_RUN_UTC = NULL`.**

```sql
ALTER TASK DCM_ADMIN.AUDIT.TASK_DCM_DRIFT_CHECK RESUME;
SELECT * FROM DCM_ADMIN.AUDIT.V_DCM_MONITOR_HEALTH;      -- OK, next run populated
```

> **Say, if you are willing to be candid — and it lands well:** "This check exists because we
> got it wrong. The task sat suspended for a day and the health view cheerfully said `OK`,
> because it only measured whether the log was recent, not whether the job was still switched
> on. Same mistake as `IF NOT EXISTS`: something that reports success without having checked
> what it claims to check."

---

## 11 — The full loop, git → Snowflake

In the Snowsight workspace, add a column to a definition file — e.g. in
`sources/definitions/30_pre_capacities.sql` add `DEMO_NOTE VARCHAR(50)` at the **end** of
`PRE.FACT_PBI_CAPACITY_OBSERVATION`. Commit and push from the workspace.

```sql
ALTER GIT REPOSITORY DCM_ADMIN.PROJECTS.PBI_REPO FETCH;

EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.PBI_CAPACITIES
    PLAN FROM '@DCM_ADMIN.PROJECTS.PBI_REPO/branches/main/';
```

**Expect one `ALTER TABLE`, adding `DEMO_NOTE`.**

> **Say:** "Same mechanism, opposite direction. Section 6 was the database moving away from
> git. This is git moving ahead of the database — a reviewed change, arriving through a pull
> request. One tool, one changeset format, both directions."

Deploy it, then revert the commit and deploy again so the demo account ends clean.

> **Note:** `FETCH` is not automatic. The nightly job fetches before every plan — otherwise it
> compares the database against a stale copy of the repo and calls the difference drift.

---

## 12 — Close honestly

> **Say:** "What this is: a proof of concept. 8 tables, 53 columns, no data, one slice of the
> estate, in a personal account. DCM Projects is a **preview** feature.
>
> What it is not: proven for views, tasks, streams or grants. Untested at 64 tables. And the
> `ERROR` recovery path has only ever been run against empty tables — on a table holding real
> data, that is a rehearsal we still owe ourselves before this goes anywhere near production.
>
> What it does prove: the second guarantee is buyable. The database can tell us, every
> morning, whether it still matches the repo — and name the column when it doesn't."

Leave the artifact link and the repo on screen for questions.

---

## If something breaks live

| Symptom | Cause | Do this |
|---|---|---|
| `PLAN` reports 13 creates when you expected none | `PURGE` ran but you skipped `DEPLOY` | Run section 4 |
| `PLAN` errors, file/line in the message | Un-revertible drift left from an earlier run | `DROP TABLE` the named table, then deploy |
| Object not found `@...PBI_REPO/...` | Clone is stale or empty | `ALTER GIT REPOSITORY ... FETCH;` then `LS` |
| Alert says `no alert sent` on `DRIFT` | Notification integration or recipient issue | Move on — show `CTL_DCM_DRIFT_LOG` instead; the finding is recorded either way |
| `HEALTH = STALE` unexpectedly | No check has run in 26h | Run `SP_DCM_DRIFT_CHECK_FROM_GIT()` once |
| Everything is wrong | — | `PURGE`, then section 4. Full rebuild is ~20 seconds |

**Golden rule:** if a step misbehaves, do not debug it live. Say *"that's a good example of
why we log every run"*, show the log, and move on. The audit trail turns a failed demo step
into a demonstration of the audit trail.

---

## Questions you will get

| Question | Answer |
|---|---|
| "Why not Terraform?" | Terraform is better for account-level objects — warehouses, roles, integrations — and keeps an external state file. DCM is native, has no state file, and covers in-database objects. Common practice is both. |
| "Does this replace Matillion?" | No. Matillion moves data. This manages the shape of the tables the data lands in. |
| "What if two people deploy at once?" | Not tested. Genuine gap — worth saying so. |
| "Can it roll back?" | Not as a command. You revert the commit and deploy again — git is the rollback mechanism. |
| "What does it cost?" | Warehouse time only. A plan over 8 tables takes ~3 seconds. |
| "Can we point this at production today?" | No — preview feature, and `DEPLOY` drops columns. `PLAN` on a schedule is the safe first step, and it is read-only. |
