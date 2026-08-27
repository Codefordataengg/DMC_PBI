# Demo run sheet — DCM + Git, the full round trip with review

**~45 min + questions.** Follow it top to bottom. Everything runs in the personal account
(`LV16268`). Nothing touches Snowy's `DEVELOP` or Matillion.

> **The one sentence they should leave with:**
> *"Our repo can build the database. It couldn't prove the database still matches it. That second
> guarantee is what was missing — and here it is, every morning, naming the column when it drifts."*

---

## Names used everywhere in this run sheet

Keep these exact — every command below depends on them.

| Thing | Name |
|---|---|
| GitHub repo | `DCM_DEMO` — **private**, README only at the start |
| Workspace | `dcm-demo` — created *From Git repository* |
| Project folder (in the repo) | `capacities/` → repo path `branches/main/capacities/` |
| DCM project object — dev | `DCM_ADMIN.PROJECTS.CAPACITIES_DEV` |
| DCM project object — prod | `DCM_ADMIN.PROJECTS.CAPACITIES_PROD` |
| Databases | `DEMO_PBI_DEV`, `DEMO_PBI_PROD` (built via `env_suffix`) |
| Git repository object | `DCM_ADMIN.PROJECTS.DEMO_REPO` |
| Feature branch | `add-fact-table` |

**Two rules that drive the whole flow:**
- **Dev is deployed from the workspace** (local files) — fast, no gate.
- **Prod is deployed from git `main` only** — after a PR is merged. Snowflake never deploys prod from a branch or a laptop.
- **One DCM project object per environment** (F16). Dev and prod cannot share one, or deploying prod drops the dev database.

---

## The spine: three questions, three diffs

Put this on a slide or say it early, and echo it at the end.

| Question | Answered by | Shown in |
|---|---|---|
| What changed in the **definition**? | `git diff` on the PR | §6 |
| What will change in the **database**? | `DCM PLAN` | §7 |
| What changed **without going through either**? | the drift check | §8 |

---

# PRE-FLIGHT (do alone, ~10 min before anyone joins)

## A. Clean slate — remove everything from prior runs

Keeps the secret and API integration; drops the demo databases, projects, git-repo object, and workspaces.

**A1 — SQL (run as `ACCOUNTADMIN`):**
```sql
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

-- databases built by earlier runs
DROP DATABASE IF EXISTS DEMO_PBI_DEV;
DROP DATABASE IF EXISTS DEMO_PBI_PROD;
DROP DATABASE IF EXISTS DEMO_PBI;          -- old un-suffixed one, if any

-- DCM project objects (old single one + per-env)
DROP DCM PROJECT IF EXISTS DCM_ADMIN.PROJECTS.DEMO_CAPACITIES;
DROP DCM PROJECT IF EXISTS DCM_ADMIN.PROJECTS.CAPACITIES_DEV;
DROP DCM PROJECT IF EXISTS DCM_ADMIN.PROJECTS.CAPACITIES_PROD;

-- the demo git-repository clone (NOT the real PBI_REPO)
DROP GIT REPOSITORY IF EXISTS DCM_ADMIN.PROJECTS.DEMO_REPO;

-- confirm the clean state
SHOW DATABASES LIKE 'DEMO_PBI%';           -- expect: no rows
SHOW DCM PROJECTS IN SCHEMA DCM_ADMIN.PROJECTS;   -- expect: none of the above
```

> **Do NOT drop:** `DCM_ADMIN`, the `PROJECTS` schema, the `GITHUB_PAT` secret, the
> `GIT_API_CODEFORDATAENGG` integration, or `PBI_REPO` (that's the real project's clone). Those are
> the plumbing you're keeping.

**A2 — UI: delete the demo workspaces.** Projects → Workspaces → open the menu on any previous
`dcm-demo` (or `DCM_DEMO`) workspace → **Delete**. Workspaces can't be dropped from SQL. Start with none.

## B. GitHub — reset the repo to a clean slate

`DCM_DEMO` must be **private** (workspaces can't push to a public repo) and contain **only a
`README`** on `main`, so the "repo fills up" moment in §3 lands.

- If the repo has files from a prior run: delete the `capacities/` folder (and any stray `out/`,
  `.gitignore`) on GitHub so `main` is just the README.
- Confirm **Settings → General → Danger Zone** shows it as **Private**.

## C. Checklist

- [ ] `snow`/workspace connection points at **`LV16268`** — not the Snowy tenant
- [ ] **GitHub PAT** valid, `repo` scope (write), stored in the `GITHUB_PAT` secret
- [ ] Snowsight zoom **150%**; warehouse `COMPUTE_WH` resumed
- [ ] Browser tabs in order: **GitHub `DCM_DEMO`** · **Snowsight** · findings artifact
- [ ] Email client open on `amitbhopte099@gmail.com` (for §12)
- [ ] **Rehearse §2 and §5 once** — the only sections with real typing / branch work

---

# THE DEMO

## 1 — The problem, in 90 seconds

Before mentioning DCM at all.

```sql
CREATE DATABASE DEMO_SCRATCH;
CREATE SCHEMA DEMO_SCRATCH.S;
CREATE TABLE IF NOT EXISTS DEMO_SCRATCH.S.CUSTOMER (ID VARCHAR(36), NAME VARCHAR(200));
-- someone, on a Tuesday, without telling anyone:
ALTER TABLE DEMO_SCRATCH.S.CUSTOMER ADD COLUMN SALARY VARCHAR(100);
-- now re-run the pipeline's own DDL, exactly as written:
CREATE TABLE IF NOT EXISTS DEMO_SCRATCH.S.CUSTOMER (ID VARCHAR(36), NAME VARCHAR(200));
```

Result: **`CUSTOMER already exists, statement succeeded.`**

```sql
DESC TABLE DEMO_SCRATCH.S.CUSTOMER;    -- three columns. SALARY is still there.
DROP DATABASE DEMO_SCRATCH;
```

> **Say:** "It succeeded, and it's honest — it says it already exists and did nothing. The problem
> is that *doing nothing counts as success*, and nothing compares the table to what we declared.
> Multiply by **70 of these statements across 8 pipeline files**. The repo can build the database.
> It can never tell you the database still matches it — and no data is harmed, which is exactly why
> it stays invisible for months."

---

## 2 — Build it in Snowflake, deploy DEV

### 2a. Create the git-backed workspace — this order can't be changed

**Projects → Workspaces → `From Git repository`.**

| Field | Value |
|---|---|
| Repository URL | `https://github.com/Codefordataengg/DCM_DEMO.git` |
| API integration | `GIT_API_CODEFORDATAENGG` |
| Authentication | Personal access token |
| Credentials | `DCM_ADMIN.PROJECTS.GITHUB_PAT` |
| Workspace name | `dcm-demo` |

> ⚠️ **A workspace can only be connected to git at creation.** If you author first in a plain
> workspace, there's no way to push. This step is non-negotiable and comes first.

### 2b. Scaffold the project inside it

**`+ Add new` → DCM Project**, name it **`capacities`**. That creates `capacities/manifest.yml`
and `capacities/sources/`.

**Delete the scaffold samples** (you're not using them):
`capacities/sources/definitions/examples.sql`, `jinja_demo.sql`, and `capacities/sources/macros/grants_macro.sql`.

### 2c. Add a `.gitignore` so `out/` never gets committed

`+ Add new → File` inside `capacities/`, name it **`.gitignore`**, contents:
```
out/
**/.DS_Store
```
> `out/` is build output the Plan/Deploy buttons generate. If it's pushed, DCM reads the rendered
> copy as a *second* set of definitions and the plan fails with a conflict. This `.gitignore` — added
> **before** the first plan — prevents that. If `out/` ever shows in Changes, delete it before pushing.

### 2d. Write the manifest — two environments, two project objects

Open `capacities/manifest.yml`. Replace its contents with:
```yaml
manifest_version: 2
type: DCM_PROJECT

default_target: DCM_DEV

targets:
  DCM_DEV:
    account_identifier: YVTSYHL-PP80681
    project_name: DCM_ADMIN.PROJECTS.CAPACITIES_DEV
    project_owner: ACCOUNTADMIN
    templating_config: DEV
  DCM_PROD:
    account_identifier: YVTSYHL-PP80681
    project_name: DCM_ADMIN.PROJECTS.CAPACITIES_PROD
    project_owner: ACCOUNTADMIN
    templating_config: PROD

templating:
  configurations:
    DEV:  { env_suffix: "_DEV" }
    PROD: { env_suffix: "_PROD" }
```

> **Say (F16):** "One project object holds one environment. Dev and prod are separate projects —
> `CAPACITIES_DEV` and `CAPACITIES_PROD` — or a prod deploy would drop the whole dev database. Same
> files build both; the only difference is `env_suffix`."

### 2e. Write the definitions — two tables, hold one back

Create `capacities/sources/definitions/10_capacities.sql`:
```sql
DEFINE DATABASE DEMO_PBI{{env_suffix}}
    COMMENT = 'Power BI governance estate - demo';

DEFINE SCHEMA DEMO_PBI{{env_suffix}}.LND COMMENT = 'Landing - raw API payloads';
DEFINE SCHEMA DEMO_PBI{{env_suffix}}.PRE COMMENT = 'Presentation - merge targets';

DEFINE TABLE DEMO_PBI{{env_suffix}}.LND."PBI_AllCapacities" (
    AUDIT_KEY         NUMBER(38,0)     NOT NULL,
    ROUTE             VARCHAR(200)     NOT NULL,
    PAGE_SEQ          NUMBER(38,0)     NOT NULL,
    IS_FINAL_PAGE     BOOLEAN          NOT NULL,
    EXTRACTED_AT_UTC  TIMESTAMP_TZ(9)  NOT NULL,
    PAYLOAD           VARIANT
);

DEFINE TABLE DEMO_PBI{{env_suffix}}.PRE.DIM_PBI_CAPACITIES (
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
> **Say:** "`DEFINE`, not `CREATE` — a description, not an instruction. The `FACT` table is held
> back on purpose; I'll add it later so you can watch a *change* travel through review to prod."

### 2f. Plan → Create → Deploy DEV

Click **Plan** (bottom-right of the Output pane, target reads `DCM_DEV (default)`).

- First Plan shows **"Project does not exist"** → **Create**. This makes `CAPACITIES_DEV`. Expected.
- Plan result: **6 entities — 5 create, 1 alter.** Then **Deploy** → builds `DEMO_PBI_DEV`.

Verify:
```sql
SELECT TABLE_SCHEMA, TABLE_NAME, COUNT(*) AS COLS
FROM   DEMO_PBI_DEV.INFORMATION_SCHEMA.COLUMNS
WHERE  TABLE_SCHEMA IN ('LND','PRE')
GROUP  BY 1,2 ORDER BY 1,2;               -- 2 tables
```
> **Say:** "That's dev — deployed straight from my workspace, fast, no gate. Prod is different:
> it only ever comes from git, after review."

---

## 3 — Push the initial project to `main`

**GitHub tab:** show `DCM_DEMO` — just a README.

Workspace → **Changes** tab. You should see `capacities/manifest.yml`,
`capacities/sources/definitions/10_capacities.sql`, `capacities/.gitignore` — **and no `out/`**
(if `out/` appears, delete it first). Commit message `Initial capacities schema` → **Push**.

**GitHub tab → refresh.** The repo now shows the `capacities/` project.

> **Say:** "Everything I built is now the team's — reviewable, rebuildable, versioned."

---

## 4 — Pull it back as a clone, deploy PROD from git

The workspace is mine and per-user; a scheduled job needs an account-level copy.

```sql
SHOW GIT REPOSITORIES IN ACCOUNT;    -- the workspace is NOT listed; it's personal

CREATE GIT REPOSITORY DCM_ADMIN.PROJECTS.DEMO_REPO
    API_INTEGRATION = GIT_API_CODEFORDATAENGG
    GIT_CREDENTIALS = DCM_ADMIN.PROJECTS.GITHUB_PAT
    ORIGIN          = 'https://github.com/Codefordataengg/DCM_DEMO.git';

ALTER GIT REPOSITORY DCM_ADMIN.PROJECTS.DEMO_REPO FETCH;

LS @DCM_ADMIN.PROJECTS.DEMO_REPO/branches/main/capacities/;   -- manifest.yml + sources/, no out/
```

**Parity check** — plan the DEV config from git against the dev database the workspace built:
```sql
EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.CAPACITIES_DEV
    PLAN USING CONFIGURATION DEV
    FROM '@DCM_ADMIN.PROJECTS.DEMO_REPO/branches/main/capacities/';
```
**Expect: no changes.**
> **Say:** "I built dev from my workspace; I'm now planning it from the account's own clone, a
> completely different path — and it agrees. Same truth, two directions."

**Now deploy PROD from git** — its own project object:
```sql
CREATE DCM PROJECT IF NOT EXISTS DCM_ADMIN.PROJECTS.CAPACITIES_PROD;

EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.CAPACITIES_PROD
    DEPLOY AS "prod_release"
    USING CONFIGURATION PROD
    FROM '@DCM_ADMIN.PROJECTS.DEMO_REPO/branches/main/capacities/';

SHOW DATABASES LIKE 'DEMO_PBI%';         -- BOTH DEMO_PBI_DEV and DEMO_PBI_PROD now exist
```
> **Say — land it slowly:** "Prod was not deployed from my workspace. It came from the reviewed
> `main`, via `USING CONFIGURATION PROD`, into its own project. Same files that built dev — I copied
> nothing. And because prod comes from git, git and prod agree by construction."

---

## 5 — A change, on a branch (this is the review flow)

> **Say:** "Now a real change — and this time it goes through review, the way a prod change should."

**Workspace → Changes tab → branch selector → New branch → `add-fact-table`.**

Append to `capacities/sources/definitions/10_capacities.sql`:
```sql
DEFINE TABLE DEMO_PBI{{env_suffix}}.PRE.FACT_PBI_CAPACITY_OBSERVATION (
    OBSERVED_DATE     DATE          NOT NULL,
    CAPACITY_ID       VARCHAR(36)   NOT NULL,
    SKU               VARCHAR(50),
    STATE             VARCHAR(50),
    REGION            VARCHAR(200),
    ADMIN_COUNT       NUMBER(38,0),
    INSERT_AUDIT_KEY  NUMBER(38,0),
    INSERT_DATE       TIMESTAMP_NTZ(9)
);
```

**Deploy DEV** from the workspace (still fast, still no gate) → adds the fact table to `DEMO_PBI_DEV`.

**Changes tab** → commit `Add capacity observation fact table` → **Push** (pushes the *branch*).

> **Say:** "Dev already has the change — I deployed it straight from my branch. Prod hasn't seen it,
> and won't, until it's reviewed."

---

## 6 — Diff one: the PR (review + approval)

**GitHub tab.** A banner offers the pushed branch → **Compare & pull request** → **Create pull request**.

- Open the PR. The **Files changed** tab shows the added `FACT_PBI_CAPACITY_OBSERVATION` — green lines.

> **Say:** "This is the diff every engineer knows — and it's the approval gate. Nothing reaches
> `main`, and therefore nothing reaches prod, without this review. In a real pipeline, a GitHub
> Action runs `dcm plan` here and posts the exact changeset as a comment, so the reviewer sees what
> will happen to the database before approving. That's Snowflake's own recommended CI/CD pattern."

**Approve → Merge pull request → Confirm merge.** `main` now has the change.

---

## 7 — Diff two: deploy PROD from the merged `main`

```sql
ALTER GIT REPOSITORY DCM_ADMIN.PROJECTS.DEMO_REPO FETCH;   -- pull the merged main

EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.CAPACITIES_PROD
    PLAN USING CONFIGURATION PROD
    FROM '@DCM_ADMIN.PROJECTS.DEMO_REPO/branches/main/capacities/';
```
**Expect: 1 entity to create — `FACT_PBI_CAPACITY_OBSERVATION`.**
> **Say:** "The plan is the second diff: those lines of SQL become exactly one change — create one
> table in prod. Visible before anything happens."

Deploy it:
```sql
EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.CAPACITIES_PROD
    DEPLOY AS "add_fact_prod"
    USING CONFIGURATION PROD
    FROM '@DCM_ADMIN.PROJECTS.DEMO_REPO/branches/main/capacities/';

SELECT COUNT(*) AS TABLES FROM DEMO_PBI_PROD.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA IN ('LND','PRE');       -- now 3
```
> **The round trip is complete:** workspace → branch → PR → merged `main` → prod. Dev fast, prod reviewed.

---

## 8 — Diff three: the reveal

> **Say:** "Everything so far went through git. Now watch someone skip it — a hotfix straight on prod."

```sql
ALTER TABLE DEMO_PBI_PROD.PRE.DIM_PBI_CAPACITIES
    ADD COLUMN QUICK_FIX_DONT_ASK VARCHAR(100);
```

**GitHub tab → refresh.** Nothing. No commit, no PR, no diff.
> **Say:** "As far as git is concerned, nothing happened. And every pipeline tonight is green."

**Back to Snowsight — drift-check prod against git:**
```sql
EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.CAPACITIES_PROD
    PLAN USING CONFIGURATION PROD
    FROM '@DCM_ADMIN.PROJECTS.DEMO_REPO/branches/main/capacities/';
```
**Expect an `ALTER TABLE`, and in the JSON:**
```
columns: removed "QUICK_FIX_DONT_ASK"   datatype VARCHAR(100), nullable true
```
> **Say:** "The column name, the datatype, the direction of the fix. Git couldn't see this — there
> was no commit. This is the third diff, and it's the one we've never had."

---

## 9 — Put it back

```sql
EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.CAPACITIES_PROD
    DEPLOY USING CONFIGURATION PROD
    FROM '@DCM_ADMIN.PROJECTS.DEMO_REPO/branches/main/capacities/';
```
> **Say, don't skip:** "Reverting that was a `DROP COLUMN`. If it held data, that data is gone —
> which is why the scheduled job only ever runs `PLAN`. Deploy is a human decision, and prod is only
> ever reverted from git, never by hand."

---

## 10 — The one that surprises people

> **Say:** "You'd think dropping a column is the easy case. It's the hard one."

```sql
-- REGION is column 5 of 8
ALTER TABLE DEMO_PBI_PROD.PRE.DIM_PBI_CAPACITIES DROP COLUMN REGION;

EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.CAPACITIES_PROD
    PLAN USING CONFIGURATION PROD
    FROM '@DCM_ADMIN.PROJECTS.DEMO_REPO/branches/main/capacities/';
```
**Expect an error, not a changeset:**
```
Unsupported feature 'CREATE OR ALTER TABLE column add before end of column list'.
```
> **Say:** "Snowflake can only *append* columns, so restoring `REGION` to position 5 is a reorder —
> unsupported. This can't be auto-reverted, and the plan *failed*, so any other drift behind it went
> unchecked. In the real slice, 45 of 53 columns aren't last — so this is the common case."

Recover on screen:
```sql
DROP TABLE DEMO_PBI_PROD.PRE.DIM_PBI_CAPACITIES;
EXECUTE DCM PROJECT DCM_ADMIN.PROJECTS.CAPACITIES_PROD
    DEPLOY USING CONFIGURATION PROD FROM '@DCM_ADMIN.PROJECTS.DEMO_REPO/branches/main/capacities/';
```
> **Say:** "Empty table, two steps. With data: unload, drop, redeploy, reload. Planned maintenance."

---

## 11 — The loop, and why prod ships from git

State the takeaway plainly:
```
   edit on a branch → Deploy DEV        (fast, from the workspace)
        │
        └→ push branch → PR → review → merge main     (the approval gate)
                 │
                 └→ DEPLOY USING CONFIGURATION PROD  FROM '@…/main/capacities/'   (prod, reviewed)
```
> **Say:** "Three rules, the whole discipline. **One** — dev deploys from the workspace, so I move
> fast. **Two** — nothing reaches prod except through a merged PR; prod is always a deploy *from*
> `main`, never a laptop. **Three** — the same files build both; `env_suffix` is the only difference.
> Deploying prod from git is what keeps the nightly drift check honest — git and prod agree by
> construction, so any difference the check finds is real."

---

## 12 — Every morning, unattended (the real system)

Switch to the **real** project (`PBI_CAPACITIES`), which has run nightly.

```sql
SELECT * FROM DCM_ADMIN.AUDIT.V_DCM_MONITOR_HEALTH;

SELECT CHECK_ID, CHECKED_AT_UTC, VERDICT, ENTITIES_CHANGED, NOTIFIED
FROM   DCM_ADMIN.AUDIT.CTL_DCM_DRIFT_LOG
ORDER  BY CHECKED_AT_UTC DESC LIMIT 10;
```
> **Say:** "05:00 UTC, every day. Fetch main, plan prod against it, log the result, email if it isn't
> clean. `PLAN` only — never deploy."

Then the finding that forced the design:
```sql
SELECT PHASE, COUNT(*) AS N
FROM   TABLE(DCM_ADMIN.INFORMATION_SCHEMA.DCM_DEPLOYMENT_HISTORY(
             project_name => 'DCM_ADMIN.PROJECTS.PBI_CAPACITIES', result_limit => 100))
GROUP  BY 1;
```
> **Say:** "`DEPLOY` rows only. Snowflake records every deployment and *no plans at all* — the drift
> check is the one thing it forgets, which is awkward when drift detection is the whole point. So we
> keep our own log. It answers *when did this drift start* — the question that took seven months last
> time." Show the alert email.

---

## 13 — Beyond schema: gate the data too

> **Say:** "One more. This manages more than the shape of the tables — the same project can gate the
> data. You attach a quality check — no null IDs, unique IDs — beside the schema, and `snow dcm test`
> runs them. A real run: one passes, one fails, with the exact value; it exits non-zero, so it gates
> a pipeline. Bad data caught where it enters, not three dashboards later. Verified on Standard
> edition — no Enterprise needed. We haven't used it yet; it's the natural next step."

---

## 14 — Close honestly

> **Say:** "A proof of concept — 8 tables, no data, one slice. Grants, tasks and streams we haven't
> exercised. But it proves the thing that matters: the database can tell us every morning whether it
> still matches the repo, and name the column when it doesn't. We'd start with scheduled `PLAN` — it's
> read-only and safe. Deploy stays a human decision, and prod only ships through a merged PR."

Leave the findings artifact and the repo on screen for questions.

---

# IF SOMETHING BREAKS LIVE

| Symptom | Cause | Do |
|---|---|---|
| `manifest.yml not found in stage` | wrong `FROM` path | it's `…/branches/main/capacities/` — the project folder, not the repo root |
| `Conflicting definition … already defined` | `out/` got pushed | delete `out/` in the workspace, push; re-`FETCH` |
| Prod deploy drops the dev database | dev + prod share one project object (F16) | use `CAPACITIES_DEV` and `CAPACITIES_PROD` — separate objects |
| Workspace won't push, "secret … not authorized" | repo is public, or token lacks write | make `DCM_DEMO` private; PAT needs `repo` scope |
| Plan shows unexpected creates | rehearsal objects left | re-run Pre-flight A1, then §2 |
| Plan errors on a file/line | un-revertible drift from earlier | `DROP TABLE` the named table, redeploy |
| Everything is wrong | — | Pre-flight A1 (clean slate) → start at §2. Rebuild ≈ 1 min |

**Golden rule:** never debug live. Say *"good example of why we log every run"*, show the log, move on.

---

# QUESTIONS YOU'LL GET

| Question | Answer |
|---|---|
| "Where's the approval?" | The **PR** (§6) — nothing reaches `main`/prod without review + merge. In CI, `dcm plan` posts the changeset to the PR automatically. |
| "Why one project per environment?" | A DCM project holds one desired state; sharing it means a prod deploy drops dev (F16). Separate `_DEV`/`_PROD` projects, one per environment. |
| "Why not just git hooks / CI?" | You can — Snowflake publishes GitHub Actions (plan-on-PR, deploy-on-merge). CI only sees changes that go *through* CI; drift is the case that doesn't. |
| "Why not Terraform?" | Terraform for account objects + external state; DCM is native, stateless, in-database. Common practice is both. |
| "Does this replace Matillion?" | No. Matillion moves data; DCM manages the shape of the tables it lands in. |
| "Roll back?" | Revert the commit, deploy again. Git is the rollback mechanism. |
| "Two people deploy at once?" | Untested — a genuine gap. |
| "Cost?" | Warehouse time. A plan over 8 tables is ~3 seconds. |
| "Production today?" | GA, so no blocker — but `DEPLOY` drops columns, so scheduled `PLAN` (read-only) is the safe first step. |
