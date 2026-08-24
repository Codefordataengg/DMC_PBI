# Demo run sheet — DCM and Git, the full round trip

**~51 min + questions. Short cut ~22 min, marked ⏩.**

Build a DCM project in Snowflake, push it to an empty GitHub repo, pull it back in as a
Snowflake-managed clone, develop against it, ship the change through git, and catch someone
tampering with the database in between.

The audience sees a change travel the whole loop — twice — and sees what happens when
something bypasses it.

Runs in the personal account (`LV16268`). Nothing touches Snowy's `DEVELOP` or Matillion.

---

## The spine of the demo: three questions, three diffs

Put this on a slide, or draw it. Everything below is an instance of it.

| Question | Answered by | Shown in |
|---|---|---|
| What changed in the **definition**? | `git diff` | §6 |
| What will change in the **database**? | `DCM PLAN` | §7 |
| What changed in the database **without going through git**? | drift check | §8 |

> **Say early, and repeat at the end:** "Git tells you what someone *wrote*. The plan tells you
> what will *happen*. Neither of those catches the third case — somebody changing the database
> directly. That third one is what we've never been able to see."

---

## Contents

| | Section | Min | |
|---|---|---|---|
| — | [Pre-flight](#pre-flight) | 15 | alone, before anyone joins |
| 1 | [The problem, in 90 seconds](#1--the-problem-in-90-seconds) | 3 | ⏩ |
| 2 | [Build it in Snowflake](#2--build-it-in-snowflake) | 8 | ⏩ |
| 3 | [**Push to an empty repo**](#3--push-to-an-empty-repo) | 4 | ⏩ |
| 4 | [**Pull it back, both ways**](#4--pull-it-back-both-ways) — UI *and* SQL | 7 | ⏩ |
| 5 | [Develop on a branch](#5--develop-on-a-branch) | 4 | |
| 6 | [**Diff one — what the code changed**](#6--diff-one--what-the-code-changed) | 3 | ⏩ |
| 7 | [**Diff two — what the database will do**](#7--diff-two--what-the-database-will-do) | 4 | ⏩ |
| 8 | [**Diff three — the reveal**](#8--diff-three--the-reveal) | 5 | ⏩ |
| 9 | [Put it back](#9--put-it-back) | 2 | ⏩ |
| 10 | [The one that surprises people](#10--the-one-that-surprises-people) | 4 | |
| 11 | [One source, two environments](#11--one-source-two-environments) | 4 | |
| 12 | [Every morning, unattended](#12--every-morning-unattended) | 4 | |
| 13 | [Close honestly](#13--close-honestly) | 2 | ⏩ |
| — | [If something breaks live](#if-something-breaks-live) | — | **read first** |

---

## Pre-flight

### A. Create an empty GitHub repo — do this first

**`DCM_DEMO`, private, and genuinely empty** — no README, no `.gitignore`, no licence.
"GitHub shows you nothing" is the opening shot of §3 and a repo with a README ruins it.

Use `Codefordataengg`. Your existing API integration is scoped to
`https://github.com/Codefordataengg`, **not** to one repo — so a new repo needs no new secret,
no new integration. Mention that in §4; it is a good detail.

### B. Reset Snowflake

```sql
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

DROP DATABASE       IF EXISTS DEMO_PBI;
DROP DCM PROJECT    IF EXISTS DCM_ADMIN.PROJECTS.DEMO_CAPACITIES;
DROP GIT REPOSITORY IF EXISTS DCM_ADMIN.PROJECTS.DEMO_REPO;

CREATE DATABASE IF NOT EXISTS DCM_ADMIN;
CREATE SCHEMA   IF NOT EXISTS DCM_ADMIN.PROJECTS;
```

Leave the real `PBI_REPO`, `PBI_CAPACITIES` and the nightly task alone — §11 uses them.

**Also delete any leftover demo workspaces** (Projects → Workspaces). You will create two
during the demo and it helps to start with none:

| Created in | Name it | Why it exists |
|---|---|---|
| §2 | `demo-authoring` | scaffolded from nothing, no git |
| §4a | `demo-from-git` | created *from* the repo URL |

Naming them on creation avoids the muddle of two identical-looking workspaces on screen.

### C. Checklist

- [ ] **Rehearse §2 and §5 once.** They are the only sections with real typing
- [ ] Browser tabs, in order: **GitHub repo** · **Snowsight** · [findings artifact](https://claude.ai/code/artifact/e873f965-68d1-44c2-912b-c5cb41f2baa3)
- [ ] Snowsight zoom **150%**
- [ ] Account switcher reads **`LV16268`**
- [ ] Warehouse resumed
- [ ] GitHub token to hand — the workspace will ask when you first push
- [ ] Know how to switch branches in the workspace **before** you're on stage

---

## 1 — The problem, in 90 seconds

Before mentioning DCM or git at all.

```sql
CREATE DATABASE DEMO_SCRATCH;
CREATE SCHEMA DEMO_SCRATCH.S;

CREATE TABLE IF NOT EXISTS DEMO_SCRATCH.S.CUSTOMER (ID VARCHAR(36), NAME VARCHAR(200));

-- someone, on a Tuesday, without telling anyone:
ALTER TABLE DEMO_SCRATCH.S.CUSTOMER ADD COLUMN SALARY VARCHAR(100);

-- now re-run the pipeline's own DDL, exactly as written:
CREATE TABLE IF NOT EXISTS DEMO_SCRATCH.S.CUSTOMER (ID VARCHAR(36), NAME VARCHAR(200));
```

**`Table CUSTOMER successfully created.`** — green, successful, and a lie by omission.

```sql
DESC TABLE DEMO_SCRATCH.S.CUSTOMER;      -- three columns. SALARY is still there.
DROP DATABASE DEMO_SCRATCH;
```

> **Say:** "It succeeded without looking inside, because it cannot look inside. Multiply that
> by **64 such statements across 9 pipeline files**. The repo can build the database. It can
> never tell you the database still matches it."

---

## 2 — Build it in Snowflake

**Snowsight → Projects → Workspaces → `+ Add new` → DCM Project.**

Snowflake scaffolds:

```
manifest.yml
sources/definitions/  examples.sql, jinja_demo.sql   ← delete both
sources/macros/       grants_macro.sql               ← keep
.gitignore   README.md
```

Scroll `examples.sql` without reading it aloud — point out it declares warehouses, dynamic
tables, **roles and grants**, then delete it.

### The manifest — walk all three blocks

Open `manifest.yml`. The scaffold generates three blocks and **placeholders in two of them
that will bite you**. Change what is marked.

```yaml
manifest_version: 2                       # schema version. Leave it.
type: DCM_PROJECT

default_target: DCM_DEV                   # which target runs when you don't say

targets:
  DCM_DEV:
    account_identifier: YVTSYHL-PP80681
    project_name: DCM_ADMIN.PROJECTS.DEMO_CAPACITIES   # ← CHANGE
    project_owner: ACCOUNTADMIN
    templating_config: DEV

templating:
  defaults:
    project_owner_role: "ACCOUNTADMIN"    # ← CHANGE from "MY_ROLE"
    wh_size: "SMALL"
  configurations:
    DEV:
      env_suffix: ""                      # ← CHANGE from "_MY_PROJECT_OBJECT"
      teams:
        - name: "SAMPLE_TEAM"
          data_retention_days: 1
```

> **Say, pointing at each block:** "`targets` is *where* — which account, which project object.
> `templating` is *what varies* — the values that differ between environments. And
> `default_target` picks one when you don't name it."

**Two changes matter, and say why out loud:**

| Placeholder | Change to | If you don't |
|---|---|---|
| `env_suffix: "_MY_PROJECT_OBJECT"` | `""` | Every object gets that string appended — `DEMO_PBI_MY_PROJECT_OBJECT` |
| `project_owner_role: "MY_ROLE"` | `"ACCOUNTADMIN"` | The grants macro references a role that doesn't exist |

> **Say:** "`env_suffix` is empty for now so the names stay readable. I'll come back to it —
> it's how one set of files builds both dev and prod."

That forward reference sets up §11. Don't explain it further here.

**If `sources/definitions/` is empty** — you deleted the examples, which is right — the Output
pane reads `Files: 0, Errors: 0`. That is not an error. It has nothing to analyse yet.

Create `sources/definitions/10_capacities.sql`:

```sql
DEFINE DATABASE DEMO_PBI
    COMMENT = 'Power BI governance estate - demo';

DEFINE SCHEMA DEMO_PBI.LND COMMENT = 'Landing - raw API payloads';
DEFINE SCHEMA DEMO_PBI.PRE COMMENT = 'Presentation - merge targets';

DEFINE TABLE DEMO_PBI.LND."PBI_AllCapacities" (
    AUDIT_KEY         NUMBER(38,0)     NOT NULL,
    ROUTE             VARCHAR(200)     NOT NULL,
    PAGE_SEQ          NUMBER(38,0)     NOT NULL,
    IS_FINAL_PAGE     BOOLEAN          NOT NULL,
    EXTRACTED_AT_UTC  TIMESTAMP_TZ(9)  NOT NULL,
    PAYLOAD           VARIANT
);

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

> **Say:** "`DEFINE`, not `CREATE` — a description of what should be true, not an instruction.
> And these types aren't invented; they came from `GET_DDL` against the real dev database."

### First Plan — expect a dialog

The first time you click **Plan**, Snowsight will say:

> **Project does not exist.** `DCM_ADMIN.PROJECTS.DEMO_CAPACITIES` doesn't exist. You can
> create it now using this name and owner role `ACCOUNTADMIN` specified in `manifest.yml`.

**Click Create.** This is expected, not an error — and it is worth a sentence rather than
clicking past it.

> **Say:** "Two different things share that name. The manifest *declares* the project should be
> called `DEMO_CAPACITIES` — that's a line of YAML. The project object is the real thing in
> Snowflake that holds deployment history. Snowflake just noticed the declaration had nothing
> behind it and offered to fix it.
>
> Which is the same shape as everything else today: something declared, something real, and a
> check that the two agree."

The equivalent in SQL, if you prefer to pre-create it:

```sql
CREATE DCM PROJECT IF NOT EXISTS DCM_ADMIN.PROJECTS.DEMO_CAPACITIES;
```

**Prerequisite:** the schema `DCM_ADMIN.PROJECTS` must already exist — pre-flight creates it.
The dialog cannot create a missing schema, only the project.

**Plan** → 6 entities, 5 create, 1 alter. **Deploy.** Then verify independently:

```sql
SELECT TABLE_SCHEMA, TABLE_NAME, COUNT(*) AS COLS
FROM   DEMO_PBI.INFORMATION_SCHEMA.COLUMNS
WHERE  TABLE_SCHEMA IN ('LND','PRE')
GROUP  BY 1,2 ORDER BY 1,2;
```

**Plan again → no changes.** Run it twice, second run does nothing.

---

## 3 — Push to an empty repo

**Switch to the GitHub tab.** Show it: no files, no commits, nothing.

> **Say:** "Everything so far lives in my workspace. It's mine — nobody can review it, nobody
> can rebuild it, and if I lose it, it's gone."

In the workspace: **connect to Git**, point at `DCM_DEMO`, commit, push.
Message: `Initial capacities schema`.

**Back to the GitHub tab. Refresh.**

> **Say:** "That's the same thing you just watched me build — now it's the team's. It can be
> reviewed, branched, rolled back, and rebuilt by anyone."

Open `10_capacities.sql` **on GitHub** and let them see it rendered there. The point is that
this is ordinary code in an ordinary repo, not a Snowflake-flavoured special case.

---

## 4 — Pull it back, both ways

> **Say:** "Now the direction people find confusing. There are two ways to bring that repo into
> Snowflake, they are **not** alternatives, and you will usually want both. Let me show you why."

### 4a — The UI route: a workspace from a git URL

**Projects → Workspaces → `+ Add new` → From Git repository.**

Fill in:

| Field | Value |
|---|---|
| Repository URL | `https://github.com/Codefordataengg/DCM_DEMO.git` |
| API integration | `GIT_API_CODEFORDATAENGG` |
| Authentication | Personal access token |
| Credentials | `DCM_ADMIN.PROJECTS.GITHUB_PAT` |

**Create.** The files appear in the editor — the same files you pushed in §3, now arriving from
GitHub rather than from your local session.

> **Say:** "No new credential and no new integration. The API integration is scoped to the
> whole GitHub account rather than one repo, so a second repo just works."

Show the git controls in the workspace toolbar — **branch selector, Pull, Commit, Push**. Pull
once, so they see it fetch.

> **Say:** "This is a git client with a SQL editor attached. Everything you'd expect — branch,
> pull, commit, push — without leaving Snowflake."

Run **Plan** from the workspace button.

**Expect: no changes.**

> **Say:** "I built this from a *different* workspace in §2. This one came from GitHub, and it
> agrees the database is already correct. Same truth, verified from two directions."

### 4b — The SQL route: a repository object

> **Say:** "So why would I need anything else? Because that workspace is **mine**."

```sql
SHOW GIT REPOSITORIES IN ACCOUNT;
```

**Expect: the workspace you just created does NOT appear here.**

> **Say:** "A workspace lives in a personal, per-user database. It exists for a human with a
> browser open. A scheduled job at 5am has no browser and no workspace — so Snowflake needs an
> account-level copy that belongs to the account, not to me."

```sql
CREATE GIT REPOSITORY DCM_ADMIN.PROJECTS.DEMO_REPO
    API_INTEGRATION = GIT_API_CODEFORDATAENGG
    GIT_CREDENTIALS = DCM_ADMIN.PROJECTS.GITHUB_PAT
    ORIGIN          = 'https://github.com/Codefordataengg/DCM_DEMO.git';

ALTER GIT REPOSITORY DCM_ADMIN.PROJECTS.DEMO_REPO FETCH;

LS @DCM_ADMIN.PROJECTS.DEMO_REPO/branches/main/;
```

Run `SHOW GIT REPOSITORIES IN ACCOUNT;` again — **now it appears.**

And the same parity check, from this third path:

```sql
EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.DEMO_CAPACITIES
    PLAN FROM '@DCM_ADMIN.PROJECTS.DEMO_REPO/branches/main/';
```

**Expect: no changes.**

### Which is which

| | Workspace | `GIT REPOSITORY` |
|---|---|---|
| Created by | UI: *From Git repository* | SQL: `CREATE GIT REPOSITORY` |
| Lives in | your personal `USER$` database | a schema you choose |
| Belongs to | **you** | the account |
| Good for | editing, branching, committing | tasks, procedures, automation |
| Path form | `snow://workspace/...` | `@DB.SCHEMA.REPO/branches/main/` |
| Updates by | **Pull** button | `ALTER ... FETCH` |
| Survives you leaving | no | yes |

> **Say:** "The workspace is where a person works. The repository object is what the machine
> reads at five in the morning. Delete my workspace and the nightly check carries on. Delete
> the repository object and it stops."

## 5 — Develop on a branch

In the workspace, create a branch: **`add-region-view`**.

> **Say:** "Nobody edits main directly. Same discipline as application code."

Add to `sources/definitions/10_capacities.sql`:

```sql
DEFINE VIEW DEMO_PBI.PRE.V_CAPACITY_BY_REGION AS
    SELECT REGION,
           COUNT(*)                    AS CAPACITY_COUNT,
           COUNT_IF(STATE = 'Active')  AS ACTIVE_COUNT
    FROM   DEMO_PBI.PRE.DIM_PBI_CAPACITIES
    WHERE  IS_CURRENT_FLAG = 1
    GROUP  BY REGION;
```

Commit and push the branch.

---

## 6 — Diff one: what the code changed

**GitHub tab.** Open the branch, click **Compare / Open pull request**.

> **Say:** "This is the diff every engineer already knows. Green lines, red lines, a reviewer,
> an approval. Nothing about it is Snowflake-specific — which is the point. Schema changes now
> arrive the same way application changes do."

Leave the PR open on screen.

> **Say:** "But notice what this diff does *not* tell you. It says I added twelve lines of SQL.
> It does not tell you what will happen to the database when that lands. Those are different
> questions."

---

## 7 — Diff two: what the database will do

Merge the PR on GitHub. **Then back to Snowsight — do this in the UI first:**

In the workspace: switch the branch selector to **`main`**, click **Pull**. The merged view
definition appears. Click **Plan**.

Then the same thing from the account-level clone, so they see both stay in step:

```sql
ALTER GIT REPOSITORY DCM_ADMIN.PROJECTS.DEMO_REPO FETCH;

EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.DEMO_CAPACITIES
    PLAN FROM '@DCM_ADMIN.PROJECTS.DEMO_REPO/branches/main/';
```

> **Say:** "Two pulls, because there are two copies — mine and the account's. The button
> updated my workspace. `FETCH` updated the one the nightly job reads. Miss the second and the
> 5am check is still looking at yesterday's repo."

**Expect: 1 entity to create — the view.**

> **Say:** "Twelve lines of SQL in git became exactly one change to the database: create one
> view. That's the second diff. A reviewer can see both — what was written, and what it will
> do — before anything happens."

Deploy it, then confirm:

```sql
SELECT * FROM DEMO_PBI.PRE.V_CAPACITY_BY_REGION;
```

> **Note if `FETCH` slips your mind:** the clone doesn't update on its own. That's why the
> nightly job fetches before every plan — otherwise it compares the database to a stale copy of
> the repo and calls the difference drift.

**The round trip is now complete: Snowflake → git → Snowflake → git → Snowflake.**

---

## 8 — Diff three: the reveal

**Slow down. This is the demo.**

> **Say:** "Everything so far went through git. Now watch someone skip it."

```sql
ALTER TABLE DEMO_PBI.PRE.DIM_PBI_CAPACITIES
    ADD COLUMN QUICK_FIX_DONT_ASK VARCHAR(100);
```

**Switch to the GitHub tab. Refresh it.**

> **Say — this is the moment:** "Nothing. No commit, no PR, no diff. As far as git is
> concerned, nothing happened. And every pipeline we run tonight will be green."

**Back to Snowsight:**

```sql
EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.DEMO_CAPACITIES
    PLAN FROM '@DCM_ADMIN.PROJECTS.DEMO_REPO/branches/main/';
```

**Expect an `ALTER TABLE`, and in the JSON:**

```
columns: removed "QUICK_FIX_DONT_ASK"   datatype VARCHAR(100), nullable true
```

> **Say:** "The column name, the datatype, and which direction the fix runs. Git couldn't see
> this — there was no commit to see. This is the third diff, and it's the one we've never had."

---

## 9 — Put it back

Deploy.

> **Say, and do not skip it:** "Reverting that was a `DROP COLUMN`. If it had held data, that
> data is gone. Which is why the scheduled job only ever runs `PLAN`. **Deploy is a decision a
> person makes after reading a plan.** We never schedule it."

---

## 10 — The one that surprises people

```sql
-- REGION is column 5 of 8
ALTER TABLE DEMO_PBI.PRE.DIM_PBI_CAPACITIES DROP COLUMN REGION;
```

Plan. **Expect an error, not a changeset:**

```
Unsupported feature 'CREATE OR ALTER TABLE column add before end of column list'.
```

> **Say:** "Snowflake can only *append* columns, so restoring `REGION` to position 5 is a
> reorder — unsupported. This cannot be auto-reverted at all. And the plan didn't report drift,
> it **failed** — so any other drift in that file went unchecked behind it.
>
> In the real slice, **45 of 53 columns are not last in their table.** This is the common case,
> not the edge case."

Recover on screen: `DROP TABLE DEMO_PBI.PRE.DIM_PBI_CAPACITIES;` then Deploy.

> **Say:** "Empty table, two steps. With data: unload, drop, redeploy, reload. Planned
> maintenance, not a 3am fix."

---

## 11 — One source, two environments

> **Say:** "Remember `env_suffix`. Here is what it's for."

In `manifest.yml`, add a second target and configuration:

```yaml
targets:
  DCM_DEV:
    account_identifier: YVTSYHL-PP80681
    project_name: DCM_ADMIN.PROJECTS.DEMO_CAPACITIES
    project_owner: ACCOUNTADMIN
    templating_config: DEV
  DCM_PROD:                                    # same account, for the demo
    account_identifier: YVTSYHL-PP80681
    project_name: DCM_ADMIN.PROJECTS.DEMO_CAPACITIES
    project_owner: ACCOUNTADMIN
    templating_config: PROD

templating:
  configurations:
    DEV:
      env_suffix: ""
    PROD:
      env_suffix: "_PROD"
```

Then reference it in the definitions — one edit, at the top of `10_capacities.sql`:

```sql
DEFINE DATABASE DEMO_PBI{{env_suffix}}
```

…and the same `{{env_suffix}}` on each `DEFINE SCHEMA` and `DEFINE TABLE`.

Plan against each target. In the workspace use the **target selector** (bottom right of the
Output pane — it currently reads `DCM_DEV (default)`), or in SQL:

```sql
EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.DEMO_CAPACITIES
    PLAN USING CONFIGURATION PROD
    FROM '@DCM_ADMIN.PROJECTS.DEMO_REPO/branches/main/';
```

**Expect: `DEMO_PBI_PROD`, `DEMO_PBI_PROD.PRE.DIM_PBI_CAPACITIES`** — a full set of creates,
because that environment doesn't exist yet.

> **Say:** "Same files. Same commit. Same review. Different environment. The differences between
> dev and prod are declared in one place instead of living in two copies of the DDL that drift
> apart — which is how everyone actually ends up with a prod schema nobody can reproduce.
>
> And note *this* is the honest version of 'promote to production': you don't copy anything.
> You point the same reviewed definition at a different target."

**Don't deploy it** unless you have time — the plan is the point. If you do, remember to purge
it afterwards.

---

## 12 — Every morning, unattended

Switch to the **real** project.

```sql
SELECT * FROM DCM_ADMIN.AUDIT.V_DCM_MONITOR_HEALTH;

SELECT CHECK_ID, CHECKED_AT_UTC, VERDICT, ENTITIES_CHANGED, NOTIFIED
FROM   DCM_ADMIN.AUDIT.CTL_DCM_DRIFT_LOG
ORDER  BY CHECKED_AT_UTC DESC LIMIT 10;
```

> **Say:** "05:00 UTC, every day. Fetch main, plan, log the result, email if it isn't clean.
> `PLAN` only — never deploy."

Then the finding that forced this design:

```sql
SELECT PHASE, COUNT(*) AS N
FROM   TABLE(DCM_ADMIN.INFORMATION_SCHEMA.DCM_DEPLOYMENT_HISTORY(
             project_name => 'DCM_ADMIN.PROJECTS.PBI_CAPACITIES', result_limit => 100))
GROUP  BY 1;
```

> **Say:** "`DEPLOY` rows only. Snowflake keeps a complete immutable record of every
> deployment — and records **no plans at all**. The drift check is the one operation it
> forgets, which is awkward when drift detection is the whole point. So we keep our own log.
> It answers *'when did this drift start?'* — the question that took seven months last time."

Show the alert email, and — if you're willing, it lands well:

> "The health view exists because we got it wrong. The task sat suspended for a day and it
> cheerfully reported `OK`, because it measured whether the log was recent, not whether the job
> was still running. Same mistake as `IF NOT EXISTS`."

---

## 13 — Close honestly

> **Say:** "Three diffs. Git shows what someone wrote. The plan shows what will happen. The
> drift check shows what happened *without* either — and that third one is what we've never
> been able to see.
>
> What this is: a proof of concept. 8 tables, no data, one slice, personal account. DCM
> Projects is a **preview** feature. Grants, tasks and streams are unproven. The un-revertible
> recovery path has only been rehearsed on empty tables.
>
> What it proves: the database can tell us every morning whether it still matches the repo, and
> name the column when it doesn't."

---

## If something breaks live

| Symptom | Cause | Do |
|---|---|---|
| Plan shows unexpected creates | Rehearsal objects left behind | `DROP DATABASE DEMO_PBI;` then §2 Deploy |
| Plan errors with file and line | Un-revertible drift from earlier | `DROP TABLE` the named table, Deploy |
| `LS @...DEMO_REPO/...` empty | Clone stale, or pushed to a branch | `ALTER GIT REPOSITORY ... FETCH;` and check the branch |
| Push from workspace rejected | Token expired | Skip §3's push; show the **real** repo instead and carry on |
| *From Git repository* won't create | API integration or credential not selectable | Skip 4a, do 4b in SQL, and say the UI is a convenience over the same objects |
| Workspace shows an old branch | Branch selector still on the previous one | Switch it, then **Pull** — worth narrating, it is the same mistake as forgetting `FETCH` |
| Two workspaces confuse you mid-demo | §2 and §4a each made one | Name them on creation: `demo-authoring` and `demo-from-git` |
| Objects appear as `DEMO_PBI_MY_PROJECT_OBJECT` | `env_suffix` placeholder left as scaffolded | Set it to `""` in the manifest, re-plan |
| `Files: 0, Errors: 0` in Output | `sources/definitions/` is empty | Expected before §2's definitions exist. Not an error |
| Grants macro errors on a missing role | `project_owner_role` still `"MY_ROLE"` | Set it to `ACCOUNTADMIN`, or delete `sources/macros/` |
| "Project does not exist" dialog | Normal on first Plan — the object hasn't been created yet | Click **Create**. Narrate it, don't apologise for it |
| **Create** in that dialog fails | Schema `DCM_ADMIN.PROJECTS` missing | `CREATE SCHEMA DCM_ADMIN.PROJECTS;` then Plan again |
| Plan from git disagrees with workspace | Forgot to `FETCH` after merging | `FETCH`, re-plan. **Good teaching moment — say so out loud** |
| Everything is wrong | — | `DROP DATABASE DEMO_PBI;` → §2. Rebuild ≈ 15 seconds |

**Golden rule:** never debug live. Say *"good example of why every run gets logged"*, show the
log, move on. A failed step becomes a demonstration of the audit trail.

---

## Questions you will get

| Question | Answer |
|---|---|
| "Why not just use git hooks / CI?" | You can, and Snowflake publishes GitHub Actions for it — plan on PR, deploy on merge. But CI only sees changes that go *through* CI. Drift is the case that doesn't. |
| "Why not Terraform?" | Terraform suits account-level objects and keeps an external state file. DCM is native and stateless. Common practice is both. |
| "Does this replace Matillion?" | No. Matillion moves data; this manages the shape of the tables it lands in. |
| "Can it roll back?" | Not as a command — revert the commit and deploy. Git *is* the rollback mechanism. |
| "Two people deploy at once?" | Untested. Genuine gap — say so. |
| "What does it cost?" | Warehouse time. A plan over 8 tables takes about three seconds. |
| "Point it at production today?" | No. Preview feature, and `DEPLOY` drops columns. Scheduled `PLAN` is the safe first step — it's read-only. |
