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

**What it does not close.** This is 8 of 64 `CREATE TABLE IF NOT EXISTS` statements, checked by hand,
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

**What this does not prove.** One slice, 8 tables, no data, one account, a preview feature.
It does not prove the same holds for views, tasks, streams or grants; it does not prove
behaviour at 64 tables; and F4 shows the reporting is all-or-nothing, so a single
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
