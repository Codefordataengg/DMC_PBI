# DCM POC — findings

Dated results from the POC. Each entry records what was checked, against what, and when.

---

## F1 — The repo and the database agree for the capacities slice (2026-08-22)

**Checked:** all 8 objects in the capacities slice, 53 columns, comparing precedence rank 1
(`GET_DDL` against `DEVELOP`, captured `target-state/GET_DDL_2026-08-22.txt`) against rank 2
(the `CREATE TABLE IF NOT EXISTS` block in `../PowerBI Governance/01_EXTRACT_PBI_CAPACITIES.orch.yaml`,
lines 163–238).

**Result: zero drift.** Every column matches on name, order, type, nullability and default.

The only textual differences are `GET_DDL` expanding implicit defaults — `NUMBER` → `NUMBER(38,0)`,
`TIMESTAMP_NTZ` → `TIMESTAMP_NTZ(9)`, `TIMESTAMP_TZ` → `TIMESTAMP_TZ(9)`, `NUMBER(1)` → `NUMBER(1,0)` —
and the `_RAW` table's `"JSON"` being quoted in the pipeline and unquoted in `GET_DDL`. A quoted
uppercase identifier and an unquoted one resolve to the same name. These are not differences.

**This closes an open concern.** `README.md` and `CLAUDE.md` both flagged that the `LND` DDL was
hand-written and had **never been diffed against the live database**. For the three capacities `LND`
tables, it now has been, and it is correct.

**What it does not close.** This is 8 of 70 `CREATE TABLE IF NOT EXISTS` statements, checked by hand,
at one point in time, by reading two files side by side. Nothing re-checks it tomorrow. The absence of
drift today is not evidence that drift cannot occur — it is one clean sample, and the clean sample is
exactly what makes the slice a good POC subject: **any drift the POC reports from here is drift the POC
introduced deliberately**, not pre-existing divergence being discovered late.

**Bearing on the POC.** Step 1 of the acceptance test should now predict **8 creates and 0 alters**
against an empty account. If `PLAN` reports an `ALTER` on a first deploy into a blank database,
something in the translation from `GET_DDL` to `DEFINE` is wrong and must be found before step 3.

---

## F2 — `PLAN DELTA` cannot detect out-of-band drift (2026-08-22, from documentation)

Not yet confirmed against the account. Recorded here because it determines whether the acceptance
test is valid.

Snowflake's documentation on `PLAN DELTA`: *"Because it skips unchanged definitions, it doesn't detect
changes that happened outside of DCM Projects on your account since the last deployment."*

Step 4 of the acceptance test — add a column by hand, confirm `PLAN` reports it — **is** an
out-of-band change. Run with `PLAN DELTA` it would report nothing, and the POC would return a false
negative on its central question. **Step 4 must use full `PLAN`.**

---

## F3 — Reverting drift means `DROP COLUMN`, and data in it is lost (2026-08-22, from documentation)

Not a POC blocker — the POC account holds no data. Recorded because it governs whether this
approach can ever point at the real `DEVELOP`.

- `DEFINE TABLE` executes as `CREATE OR ALTER TABLE`. Snowflake: *"if a `CREATE OR ALTER TABLE`
  statement results in a dropped column, any data contained in the column is lost (but can still be
  recovered with Time Travel)."* Step 5 of the acceptance test is therefore a destructive operation
  by design.
- Snowflake: *"If you remove a `DEFINE` statement, Snowflake drops the corresponding object the next
  time you deploy the project."* Against append-only landing tables and the tables the inventory marks
  as holding irreplaceable data, deleting a line from a source file is a data-loss event.

**Consequence if this graduates past POC:** `DEPLOY` must be gated on a reviewed `PLAN`, never run
unattended. That is the same shape as the rule the governance chain already follows — guards fail the
run rather than alert-then-succeed.

---

## F4 — One un-revertible drift blocks the whole PLAN (2026-08-23, verified)

**Found by accident**, while running step 4. It is the most operationally significant
result of the POC so far.

Step 4b widened `PRE.DIM_PBI_CAPACITIES.SKU` from `VARCHAR(50)` to `VARCHAR(100)` by hand.
Reverting that is a *narrowing*, which Snowflake does not support. `PLAN` did not report
the drift and mark it un-revertible. **It aborted:**

```
040050 (22000): Error during DCM PLAN ... Execution failed after completing
[9/12] statement executions in file sources/definitions/30_pre_capacities.sql
on line 8: SQL compilation error: cannot change column SKU from type
VARCHAR(100) to VARCHAR(50) because reducing the byte-length of a varchar is
not supported.
```

**Two things this tells us.**

1. **`PLAN` is not a pure read.** It works by executing the `CREATE OR ALTER` statements in
   a validating mode, and stops at the first one that cannot compile — here, 9 statements
   into a 12-statement file. It is not computing a diff from the catalogue.

2. **A single un-revertible drift hides every other drift.** Two other hand-made changes
   (`HAND_ADDED_BY_A_HUMAN` added, `INSERT_DATE` dropped) were present and went unreported,
   because the run died before finishing. The changeset is all-or-nothing.

**Why this matters for the nightly drift check.** The intended design was: run `PLAN` on a
schedule, alert when the changeset is non-empty. This finding says the alert must also treat
**failure** as a signal, and a distinct one:

| Plan outcome | Meaning |
|---|---|
| empty changeset | no drift |
| non-empty changeset | drift, revertible |
| **error** | **drift exists AND cannot be auto-reverted — and other drift may be hidden behind it** |

A monitor that only checks "did the changeset have rows" would read the third case as a
broken job rather than the most serious of the three. That is the same failure shape as
alert-then-succeed: a real signal arriving in a channel nobody reads as a signal.

**Consequence for widening the POC:** narrowing a column is unsupported, so any hand-widened
column anywhere in a managed schema puts that whole definition file into a permanently
failing state until someone rebuilds the table. Recovery is a manual `DROP TABLE` and
redeploy — which for a table holding data means unloading it first.

**Test design note:** 4b was a badly chosen probe — it tested Snowflake's `ALTER` limits
rather than DCM's detection. It has been removed from `90_INDUCE_DRIFT.sql`. 4a (added
column) and 4c (dropped column) are both revertible and remain the real test.

---

## F5 — THE VERDICT: DCM detects hand-made drift, at column level (2026-08-23, verified)

**The POC succeeds.** Full run on audit-equivalent aliases `step2_initial`, `recover_after_4b`,
`step5_revert` in account `LV16268`.

| Step | Expected | Actual | |
|---|---|---|---|
| 1 | *n* creates on an empty account | 13 created, 1 altered | ✅ |
| 2 | objects exist | 8 tables, **53 columns** | ✅ |
| 3 | zero changes | `No changes detected.` | ✅ |
| **4** | **PLAN names the hand-made drift** | **both columns named, with types** | ✅ |
| 5 | drift reverted | back to 53 columns, plan clean | ✅ |

**Step 4 in full.** Two changes were made by hand, outside DCM, in a worksheet session:
a column added to `PRE.DIM_PBI_CAPACITIES`, a column dropped from
`STG.BRIDGE_PBI_CAPACITY_ADMIN`. A full `PLAN` returned:

```json
ALTER TABLE "DEVELOP"."PRE"."DIM_PBI_CAPACITIES"
  columns: removed "HAND_ADDED_BY_A_HUMAN"  datatype VARCHAR(100), nullable true
ALTER TABLE "DEVELOP"."STG"."BRIDGE_PBI_CAPACITY_ADMIN"
  columns: added   "INSERT_DATE"            datatype TIMESTAMP_NTZ(9), nullable true
```

**The granularity is the important part.** It does not report "these two tables differ" — it
names the column, the datatype and the nullability, and says which direction the fix goes.
A drift alert built on this can tell someone *what* changed, not merely that something did.
That was the open question after F2 and it is now answered.

**So the second guarantee is now purchasable:**

| | Before | With DCM |
|---|---|---|
| "This repo can build the database" | ✅ | ✅ |
| "The database matches this repo" | ❌ | ✅ |

**What this does not prove.** One slice, 8 tables, no data, one account (built during preview; DCM went GA 2026-08-07).
It does not prove the same holds for views, tasks, streams or grants; it does not prove
behaviour at full-estate scale (52 tables); and F4 shows the reporting is all-or-nothing, so a single
un-revertible drift still blinds the check. Widening the scope is the next question,
not a formality.

---

## F6 — DCM records DEPLOY but never PLAN. Drift checks leave no trace. (2026-08-23, verified)

**This is the finding that decides the architecture.**

Over this POC we ran **7+ PLAN operations** — including the F4 failure — and **4 DEPLOY
operations. Queried afterwards:**

```sql
SELECT PHASE, COUNT(*) FROM TABLE(DCM_ADMIN.INFORMATION_SCHEMA.DCM_DEPLOYMENT_HISTORY(
    project_name => 'DCM_ADMIN.PROJECTS.PBI_CAPACITIES', result_limit => 100)) GROUP BY 1;

PHASE   N
DEPLOY  4
```

**No PLAN rows. None.** Snowflake persists an immutable artifact snapshot per *deployment*
(`plan_result.json` + `deploy_result.json`), and the docs correctly call that "the canonical
audit trail" — but only for deployments. A `PLAN` that is not followed by a `DEPLOY` writes
nothing anywhere server-side. `--save-output` writes to the **local** filesystem of whoever
ran it, which on a scheduled task is nowhere.

**So the drift check, which is the entire value proposition, is the one operation Snowflake
does not remember.** A nightly PLAN would detect the hand-added column, print it to a task
log, and lose it.

Two further gaps in the native trail:

| | |
|---|---|
| `DCM_DEPLOYMENT_HISTORY` retention | **12 months**, and there is **no `ACCOUNT_USAGE` equivalent** |
| Coverage | deployments only — no plans, therefore no drift record |

**Consequence — the audit table is not optional.** Without one there is no answer to "when
did this drift start?", which is the question the dashboard-freeze incident turned on. The
governance chain already solved the same problem the same way:
`PRE.CTL_PBI_GOVERNANCE_HEARTBEAT` exists because Matillion alerts on failure and nothing
alerts on never-started.

Design in `docs/DCM_ARCHITECTURE.md`; implementation in `10_AUDIT_AND_MONITOR.sql`.

---

## F7 — Dropping a column that is not LAST is un-revertible (2026-08-23, verified)

**This makes `ERROR` the common case, not the edge case.** It substantially revises F4.

Testing the drift monitor, `REGION` was dropped from `STG.DIM_PBI_CAPACITIES` — position
**5 of 8**. `PLAN` did not report drift. It failed:

```
Unsupported feature 'CREATE OR ALTER TABLE column add before end of column list'.
```

`CREATE OR ALTER` can only **append** columns. Restoring a column to the middle of the list
would be a reorder, which is on Snowflake's unsupported list. So:

| Hand-made change | Revertible? | Verdict |
|---|---|---|
| Add a column | yes — it lands at the end | `DRIFT` |
| Drop the **last** column | yes — re-append restores it | `DRIFT` |
| **Drop any other column** | **no** | **`ERROR`** |
| Widen a VARCHAR (F4) | no — narrowing unsupported | `ERROR` |
| Rename a column | no — reads as drop + add | `ERROR` unless it was last |

**Why this reframes the design.** F5's step-4 pass was luckier than it looked: the dropped
column there (`INSERT_DATE` in `STG.BRIDGE_PBI_CAPACITY_ADMIN`) happened to be the last one.
In the real 53-column slice, **45 of 53 columns are not last**. Most accidental column drops
will therefore produce `ERROR`, not `DRIFT`.

A two-state monitor — "changeset empty or not" — would misread the **majority** of real drop
incidents as a broken job. The three-verdict design is not defensive over-engineering; it is
the common path.

**And the F4 blast radius applies here too:** the failing definition file aborts mid-way
(here, 7 of 12 statements), so every object declared after it in that file goes unchecked.
One dropped column in `STG` can mask unrelated drift in `PRE`.

**Operational consequence.** `ERROR` means a human must intervene: unload the table, drop it,
redeploy, reload. There is no automated path back. For a table holding irreplaceable data
that is a planned maintenance task, not a 3am fix — which is another reason `DEPLOY` must
never be scheduled.

---

## F8 — Snowflake `IDENTITY` is not monotonic across sessions (2026-08-23, verified)

**An implementation finding, not a DCM one — but it silently disabled the alert, which is
the exact failure shape this project exists to catch.**

`SP_DCM_DRIFT_CHECK_AND_ALERT` found "the row just written" with
`ORDER BY CHECK_ID DESC LIMIT 1`. That is wrong. Observed in the log:

```
CHECK_ID  VERDICT  CHECKED_AT_UTC
       3  DRIFT    2026-08-22 15:07:52   ← newest row
     105  CLEAN    2026-08-22 14:24:38   ← older row, higher id
```

Snowflake `IDENTITY` / `AUTOINCREMENT` allocates **ranges per session**. A row inserted later
can receive a lower id than one inserted earlier. Ordering by it to find the most recent row
returns whatever row holds the highest number, which is not the same question.

**What it did.** The wrapper read row 105, saw `CLEAN`, took the no-alert branch, and returned
`DRIFT | entities=1 | no alert sent`. Drift was correctly detected, correctly logged — and
nobody was told. The return string reported the suppression as though it were a normal outcome.

**The fix.** `SEQ_DCM_CHECK_ID`, claimed with `NEXTVAL` *before* the insert. The check
procedure returns the id it used; the wrapper parses field 1 rather than re-querying. Nothing
guesses which row it just wrote.

**The general rule for this repo:** never use an `IDENTITY` column to establish recency, in
any table. If code needs to know which row it just inserted, it must decide the key beforehand.

**How it was caught:** only because the git-sourced check was re-tested end to end after being
repointed, rather than assumed to behave like the stage-sourced one it was copied from. A test
that only asserted the verdict — and not that the alert *fired* — would have passed.

---

## F9 — The monitor never ran, and the health view reported OK (2026-08-23, verified)

**Third instance of the same disease in this build, and this time in the component whose
entire job was to catch it.**

The task was resumed 2026-08-22 at 15:10 UTC. It was scheduled for 05:00 UTC daily. At
13:02 UTC on 2026-08-23 — eight hours after it should have fired:

```
TASK_HISTORY(TASK_NAME=>'TASK_DCM_DRIFT_CHECK')   →  No data

SHOW TASKS:
  STATE       suspended
  DEFINITION  ... '@DCM_ADMIN.PROJECTS.PBI_CAPACITIES_SRC' ...   ← stage, dropped 08-22

V_DCM_MONITOR_HEALTH:
  HOURS_SINCE_LAST_CHECK  20        HEALTH  OK        ← wrong
```

Not one failure but three, stacked:

**1. Two files owned the same object.** `11_ALERTING.sql` §4 carried its own
`CREATE OR REPLACE TASK`, as did `12_GIT_INTEGRATION.sql` §6. Re-running the former to add
an `ACKNOWLEDGED_AT` column silently repointed the task back at the stage — which had by then
been dropped — so it would have failed even if it had run.

**2. `CREATE OR REPLACE TASK` always creates the task SUSPENDED**, regardless of its previous
state. Replacing a running task stops it, and says nothing.

**3. The health view could not tell "ran and found nothing" from "did not run".** It measured
recency of the last log row and nothing else, with a 30-hour staleness window — so a fully
missed daily run still read `OK` for six more hours. The one failure it existed to catch was
the one it was blind to.

**Fixes.**

| | |
|---|---|
| Single ownership | The task is defined in `12_GIT_INTEGRATION.sql` §6 and **nowhere else**. `11_ALERTING.sql` §4 now explains why it is absent. |
| Task state is now a health input | `TASK_HISTORY` shows a future `SCHEDULED` row only while a task is resumed. `NEXT_RUN_UTC IS NULL` → **`TASK_NOT_SCHEDULED`**, ranked above every other state, because a suspended monitor makes the rest of the row meaningless. |
| Window tightened | 30h → **26h**. A daily task may run late; it may not miss a whole day. |
| Verified both ways | The view returned `TASK_NOT_SCHEDULED` while suspended, and `OK` with `NEXT_RUN_UTC = 2026-08-24 05:00 UTC` once repointed and resumed. |

### F9 addendum — the fix itself was incomplete (2026-08-25)

The remediation above claimed the task was defined in `12_GIT_INTEGRATION.SQL` §6 "and
**nowhere else**". That was false when written. The duplicate was removed from
`11_ALERTING.sql` and **missed in `10_AUDIT_AND_MONITOR.sql`**, which still carried a
`CREATE OR REPLACE TASK` pointing at the dropped stage and the non-alerting procedure.

Re-running that file would have suspended the live task, repointed it at a stage that no
longer exists, and silently removed alerting — the same failure, from a different file.

Found by grepping which files define the same object, not by anything failing. **The single
ownership rule was stated but never verified.** A rule nobody checks is a comment.

```
grep -ln "CREATE OR REPLACE TASK DCM_ADMIN.AUDIT.TASK_DCM_DRIFT_CHECK" *.sql
```

That one-liner belongs in any future audit of this repo.

**The pattern, stated plainly.** Three times now in this build the same shape has appeared:
`IF NOT EXISTS` that cannot detect drift; alert-then-succeed hiding a seven-month dashboard
freeze; `ORDER BY CHECK_ID` suppressing an alert while reporting success (F8); and now a health
view reporting `OK` over a monitor that was switched off. **Every one was a component that
returned a reassuring value without having checked the thing it claimed to check.**

The general defence is not more monitors. It is that a check must fail when its own
preconditions are unmet, rather than reporting on data it never gathered.

---

## F10 — Views work, report better, and share the reorder limitation (2026-08-24, verified)

Tested because the demo plan proposed a `VIEW` as its incremental object, and views had
**never been exercised** — the POC covered only databases, schemas and tables.

**They work.** `DEFINE VIEW ... AS SELECT ...` parses, plans and deploys.

**Drift reporting on a view is richer than on a table.** A view redefined by hand outside DCM
produced a changeset naming the added column *and* diffing the SQL itself:

```json
"kind": "changed", "attribute_name": "select_query",
"value":      "SELECT ID, LABEL FROM ... WHERE LABEL IS NOT NULL",
"prev_value": "SELECT ID, LABEL, 'TAMPERED' AS SNUCK_IN FROM ..."
```

Before-and-after SQL, not just a column list. For a view, that is the whole object.

**But the F7 constraint applies here too.** Removing a *leading* column from a view — so the
revert has to restore column order — fails exactly as it does for tables:

```
Cannot reorder VIEW columns in ALTER. Saw ID before LABEL.
```

So the earlier instinct that views are simply "safer than tables" is **wrong**. The accurate
comparison:

| | Table | View |
|---|---|---|
| Drift detected at column grain | yes | yes |
| Full definition diff reported | no | **yes** — the `SELECT` itself |
| Reverting a trailing change | yes | yes |
| Reverting a non-trailing removal | **no** — `ERROR` | **no** — `ERROR` |
| Data destroyed by revert | **yes** — `DROP COLUMN` | no — views hold none |

Views are safer in exactly one respect: reverting one destroys no data. They are *not* exempt
from the reorder rule, and a view whose leading column is removed by hand needs the same
manual `DROP` and redeploy a table does.

**Demo consequence:** a view is a good object to author live, and a good object to drift — but
drift it by **adding** a column, not removing a leading one, unless the `ERROR` path is the
point being made.

---

## F11 — The chain runs unattended. Two consecutive nights, no intervention. (2026-08-25, verified)

The last unproven thing about the POC as built. It has now run on its own.

```
TASK_HISTORY(TASK_NAME => 'TASK_DCM_DRIFT_CHECK')

STATE       SCHEDULED_TIME              COMPLETED_TIME              ERROR
SCHEDULED   2026-08-25 05:00 UTC        —                           —
SUCCEEDED   2026-08-25 05:00 UTC        05:00:31  (31s)             none
SUCCEEDED   2026-08-24 05:00 UTC        05:00:30  (30s)             none
```

Both runs fetched `main`, planned against the live database, wrote a row, and found `CLEAN`.
`V_DCM_MONITOR_HEALTH` reads `OK` with `NEXT_RUN_UTC` populated. **~30 seconds per run.**

**What this closes.** F9 was the same task sitting suspended while the health view reported
`OK`. The fix is now demonstrated over two consecutive nights rather than asserted from a
single manual invocation.

**What it does not close.** Every run so far returned `CLEAN`, so the *unattended alerting*
path — a scheduled run finding real drift and successfully emailing — has still only been
proven by manual call, never by the task itself. The remaining rehearsal is to leave a
deliberate drift in place overnight and confirm the email arrives without anyone present.

---

## F12 — `CREATE TABLE IF NOT EXISTS` is honest about doing nothing (2026-08-26, verified)

**A correction to how this project has been describing its own founding problem**, caught when
the slide was questioned rather than by anything failing.

The deck and run sheet both claimed the statement returns *"Table successfully created"* against
an existing table, and called that "a lie by omission". Verified in Snowflake:

```sql
CREATE TABLE IF NOT EXISTS SCRATCH_MSG.S.CUSTOMER (ID VARCHAR(36), NAME VARCHAR(200));

  status
  CUSTOMER already exists, statement succeeded.
```

Rows before: 2. Rows after: 2. Columns after: `ID`, `NAME`, **`SALARY`** — the hand-added one,
untouched.

**So the framing was wrong in a way that mattered.** Snowflake is not deceptive. It states
plainly that the object already exists and that it did nothing. Nothing is dropped, nothing is
recreated, no data is at risk.

**The accurate problem is narrower and sharper:**

- The statement is a **create-if-missing safety net**, so a pipeline works against an empty
  environment. First run creates; every run after is a no-op. That is correct behaviour.
- The defect is that **"did nothing" is indistinguishable from "verified nothing"** to anything
  downstream. The pipeline asks *did the statement succeed?* and never *does this table match
  what I declared?*
- **It stays invisible precisely because it is harmless.** No data loss, no failure, nothing to
  notice. A destructive bug would have been found in a day.

Corrected in `docs/build_deck.py`, `DEMO_RUNSHEET.md` §1 and `docs/PPT_PROMPT.md`.

**The lesson is the same one as F8 and F9:** a claim repeated across three documents for a week
was never tested, because it was about something everyone already "knew". The two-minute check
was available the whole time.

---

## F13 — The "64 statements" figure was stale, and slide 3 conflated two failures (2026-08-26, verified)

**A full audit of every factual claim in the deck**, prompted by a challenge to slide 3.

### The count was wrong

Every document quoted **64 `CREATE TABLE IF NOT EXISTS` across 9 pipeline files**. Recounted:

```
grep -roh "CREATE TABLE IF NOT EXISTS" PowerBI Governance/ | wc -l     →  71
grep -roh ... --include="*.orch.yaml"                                  →  70  across  8 files
```

| | |
|---|---|
| **70** | in `*.orch.yaml` — the orchestration pipelines |
| **+1** | in `97_DEPLOY_MONITOR_TASK.sql`, a deploy script rather than a pipeline |
| **71** | total, across 9 files |

The figure has been quoted as 64 since the project began. It grew when DDL for the nine `PRE`
tables was added on 2026-08-21 — a change we made ourselves and never re-counted.
**Corrected to 70 across 8 pipeline files** in `CLAUDE.md`, the README, the architecture doc,
the run sheet, the PPT prompt and the deck.

### Slide 3 conflated two different defects

The slide used the seven-month dashboard freeze as evidence for the `IF NOT EXISTS` problem.
They are not the same mechanism:

| | Cause |
|---|---|
| **Dashboard freeze** | a **trailing comma** in `02F_STG_DIM_PBI_DASHBOARDS`, a hard syntax error, hidden by **alert-then-succeed** |
| **`IF NOT EXISTS`** | a statement that correctly does nothing, where *did nothing* is indistinguishable from *verified nothing* |

Same *family* — something that looked like a check and never checked — but different
mechanisms. Presenting one as evidence for the other is an argument a knowledgeable audience
can dismantle, on a point that was never necessary. The slide now states the distinction
explicitly.

### "This repo" was ambiguous

The word had been used in this project for both the **Matillion pipeline repo** (which holds
the 70 statements) and the **DCM repo** (`DMC_PBI`). Slide 3 now names which one it means.

**The pattern, again.** Three claims — the `IF NOT EXISTS` message (F12), the statement count,
and the dashboard attribution — survived across four documents because each was about something
already believed. None had been checked. All three were a two-minute verification away.

---

## F14 — DCM went GA on 2026-08-07; and we omitted expectations (2026-08-26, verified from docs)

**A web validation of every Snowflake-behaviour claim in the deck**, prompted before presenting.
Two things were stale or missing.

### 1. No longer preview

Confirmed from two independent Snowflake sources: **DCM Projects reached General Availability
on 2026-08-07.** The entire POC (Mar–Aug 2026) was built during preview, and every artifact
still said "preview feature." That was correct when written and stale by the time of the demo —
the same class of drift this project is about, one level up.

Corrected in the deck (both formats), architecture doc, README, run sheet, PPT prompt and this
file. GA *removes* a stated limitation, so the honest-limits slide is now stronger, not weaker.

Per-object status at GA (from the supported-entities page):

| GA | Preview |
|---|---|
| table · view · task · warehouse · role · schema · database · sequence · stage · tag · network rule · function · procedure · alert | stream · pipe · masking / row-access policy · semantic view · share · inherited grants · ATTACH TAG |

So of our "untested by us" list: **tasks and grants are GA; streams are still preview.** The
honest limit is that *we* never exercised them — not that DCM can't.

### 2. The concept we omitted — expectations

DCM manages more than schema shape. **Expectations** attach data-quality checks (data metric
functions) to tables, views and dynamic tables, declared in the same project and run with
`snow dcm test`. Snowflake positions them as quality gates across bronze/silver/gold layers.

For a Power BI governance estate this is arguably the most valuable unexplored surface: the same
declarative project that guarantees the schema *matches* could also guarantee the data *passes*.
The POC never touched it. Worth a slide, and worth a follow-up spike.

### Smaller capabilities we don't mention (GA or new since preview)

- `snow dcm preview` — queries the SELECT of managed views / dynamic tables without running tasks
- On deploy, a **running task is auto-suspended, altered, and resumed** — no manual dance
- GA/July-preview additions: Python & Java functions/procedures, tag attachment, inherited grants, network rules
- `PLAN DELTA` is now a documented, supported variant — still **banned here** (F2): it cannot see out-of-band drift

### Still worth re-verifying on the account post-GA

F6 (DCM records DEPLOY, never PLAN) and the 12-month / no-`ACCOUNT_USAGE` retention were both
measured or read during preview. Nothing suggests GA changed them, but a 5-minute re-check on
the account would confirm the audit-table rationale still holds.

---

## F15 — Expectations work end-to-end, on Standard edition, and F6 still holds at GA (2026-08-26, verified)

**The follow-up spike from F14, run against the account** (now Snowflake 10.30.101, DCM GA).

### Data-quality expectations are real, and not Enterprise-gated

Built a throwaway DCM project with `ATTACH DATA METRIC FUNCTION … EXPECTATION` on a table, deployed
it, and ran `snow dcm test`. It works — and the account is **Standard edition**, so DMF-based
expectations in DCM are *not* gated to Enterprise the way standalone data-quality monitoring often is.

Verified deploy, then a real failing run:

```
$ snow dcm test EXP_TEST
  ✓ PASS   EXP_DB.PRE.DIM_CAP (NO_NULL_IDS)
  ✗ FAIL   EXP_DB.PRE.DIM_CAP (UNIQUE_IDS)
     └─ Expected: VALUE = 0, Got: 1 (Metric: DUPLICATE_COUNT)
  1 passed, 1 failed out of 2 total.
```

The failure output names the expectation, the metric, the expected condition and the actual value —
richer than the mock-up that was on the deck, which is now replaced with this real output. **And
`snow dcm test` exits non-zero on failure**, so it gates a CI pipeline directly.

**Two syntax facts learned the hard way:**
- Column DMFs attach as `… ON (col) EXPECTATION name ( VALUE = 0 )`. Verified: `NULL_COUNT`,
  `DUPLICATE_COUNT`.
- A **table-level DMF** (`ROW_COUNT`, no column) does **not** accept the same `EXPECTATION` clause
  form — `ATTACH … ROW_COUNT … EXPECTATION fact_not_empty (VALUE > 0)` fails to compile
  (`unexpected 'EXPECTATION'`). The deck's illustrative `fact_not_empty` line was dropped; the two
  shown examples are the column-based ones that actually deploy. Getting the table-level form right
  is a small follow-up, not a blocker.

### F6 re-verified at GA — still true

Ran 2 plans + 1 deploy against the test project on 10.30.101:

```
PHASE   N
DEPLOY  1        ← no PLAN rows
```

And `SNOWFLAKE.ACCOUNT_USAGE` still has **no DCM view** (`ILIKE '%DCM%'` → nothing). So GA did not
change F6: **DCM records DEPLOY, never PLAN, and there is no ACCOUNT_USAGE equivalent.** The audit
table (`CTL_DCM_DRIFT_LOG`) remains mandatory, exactly as designed.

**Demo consequence:** the expectations slides are now backed by a real run, not a description. If
asked "does this actually work / do we need Enterprise?", the answer is yes / no respectively, shown
live in ~30 seconds with `ADD DATA METRIC FUNCTION … EXPECTATION` + `snow dcm test`.
