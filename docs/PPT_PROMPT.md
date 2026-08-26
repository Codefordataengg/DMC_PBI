# Slide-deck generation prompt

Paste everything below the line into your slide generator (Gamma, Copilot, Claude, etc.).

**Why it is this long:** given only topic headings, a generator invents plausible-sounding
specifics — wrong numbers, features that do not exist, findings we never made. Every figure
below is measured. Keep them exact.

---

## PROMPT STARTS HERE

Create an **18-slide presentation** for a technical audience of data engineers and platform
leads. Tone: precise, evidence-led, no marketing language. This reports a proof of concept
including what went wrong — not a product pitch.

### Visual theme — Modern Minimalist

| Role | Colour |
|---|---|
| Primary / headers / dark fills | Charcoal `#36454f` |
| Secondary / supporting text | Slate Gray `#708090` |
| Fills, table stripes, rules | Light Gray `#d3d3d3` |
| Background | White `#ffffff` |

- **Headers:** DejaVuSans Bold · **Body:** DejaVuSans
- Generous whitespace. Flat — no gradients, no drop shadows, no 3-D.
- **No accent colour.** Where severity must be shown, escalate tonally:
  light gray = benign · slate = attention · charcoal = serious.
- Diagrams: thin charcoal strokes on white, slate labels, light-gray fills.
- Maximum 6 bullets per slide, ≤ 12 words each. Prefer a diagram or table to a list.

---

### Slide 1 — Title
**Declarative Schema Management in Snowflake**
Subtitle: A proof of concept — what it does, what it costs, what it cannot do
Footer: Personal Snowflake account · 8 tables · 53 columns · August 2026

### Slide 2 — The problem
Title: **Our pipelines cannot see the database**

70 `CREATE TABLE IF NOT EXISTS` statements across 8 pipeline files.

Against a table that already exists, that statement **does nothing at all**. It does not
inspect the table. It cannot.

Show the sequence as three steps:
1. Table created by the pipeline
2. Someone adds a column by hand on a Tuesday
3. Pipeline re-runs the same DDL → **"already exists, statement succeeded"** → the column is
   still there, data untouched

Closing line: *It did nothing, said so honestly, and doing nothing counted as success.*

Note for the deck: `IF NOT EXISTS` destroys nothing — no data loss, no recreation. That is
precisely why the drift stays invisible: nothing breaks, so there is nothing to notice.

### Slide 3 — Two guarantees
Title: **Only one of these was ever real**

Caption above the table: *"repo" here = the Matillion pipeline repo holding the 70 DDL statements.*

| Statement | Before | With DCM |
|---|---|---|
| "The pipeline repo can build the database" | ✅ | ✅ |
| "The database still matches the pipeline repo" | ❌ | ✅ |

Note beneath — **state this precisely, the two failures are not the same mechanism**: a
dashboard dimension in this estate sat frozen for seven months. That was a *different* defect —
a trailing comma in a transformation that alert-then-succeed hid — but the same shape:
something that looked like a check and never checked anything.

### Slide 4 — What DCM Projects is
Title: **Declare the state. Let Snowflake work out the difference.**

- Native Snowflake feature, **currently in preview**
- You declare objects in `.sql` files; Snowflake computes the changeset
- `PLAN` — dry run, changes nothing · `DEPLOY` — applies it
- No external state file, unlike Terraform
- `TABLE`, `SCHEMA`, `DATABASE` are GA within DCM

### Slide 5 — Infrastructure as code, concretely
Title: **The DDL stops living inside the ETL**

Two columns.

**Before** — DDL embedded in orchestration: 70 statements across 8 pipeline files, executed as
a side effect of a data load, no review, no diff, drift invisible.

**After** — DDL in git: reviewed like application code, plan shows the impact before it lands,
one command rebuilds an environment, drift becomes detectable.

Closing line: *The database becomes a build output, not a place things accumulate.*

### Slide 6 — DEFINE, not CREATE
Title: **A description, not an instruction**

```sql
DEFINE TABLE DEMO_PBI.PRE.DIM_PBI_CAPACITIES (
    ID                VARCHAR(36)   NOT NULL,
    NAME              VARCHAR(500),
    SKU               VARCHAR(50),
    IS_CURRENT_FLAG   NUMBER(1,0)   DEFAULT 1
);
```

- Definition files accept only `DEFINE`, `GRANT`, `ATTACH`
- Names must be fully qualified: `database.schema.object`
- Executes underneath as `CREATE OR ALTER`
- **Remove a `DEFINE` and the next deploy drops the object**

### Slide 7 — Folder structure
Title: **The layout is fixed, not a convention**

```
manifest.yml              which account, which project, what varies
sources/
  definitions/            EVERY object definition. Snowflake looks here and nowhere else
  macros/                 optional Jinja macros
out/                      plan and deploy artifacts, generated
```

- `sources/definitions/` is **required** — files elsewhere are simply not read
- Filenames carry no meaning; grouping is for humans
- `out/` is generated output — git-ignored

### Slide 8 — The manifest
Title: **Where, and what varies**

```yaml
targets:
  DCM_DEV:
    account_identifier: ORG-ACCOUNT
    project_name: DCM_ADMIN.PROJECTS.PBI_CAPACITIES
    templating_config: DEV
templating:
  configurations:
    DEV:   { env_suffix: "" }
    PROD:  { env_suffix: "_PROD" }
```

- `targets` = **where** · `templating` = **what differs between environments**
- The same reviewed files build dev and prod
- Promotion is pointing at a different target — **you copy nothing**

### Slide 9 — Architecture
Title: **How it fits together**

Diagram, left to right:
`GitHub` → `GIT REPOSITORY (account-level clone)` → `DCM PROJECT` → `PLAN / DEPLOY` → `Database`

Below, branching from the project: `Nightly task 05:00 UTC` → `Drift log` → `Email alert`

Label two edges explicitly: **`PLAN` is automated. `DEPLOY` is not.**

### Slide 10 — Three copies of the same files
Title: **All three can be stale, independently**

| | Lives in | Updated by | Read by |
|---|---|---|---|
| GitHub repo | github.com | your push | everyone |
| `GIT REPOSITORY` | a Snowflake schema | `ALTER … FETCH` | plan, deploy, the task |
| Workspace | your personal database | Pull button | you, in the editor |

- A `GIT REPOSITORY` is a **snapshot, not a live link**
- A workspace is **invisible to automation** — a scheduled task cannot read one
- GitHub is authoritative. The other two are caches.

### Slide 11 — How a change travels
Title: **One direction only**

```
edit → commit → GitHub → FETCH → PLAN → review → DEPLOY → database
                   ▲                                         │
                   └──────────── no path back ───────────────┘
```

Closing line: *A hand-made `ALTER` never flows back into the repo. That asymmetry is why drift
detection has to exist.*

### Slide 12 — Three questions, three diffs
Title: **Git answers two of these. Only one tool answers the third.**

| Question | Answered by |
|---|---|
| What changed in the definition? | `git diff` |
| What will change in the database? | `DCM PLAN` |
| **What changed without going through either?** | **drift check** |

Note: The third is the one we have never been able to see.

### Slide 13 — Drift detection: three verdicts
Title: **Two states would be wrong most of the time**

Three tonal blocks, escalating light gray → slate → charcoal:

- **CLEAN** — changeset empty. Database matches the repo. Logged, no alert.
- **DRIFT** — changeset non-empty. Revertible. Alert names the column and datatype.
- **ERROR** — the plan failed to compile. Drift exists, **cannot** be auto-reverted, and is
  hiding whatever sits behind it.

Bottom bar: **45 of our 53 columns are not the last column in their table** — so `ERROR` is
the common case, not the edge case.

### Slide 14 — What drift detection actually returns
Title: **It names the column, not just the table**

```
ALTER TABLE "DEVELOP"."PRE"."DIM_PBI_CAPACITIES"
  columns: removed "HAND_ADDED_BY_A_HUMAN"   VARCHAR(100), nullable
```

- Column name, datatype, and which direction the fix runs
- The difference between an alert worth waking for and one people mute
- Views report even more — the **before/after `SELECT`**

### Slide 15 — What Snowflake does not record
Title: **The drift check is the one thing it forgets**

Measured after a full test run — 7+ plans, 4 deploys:

```
PHASE    N
DEPLOY   4      ← no PLAN rows. none.
```

- Deployments: full immutable artifacts, 12-month retention
- Plans: **not recorded at all**, and no `ACCOUNT_USAGE` view exists
- So we keep our own log — it answers *"when did this drift start?"*

### Slide 16 — What we found by breaking it
Title: **Twelve findings. Four came from deliberate sabotage.**

| | Finding |
|---|---|
| F5 | Drift is detected and reported **at column level** — the verdict |
| F6 | DCM records `DEPLOY`, never `PLAN` — so an audit table is mandatory |
| F7 | Dropping a non-last column is **un-revertible** |
| F9 | Our own monitor sat suspended while its health view reported `OK` |
| F11 | The chain has now run unattended, two consecutive nights, ~30s per run |

Closing line: *Every failure we found was something reporting success without checking what it
claimed to check.*

### Slide 17 — What we will demo
Title: **Live, end to end, about 20 minutes**

1. `CREATE TABLE IF NOT EXISTS` succeeding against a table it never looked at
2. Build a project from nothing — scaffold, definitions, plan, deploy
3. Push to git — the repo fills up
4. Snowflake pulls its own copy; plan agrees from both directions
5. Add a table, push, fetch, deploy — a change travelling through git
6. **Tamper with the database by hand — GitHub shows nothing, the drift check names it**
7. The un-revertible case, and why it matters

### Slide 18 — Honest limits and next steps
Title: **What this does not yet prove**

**Limits**
- One slice: 8 tables, 53 columns, **no data**. Untested at 64 tables
- DCM Projects is a **preview** feature
- Grants, tasks and streams unproven
- `ERROR` recovery rehearsed only on empty tables

**Next**
- Widen to a second slice
- Rehearse recovery on a table holding data
- Scheduled `PLAN` first — it is read-only. `DEPLOY` stays a human decision.

## PROMPT ENDS HERE
