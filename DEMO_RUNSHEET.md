# Demo run sheet — building a DCM project from nothing

**~35 min + questions. Short cut ~15 min, marked ⏩.**

You build a project live in Snowsight: scaffold it, write the definitions, plan, deploy,
break it, catch the break, then put it under version control. Nothing is pulled from a repo —
the audience watches it come into existence.

Everything runs in the personal account (`LV16268`). Nothing touches Snowy's `DEVELOP` or any
Matillion pipeline.

> **The one sentence they should leave with:**
> *"Our repo can build the database. It cannot prove the database still matches it. That
> second guarantee is what was missing — and here is what it costs to buy."*

---

## Contents

| | Section | Min | |
|---|---|---|---|
| — | [Pre-flight](#pre-flight) | 10 | alone, before anyone joins |
| 1 | [The problem, in 90 seconds](#1--the-problem-in-90-seconds) | 3 | ⏩ |
| 2 | [Scaffold the project](#2--scaffold-the-project) | 4 | ⏩ |
| 3 | [Read the manifest](#3--read-the-manifest) | 3 | |
| 4 | [Write the definitions](#4--write-the-definitions) | 5 | ⏩ |
| 5 | [Plan](#5--plan) | 3 | ⏩ |
| 6 | [Deploy](#6--deploy) | 3 | ⏩ |
| 7 | [Run it twice](#7--run-it-twice) | 1 | ⏩ |
| 8 | [Add a view, live](#8--add-a-view-live) | 3 | |
| 9 | [**The reveal**](#9--the-reveal) | 5 | ⏩ |
| 10 | [The one that surprises people](#10--the-one-that-surprises-people) | 4 | |
| 11 | [Put it under version control](#11--put-it-under-version-control) | 3 | |
| 12 | [What this looks like at scale](#12--what-this-looks-like-at-scale) | 4 | |
| 13 | [Close honestly](#13--close-honestly) | 2 | ⏩ |
| — | [If something breaks live](#if-something-breaks-live) | — | **read first** |

---

## Pre-flight

Do this alone. Never in front of the audience.

```sql
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

-- Clear anything left from a rehearsal.
DROP DATABASE IF EXISTS DEMO_PBI;
DROP DCM PROJECT IF EXISTS DCM_ADMIN.PROJECTS.DEMO_CAPACITIES;

-- Somewhere for the demo project object to live (the real one already uses this).
CREATE DATABASE IF NOT EXISTS DCM_ADMIN;
CREATE SCHEMA   IF NOT EXISTS DCM_ADMIN.PROJECTS;
```

**Checklist:**

- [ ] Snowsight zoom **150%** — result grids are unreadable on a projector at default
- [ ] Account switcher says **`LV16268`**, not the Snowy tenant
- [ ] Warehouse resumed — the first query of a demo should not be a cold start
- [ ] This file open in a second window
- [ ] **Rehearse §4 once.** It is the only section with real typing, and it is the one that
      bites
- [ ] Have the [findings artifact](https://claude.ai/code/artifact/e873f965-68d1-44c2-912b-c5cb41f2baa3)
      and the real repo open in browser tabs for §12

---

## 1 — The problem, in 90 seconds

Do this before mentioning DCM at all.

> **Say:** "Our pipelines create tables with `CREATE TABLE IF NOT EXISTS`. Let me show you what
> that actually does when the table is already there."

```sql
CREATE DATABASE DEMO_SCRATCH;
CREATE SCHEMA DEMO_SCRATCH.S;

CREATE TABLE IF NOT EXISTS DEMO_SCRATCH.S.CUSTOMER (ID VARCHAR(36), NAME VARCHAR(200));

-- someone, on a Tuesday, without telling anyone:
ALTER TABLE DEMO_SCRATCH.S.CUSTOMER ADD COLUMN SALARY VARCHAR(100);

-- now re-run the pipeline's own DDL, exactly as written:
CREATE TABLE IF NOT EXISTS DEMO_SCRATCH.S.CUSTOMER (ID VARCHAR(36), NAME VARCHAR(200));
```

**`Table CUSTOMER successfully created.`** Green. Successful. And a lie by omission.

```sql
DESC TABLE DEMO_SCRATCH.S.CUSTOMER;     -- three columns. SALARY is still there.
```

> **Say:** "It succeeded without looking inside. It cannot look inside. Now multiply that by
> **64 of these statements across 9 pipeline files**. The repo can build the database. It can
> never tell you whether the database still matches it — and every pipeline stays green while
> the repo is quietly wrong."

```sql
DROP DATABASE DEMO_SCRATCH;
```

---

## 2 — Scaffold the project

**Snowsight → Projects → Workspaces → `+ Add new` → DCM Project.**

Snowflake generates the whole structure:

```
manifest.yml
sources/
  definitions/
    examples.sql        ← delete this
    jinja_demo.sql      ← delete this
  macros/
    grants_macro.sql    ← keep, mention in §12
.gitignore
README.md
```

> **Say:** "That folder layout is not a convention we invented — Snowflake requires definitions
> under `sources/definitions/`. It will not find them anywhere else."

Open `examples.sql` and scroll it **without reading it aloud**. Point out only that it
declares warehouses, databases, schemas, tables, **dynamic tables, roles and grants** — then
delete both example files.

> **Say:** "Worth knowing the scope: this is not just tables. Roles and grants are declarable
> too, which means access can live in the same reviewed file as the schema. We haven't proven
> that part yet — I'll come back to it."

---

## 3 — Read the manifest

Open `manifest.yml`. Two things matter; skip the rest.

```yaml
targets:
  DCM_DEV:
    account_identifier: YVTSYHL-PP80681
    project_name: DCM_ADMIN.PROJECTS.DEMO_CAPACITIES
    project_owner: ACCOUNTADMIN
    templating_config: DEV

templating:
  configurations:
    DEV:
      env_suffix: "_DEV"
```

> **Say:** "`targets` is which account and which project object. `templating` is the
> interesting one — the same definition files can build dev and prod, with the differences
> declared here rather than living in two divergent copies of the DDL. That is the problem
> everyone solves badly with copy-paste."

Set `project_name` to `DCM_ADMIN.PROJECTS.DEMO_CAPACITIES`, and for a simpler demo set
`env_suffix: ""`.

---

## 4 — Write the definitions

**The only section with real typing. Paste, don't type.**

Create `sources/definitions/10_capacities.sql`:

```sql
DEFINE DATABASE DEMO_PBI
    COMMENT = 'Power BI governance estate - demo';

DEFINE SCHEMA DEMO_PBI.LND COMMENT = 'Landing - raw API payloads';
DEFINE SCHEMA DEMO_PBI.PRE COMMENT = 'Presentation - merge targets';

-- Landing. The quoted mixed-case name is deliberate: it mirrors the real
-- estate, and renaming it would be a breaking change to everything downstream.
DEFINE TABLE DEMO_PBI.LND."PBI_AllCapacities" (
    AUDIT_KEY         NUMBER(38,0)     NOT NULL,
    ROUTE             VARCHAR(200)     NOT NULL,
    PAGE_SEQ          NUMBER(38,0)     NOT NULL,
    IS_FINAL_PAGE     BOOLEAN          NOT NULL,
    EXTRACTED_AT_UTC  TIMESTAMP_TZ(9)  NOT NULL,
    PAYLOAD           VARIANT
);

-- Presentation. This is the merge target the reports actually read.
DEFINE TABLE DEMO_PBI.PRE.DIM_PBI_CAPACITIES (
    ID                VARCHAR(36)   NOT NULL,
    NAME              VARCHAR(500),
    SKU               VARCHAR(50),
    STATE             VARCHAR(50),
    REGION            VARCHAR(200),
    INSERT_AUDIT_KEY  NUMBER(38,0),
    INSERT_DATE       TIMESTAMP_NTZ(9),
    IS_CURRENT_FLAG   NUMBER(1,0)   DEFAULT 1
);
```

> **Say:** "`DEFINE`, not `CREATE`. It is a description of what should be true, not an
> instruction to do something. Snowflake works out the difference between this and reality.
>
> And these types are not invented — they came from `GET_DDL` against the real dev database.
> When we diffed all 53 columns of the real slice against what our pipelines claim to create,
> they matched exactly. Which was reassuring, and also the last time anyone will ever check
> that by hand."

---

## 5 — Plan

Click **Plan** in the workspace (or run it as SQL).

**Expect: 6 entities — 5 create, 1 alter.** Expand the JSON.

> **Say:** "Nothing has happened yet. This is a dry run — it reports what it would do and
> changes nothing. The 'alter' is Snowflake recording ownership. The extra schema is `PUBLIC`,
> which every database gets automatically."

⚠️ **Never use `PLAN DELTA`.** It skips definitions it believes unchanged and cannot see
hand-made edits — it would report clean over a drifted database and destroy §9 entirely.

---

## 6 — Deploy

Click **Deploy**. Then verify independently — not the tool marking its own homework:

```sql
SELECT TABLE_SCHEMA, TABLE_NAME, COUNT(*) AS COLS
FROM   DEMO_PBI.INFORMATION_SCHEMA.COLUMNS
WHERE  TABLE_SCHEMA IN ('LND','PRE')
GROUP  BY 1,2 ORDER BY 1,2;
```

**Expect 2 rows: `PBI_AllCapacities` 6, `DIM_PBI_CAPACITIES` 8.**

> **Say:** "Landing and presentation, built from a text file. If someone joins next week and
> needs an environment, that is the entire onboarding step."

---

## 7 — Run it twice

Click **Plan** again. **Expect: no changes.**

> **Say:** "Same bar we hold every audit run to — run it twice, the second run does nothing.
> It compared, and found nothing to do."

---

## 8 — Add a view, live

Add to the same file, then Plan and Deploy:

```sql
DEFINE VIEW DEMO_PBI.PRE.V_CAPACITY_BY_REGION AS
    SELECT REGION,
           COUNT(*)                                   AS CAPACITY_COUNT,
           COUNT_IF(STATE = 'Active')                 AS ACTIVE_COUNT
    FROM   DEMO_PBI.PRE.DIM_PBI_CAPACITIES
    WHERE  IS_CURRENT_FLAG = 1
    GROUP  BY REGION;
```

**Expect: 1 entity to create.**

> **Say:** "Same mechanism, and now a change rather than a creation. This is the loop you'd
> actually live in — edit the file, plan, review, deploy."

Views are worth a beat: drift on a view reports the **before-and-after `SELECT`**, not just a
column list. For a view, the query *is* the object.

---

## 9 — The reveal

**This is the demo. Slow down.**

> **Say:** "Now I'll do what a colleague does on a Tuesday afternoon."

```sql
ALTER TABLE DEMO_PBI.PRE.DIM_PBI_CAPACITIES
    ADD COLUMN QUICK_FIX_DONT_ASK VARCHAR(100);
```

> **Say before planning:** "Nothing in our current pipelines would ever notice that. Not
> tonight, not next month. Watch."

Click **Plan**.

**Expect:** an `ALTER TABLE`, and in the JSON:

```
columns: removed "QUICK_FIX_DONT_ASK"   datatype VARCHAR(100), nullable true
```

> **Say:** "Not 'a table differs'. The column name, its datatype, and which direction the fix
> runs. That is the difference between an alert worth waking for and one people mute."

Deploy to revert, then:

> **Say, and do not skip it:** "Reverting that was a `DROP COLUMN`. If it had held data, that
> data is gone. Which is exactly why the scheduled job only ever runs `PLAN`. **Deploying is a
> decision a person makes after reading a plan.** We never schedule it."

---

## 10 — The one that surprises people

> **Say:** "You'd assume dropping a column is the easy case. It's the hard one."

```sql
-- REGION is column 5 of 8
ALTER TABLE DEMO_PBI.PRE.DIM_PBI_CAPACITIES DROP COLUMN REGION;
```

Click **Plan**. **Expect an error, not a changeset:**

```
Unsupported feature 'CREATE OR ALTER TABLE column add before end of column list'.
```

> **Say:** "Snowflake can only *append* columns. Putting `REGION` back in position 5 is a
> reorder, and that's unsupported — so this cannot be auto-reverted at all. And notice the plan
> didn't report drift, it **failed** — which means any other drift in that file went unchecked
> behind it.
>
> In the real slice, **45 of 53 columns are not the last column in their table.** So this isn't
> the edge case. It's the common one. Any monitor that only asks 'was the changeset empty?'
> reads the worst outcome as a broken job."

Recover on screen — it makes the point:

```sql
DROP TABLE DEMO_PBI.PRE.DIM_PBI_CAPACITIES;
```
…then Deploy.

> **Say:** "Empty table, so that was two steps. On a table with data it's unload, drop,
> redeploy, reload. Planned maintenance, not a 3am fix."

---

## 11 — Put it under version control

In the workspace, connect to Git and push.

> **Say:** "Everything so far lived in a workspace, which is mine. This makes it the team's.
> From here the definitions are reviewed in pull requests like any other code — and the same
> plan output can be posted to the PR so a reviewer sees exactly what will change before
> approving it."

Point out the direction, because it is the thing people get wrong:

```
edit → commit → GitHub → FETCH → Snowflake
                                     │
        there is no path back ───────┘
```

> **Say:** "One way only. A hand-made `ALTER` never flows back into the repo. That asymmetry is
> precisely why drift detection has to exist."

---

## 12 — What this looks like at scale

Switch to the real repo and the findings page.

> **Say:** "What you just watched is the toy version. The real slice is 8 tables, 53 columns,
> across landing, staging and presentation — and it runs a drift check every night at 05:00."

Show, briefly:

| Show | Point |
|---|---|
| `FINDINGS.md` | Ten findings, dated and evidenced. Three came from deliberately breaking it |
| `CTL_DCM_DRIFT_LOG` | **Snowflake records every deploy and no plans at all** — so the drift check is the one operation it forgets. We keep our own log, which answers *"when did this drift start?"* |
| `V_DCM_MONITOR_HEALTH` | Catches the monitor being switched off — because a stopped monitor and a clean one are both silence |
| `sources/macros/` | Roles and grants are declarable too. **Untested by us**, and worth saying so |

> **Say, if you're willing — it lands well:** "The health check exists because we got it wrong.
> The task sat suspended for a day and the view cheerfully reported `OK`, because it only
> measured whether the log was recent, not whether the job was still running. Same mistake as
> `IF NOT EXISTS` — something reporting success without checking what it claims to check."

---

## 13 — Close honestly

> **Say:** "What this is: a proof of concept. 8 tables, no data, one slice, in a personal
> account. DCM Projects is a **preview** feature.
>
> What it is not: proven for grants, tasks or streams. Untested at 64 tables. And the
> un-revertible recovery path has only been run on empty tables — on a table with real data,
> that rehearsal is one we still owe ourselves.
>
> What it does prove: the second guarantee is buyable. The database can tell us every morning
> whether it still matches the repo, and name the column when it doesn't."

---

## If something breaks live

| Symptom | Cause | Do |
|---|---|---|
| Plan shows creates you didn't expect | A rehearsal left objects behind | `DROP DATABASE DEMO_PBI;` then §6 |
| Plan errors with a file and line | Un-revertible drift from an earlier run | `DROP TABLE` the named table, Deploy |
| Deploy fails on the database | Name collision with a rehearsal | Change `DEMO_PBI` to `DEMO_PBI2` throughout |
| Workspace won't save or commit | Session expired | Reload Snowsight; the files persist |
| Everything is wrong | — | `DROP DATABASE DEMO_PBI;` → §5. Full rebuild ≈ 15 seconds |

**Golden rule:** never debug live. Say *"good example of why every run gets logged"*, show the
log, move on. A failed step becomes a demonstration of the audit trail.

---

## Questions you will get

| Question | Answer |
|---|---|
| "Why not Terraform?" | Terraform suits account-level objects — warehouses, roles, integrations — and keeps an external state file. DCM is native, stateless, and covers in-database objects. Common practice is both. |
| "Does this replace Matillion?" | No. Matillion moves data. This manages the shape of the tables it lands in. |
| "Can it roll back?" | Not as a command. You revert the commit and deploy again — git is the rollback mechanism. |
| "Two people deploy at once?" | Untested. Genuine gap — say so. |
| "What does it cost?" | Warehouse time. A plan over 8 tables takes about three seconds. |
| "Point it at production today?" | No. Preview feature, and `DEPLOY` drops columns. Scheduled `PLAN` is the safe first step — it's read-only. |
| "What about the data in the tables?" | DCM manages structure only. It never reads or writes rows. |
