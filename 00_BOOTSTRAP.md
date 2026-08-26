# Bootstrap — build the whole thing from nothing

**The order matters and is not obvious from the filenames.** `12_GIT_INTEGRATION.sql` has to be
run in *two halves*, with other files in between, because its task depends on a procedure
defined in `11_ALERTING.sql`.

This file is the only place that order is written down. If you change the dependency shape,
change it here.

**Every step gives the UI path first, then the SQL.** Some steps have no UI path at all — those
are marked. Doing it in the UI is slower but it is what you will be showing, so learn it that
way.

### What can and cannot be done in the UI

| Step | UI | SQL |
|---|---|---|
| Database + schema | ✅ Databases → **+ Database** | ✅ |
| Secret (git PAT) | ⚠️ only inside the *From Git repository* dialog | ✅ `CREATE SECRET` |
| API integration | ✅ Admin → **Integrations** → Create | ✅ |
| **Git repository object** | ❌ **no UI path** — a workspace does *not* create one | ✅ `CREATE GIT REPOSITORY` |
| DCM project **folder** (files) | ✅ Workspaces → **+ Add new** → DCM Project | ❌ n/a |
| DCM project **object** (Snowflake) | ✅ the *Project does not exist* → **Create** dialog | ✅ |
| Plan / Deploy | ✅ workspace buttons | ✅ |
| Audit + alerting scripts | ❌ paste into a worksheet | ✅ |
| Notification integration | ✅ Admin → **Integrations** → Create | ✅ |
| Task creation | ❌ no UI path | ✅ |
| Task resume / suspend | ✅ Transformation → **Tasks** → actions menu | ✅ |
| Task history | ✅ Transformation → **Tasks** | ✅ |

**The two that force you into SQL** are the git repository object and the task. Everything else
you can drive from the interface.

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

**UI:** Databases → **+ Database** → name `DCM_ADMIN` → Create.
Then select it → **+ Schema** → name `PROJECTS` → Create.

**SQL:**

```sql
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

CREATE DATABASE IF NOT EXISTS DCM_ADMIN;
CREATE SCHEMA   IF NOT EXISTS DCM_ADMIN.PROJECTS;
```

> Set the role picker to `ACCOUNTADMIN` in the top-right before you start. Objects get created
> owned by whatever role is active, and getting this wrong is tedious to unpick later.

### 2 — Git plumbing — `12_GIT_INTEGRATION.sql` §1–§4

**The API integration has a UI path. The secret and the repository object do not.**

**2a. API integration — UI:** Admin → **Integrations** → **Create** → choose the git type.
Set allowed prefix `https://github.com/Codefordataengg`. Or run §2 of the SQL file.

**2b. Secret — SQL.** Paste your token into §1 and run it.

> **Do not commit the file with a real token in it.** GitHub auto-revokes leaked tokens and you
> would be back to step 0. Put the placeholder back afterwards.

**2c. Git repository object — SQL only.** Run §3 and §4.

> ❌ **There is no UI for this**, and it is the single most common misunderstanding. Creating a
> workspace *From Git repository* gives **you** a git-connected editor. It does **not** create
> an account-level `GIT REPOSITORY` object, and a scheduled task cannot read a workspace.
> Prove it to yourself: `SHOW GIT REPOSITORIES IN ACCOUNT;` after making a git workspace — it
> will not be listed.

Stop after §4's `LS`. **Expect 20+ files under `branches/main/`.**

### 3 — The project object

> **Two things share the name "DCM project" and they are not the same:**
>
> | | What it is | Made by |
> |---|---|---|
> | **Project folder** | `manifest.yml` + `sources/definitions/` — *files* | `+ Add new` → **DCM Project** |
> | **Project object** | Snowflake object holding deployment history — *a database object* | the **Create** dialog, or SQL |
>
> Proof they are separate: create a folder with `+ Add new → DCM Project`, click **Plan**, and
> Snowsight tells you the project *does not exist*. The folder did not make the object.
>
> **For this bootstrap you do not need `+ Add new`** — the files come from git, so the workspace
> already has them. You need only the object, below.

**UI, and this is the one worth doing in the interface:** open a workspace containing the
project's `manifest.yml` and click **Plan**. Snowsight sees the manifest names a project that
does not exist and offers:

> **Project does not exist.** `DCM_ADMIN.PROJECTS.PBI_CAPACITIES` doesn't exist. You can create
> it now using this name and owner role `ACCOUNTADMIN` specified in `manifest.yml`.

Click **Create**. It reads the name and owner straight from the manifest, so there is nothing
to type and nothing to get wrong.

**SQL:**

```sql
CREATE DCM PROJECT IF NOT EXISTS DCM_ADMIN.PROJECTS.PBI_CAPACITIES
    COMMENT = 'Power BI capacities slice, all three layers.';
```

> The dialog cannot create a missing **schema** — only the project. If `DCM_ADMIN.PROJECTS`
> does not exist, **Create** fails. That is step 1.

### 4 — Build the estate

**UI:** in the workspace, **Plan** button (bottom right of the Output pane), then **Deploy**
from the same dropdown. The changeset renders as an expandable list rather than raw JSON —
easier to read, and better to show an audience.

**SQL** — and note this plans from the *repository object*, not the workspace, which is the
path the nightly task uses:

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

❌ **No UI path.** Open a SQL worksheet (Projects → Worksheets → **+**), paste the whole file,
**Run All**. Watch for red — a failure halfway leaves you with some objects and not others.

Creates: `AUDIT` schema · `CTL_DCM_DRIFT_LOG` · `SEQ_DCM_CHECK_ID` ·
`V_DCM_DRIFT_OBJECTS` · `V_DCM_DRIFT_COLUMNS` · `SP_DCM_DRIFT_CHECK`.

**Defines no task.** That is deliberate — see F9.

### 6 — Alerting — run `11_ALERTING.sql` whole

The notification integration in §1 of that file **can** be made in the UI — Admin →
**Integrations** → Create → Notification — but running the whole script is simpler and keeps
the recipient list in version control.

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

**UI:** Transformation → **Tasks** → `TASK_DCM_DRIFT_CHECK` → actions menu (⋯) → **Resume**.
The same page shows run history, so it is where you check tomorrow morning whether it fired.

**SQL:**

```sql
ALTER TASK DCM_ADMIN.AUDIT.TASK_DCM_DRIFT_CHECK RESUME;
SELECT * FROM DCM_ADMIN.AUDIT.V_DCM_MONITOR_HEALTH;     -- expect HEALTH = OK, NEXT_RUN_UTC set
```

> Task history in the UI only covers the **last 7 days**. Your own `CTL_DCM_DRIFT_LOG` is the
> durable record — which is F6, in practical form.

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

Then wait one night and confirm `SUCCEEDED` — the only proof that matters (F11).

**UI:** Transformation → **Tasks** → select the task → run history.
**SQL:** the `TASK_HISTORY` query in `evidence/task_history_2026-08-26.csv`'s header.

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
