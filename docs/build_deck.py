from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE

CHARCOAL = RGBColor(0x36, 0x45, 0x4F)
SLATE    = RGBColor(0x70, 0x80, 0x90)
LIGHT    = RGBColor(0xD3, 0xD3, 0xD3)
WHITE    = RGBColor(0xFF, 0xFF, 0xFF)
HDR, BODY, MONO = "DejaVu Sans", "DejaVu Sans", "DejaVu Sans Mono"

prs = Presentation()
prs.slide_width, prs.slide_height = Inches(13.333), Inches(7.5)
W, H = 13.333, 7.5
M = 0.85                      # margin
CW = W - 2 * M                # content width

def blank():
    s = prs.slides.add_slide(prs.slide_layouts[6])
    s.background.fill.solid(); s.background.fill.fore_color.rgb = WHITE
    return s

def tb(s, x, y, w, h, align=PP_ALIGN.LEFT):
    t = s.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = t.text_frame; tf.word_wrap = True
    tf.margin_left = tf.margin_right = tf.margin_top = tf.margin_bottom = 0
    tf.paragraphs[0].alignment = align
    return tf

def para(tf, text, size, color=CHARCOAL, bold=False, font=BODY,
         space_before=0, space_after=6, first=False, align=None, line=None):
    p = tf.paragraphs[0] if first else tf.add_paragraph()
    p.space_before = Pt(space_before); p.space_after = Pt(space_after)
    if align is not None: p.alignment = align
    if line: p.line_spacing = line
    r = p.add_run(); r.text = text
    r.font.size, r.font.bold, r.font.name, r.font.color.rgb = Pt(size), bold, font, color
    return p

def title(s, text, sub=None):
    tf = tb(s, M, 0.62, CW, 1.0)
    para(tf, text, 32, CHARCOAL, True, HDR, first=True, space_after=0)
    if sub:
        para(tf, sub, 15, SLATE, False, BODY, space_before=8)
    ln = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(M), Inches(1.62 if not sub else 1.95),
                            Inches(1.5), Pt(3))
    ln.fill.solid(); ln.fill.fore_color.rgb = CHARCOAL; ln.line.fill.background(); ln.shadow.inherit = False
    return 2.15 if not sub else 2.45

def rect(s, x, y, w, h, fill, line=None):
    sh = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(x), Inches(y), Inches(w), Inches(h))
    sh.fill.solid(); sh.fill.fore_color.rgb = fill
    if line: sh.line.color.rgb = line; sh.line.width = Pt(1)
    else: sh.line.fill.background()
    sh.shadow.inherit = False
    return sh

def bullets(s, y, items, size=17, gap=0.46, x=None, w=None):
    x = x if x is not None else M; w = w if w is not None else CW
    for i, it in enumerate(items):
        d = rect(s, x + 0.05, y + i*gap + 0.11, 0.09, 0.09, SLATE)
        tf = tb(s, x + 0.35, y + i*gap, w - 0.35, gap)
        para(tf, it, size, CHARCOAL, first=True, space_after=0)
    return y + len(items)*gap

def code(s, x, y, w, lines, size=13):
    h = 0.30 + len(lines)*0.245
    rect(s, x, y, w, h, RGBColor(0xF2,0xF4,0xF6), LIGHT)
    tf = tb(s, x+0.22, y+0.15, w-0.4, h-0.3)
    for i, ln in enumerate(lines):
        para(tf, ln, size, CHARCOAL if not ln.startswith("#") else SLATE,
             font=MONO, first=(i==0), space_after=2)
    return y + h

def table(s, x, y, w, rows, col_w, header=True, size=14, rh=0.44):
    n = len(rows)
    for i, row in enumerate(rows):
        yy = y + i*rh
        if i == 0 and header:
            rect(s, x, yy, w, rh, CHARCOAL)
        elif i % 2 == 0:
            rect(s, x, yy, w, rh, RGBColor(0xF5,0xF6,0xF8))
        cx = x
        for j, cell in enumerate(row):
            tf = tb(s, cx+0.16, yy+0.10, col_w[j]-0.25, rh-0.16)
            para(tf, cell, size,
                 WHITE if (i==0 and header) else CHARCOAL,
                 bold=(i==0 and header), first=True, space_after=0)
            cx += col_w[j]
        if not (i == 0 and header):
            ln = rect(s, x, yy+rh-0.012, w, 0.012, LIGHT)
    return y + n*rh

def footer(s, text):
    tf = tb(s, M, H-0.72, CW, 0.4)
    para(tf, text, 12, SLATE, first=True, space_after=0)

def kicker(s, y, text, tone=CHARCOAL):
    rect(s, M, y, CW, 0.62, tone)
    tf = tb(s, M+0.28, y+0.15, CW-0.56, 0.4)
    para(tf, text, 15, WHITE, True, first=True, space_after=0)
    return y + 0.62

# ---------------------------------------------------------------- 1 title
s = blank()
rect(s, 0, 0, W, H, CHARCOAL)
tf = tb(s, M, 2.35, CW, 2.4)
para(tf, "Declarative Schema Management", 46, WHITE, True, HDR, first=True, space_after=2)
para(tf, "in Snowflake", 46, SLATE, True, HDR, space_after=22)
para(tf, "A proof of concept — what it does, what it costs,", 19, LIGHT, space_after=2)
para(tf, "and what it cannot do", 19, LIGHT)
ln = rect(s, M, 5.35, 2.0, 0.035, SLATE)
tf = tb(s, M, 5.72, CW, 0.9)
para(tf, "DCM Projects  ·  8 tables  ·  53 columns  ·  13 findings", 14, LIGHT, first=True, space_after=3)
para(tf, "Personal Snowflake account  ·  August 2026", 13, SLATE)

# ---------------------------------------------------------------- 2 problem
s = blank()
y = title(s, "Our pipelines cannot see the database")
tf = tb(s, M, y, CW, 0.6)
para(tf, "70  CREATE TABLE IF NOT EXISTS  statements across 8 pipeline files.", 18, CHARCOAL, first=True)
y += 0.72
steps = [("1", "Pipeline creates the table", "first run only"),
         ("2", "Someone adds a column by hand", "a Tuesday afternoon, no ticket"),
         ("3", "Pipeline re-runs the same DDL", "\"already exists,\nstatement succeeded\"")]
bw = (CW - 0.5) / 3
for i, (n, t1, t2) in enumerate(steps):
    x = M + i*(bw+0.25)
    tone = CHARCOAL if i == 2 else LIGHT
    rect(s, x, y, bw, 1.85, RGBColor(0xF5,0xF6,0xF8), LIGHT)
    rect(s, x, y, bw, 0.055, tone)
    tf = tb(s, x+0.28, y+0.32, bw-0.56, 1.3)
    para(tf, n, 26, SLATE, True, HDR, first=True, space_after=8)
    para(tf, t1, 15, CHARCOAL, True, space_after=6)
    para(tf, t2, 13, SLATE)
y += 2.1
y = code(s, M, y, CW, [
    "DESC TABLE CUSTOMER;        -- data intact, 2 rows, nothing dropped",
    "",
    "ID       VARCHAR(36)",
    "NAME     VARCHAR(200)",
    "SALARY   VARCHAR(100)     <-- undeclared. Never inspected.",
])
kicker(s, y + 0.24, "It did nothing, said so honestly, and doing nothing counted as success.")

# ---------------------------------------------------------------- 3 guarantees
s = blank()
y = title(s, "Only one of these was ever real")
tf = tb(s, M, y, CW, 0.5)
para(tf, "\u201crepo\u201d here = the Matillion pipeline repo that holds the 70 DDL statements.",
     14, SLATE, first=True)
y = table(s, M, y+0.62, CW,
    [["", "Before", "With DCM"],
     ["“The pipeline repo can build the database”", "YES", "YES"],
     ["“The database still matches the pipeline repo”", "NO", "YES"]],
    [CW-4.2, 2.1, 2.1], rh=0.72, size=16)
tf = tb(s, M, y+0.5, CW, 1.5)
para(tf, "Two different guarantees. Only the first was ever true —", 18, CHARCOAL, first=True, space_after=6)
para(tf, "and nothing in the estate could tell you the difference.", 18, CHARCOAL, space_after=16)
para(tf, "Related, and the reason we went looking: a dashboard dimension in this estate sat frozen",
     14, SLATE, space_after=2)
para(tf, "for seven months. A different defect — a trailing comma that alert-then-succeed hid —",
     14, SLATE, space_after=2)
para(tf, "but the same shape: something that looked like a check and never checked anything.",
     14, SLATE)

# ---------------------------------------------------------------- 4 what is DCM
s = blank()
y = title(s, "Declare the state. Snowflake works out the difference.")
y = bullets(s, y+0.25, [
    "Native Snowflake feature — currently in preview",
    "You declare objects in .sql files; Snowflake computes the changeset",
    "PLAN is a dry run and changes nothing.  DEPLOY applies it",
    "No external state file, unlike Terraform",
    "TABLE, SCHEMA and DATABASE are GA within DCM",
], size=18, gap=0.62)
kicker(s, y+0.5, "The database stops being a place things accumulate, and becomes a build output.")

# ---------------------------------------------------------------- 5 IaC
s = blank()
y = title(s, "The DDL stops living inside the ETL")
cw2 = (CW - 0.45) / 2
for i, (hd, tone, items) in enumerate([
    ("BEFORE", SLATE, ["DDL embedded in orchestration",
                       "70 statements, 8 pipeline files",
                       "Runs as a side effect of a data load",
                       "No review, no diff",
                       "Drift is invisible"]),
    ("AFTER", CHARCOAL, ["DDL in git, reviewed like code",
                         "One source of truth",
                         "Plan shows impact before it lands",
                         "One command rebuilds an environment",
                         "Drift becomes detectable"])]):
    x = M + i*(cw2+0.45)
    rect(s, x, y, cw2, 3.5, RGBColor(0xF5,0xF6,0xF8) if i==0 else WHITE, LIGHT)
    rect(s, x, y, cw2, 0.5, tone)
    tf = tb(s, x+0.28, y+0.11, cw2-0.5, 0.35)
    para(tf, hd, 14, WHITE, True, HDR, first=True, space_after=0)
    for j, it in enumerate(items):
        rect(s, x+0.32, y+0.85+j*0.52, 0.07, 0.07, SLATE)
        tf2 = tb(s, x+0.55, y+0.74+j*0.52, cw2-0.85, 0.45)
        para(tf2, it, 14, CHARCOAL, first=True, space_after=0)
footer(s, "The repo becomes able to prove what the database should look like — not merely to build it once.")

# ---------------------------------------------------------------- 6 DEFINE
s = blank()
y = title(s, "DEFINE, not CREATE", "A description of what should be true — not an instruction to do something")
y = code(s, M, y+0.15, CW, [
    "DEFINE TABLE DEMO_PBI.PRE.DIM_PBI_CAPACITIES (",
    "    ID                VARCHAR(36)   NOT NULL,",
    "    NAME              VARCHAR(500),",
    "    SKU               VARCHAR(50),",
    "    IS_CURRENT_FLAG   NUMBER(1,0)   DEFAULT 1",
    ");",
], size=15)
y = bullets(s, y+0.45, [
    "Definition files accept only DEFINE, GRANT and ATTACH",
    "Names must be fully qualified:  database.schema.object",
    "Executes underneath as CREATE OR ALTER",
], size=16, gap=0.5)
kicker(s, y+0.35, "Remove a DEFINE statement and the next deploy drops the object.")

# ---------------------------------------------------------------- 7 folders
s = blank()
y = title(s, "The folder layout is fixed, not a convention")
y = code(s, M, y+0.2, CW, [
    "manifest.yml            which account, which project, what varies",
    "",
    "sources/",
    "  definitions/          EVERY object definition lives here",
    "  macros/               optional Jinja macros",
    "",
    "out/                    plan and deploy artifacts, generated",
], size=15)
y = bullets(s, y+0.5, [
    "sources/definitions/ is required — files anywhere else are simply not read",
    "Filenames carry no meaning; grouping is for humans",
    "out/ is generated output and is git-ignored",
], size=16, gap=0.5)

# ---------------------------------------------------------------- 8 manifest
s = blank()
y = title(s, "The manifest: where, and what varies")
y = code(s, M, y+0.15, CW, [
    "targets:",
    "  DCM_DEV:",
    "    account_identifier: ORG-ACCOUNT",
    "    project_name: DCM_ADMIN.PROJECTS.PBI_CAPACITIES",
    "    templating_config: DEV",
    "",
    "templating:",
    "  configurations:",
    "    DEV:   { env_suffix: \"\" }",
    "    PROD:  { env_suffix: \"_PROD\" }",
], size=14)
y = bullets(s, y+0.35, [
    "targets = WHERE.    templating = WHAT DIFFERS between environments",
    "The same reviewed files build dev and prod",
], size=16, gap=0.5)
kicker(s, y+0.3, "Promotion is pointing at a different target. You copy nothing.")

# ---------------------------------------------------------------- 9 architecture
s = blank()
y = title(s, "How it fits together")
boxes = [("GitHub", "authoritative"), ("GIT REPOSITORY", "account-level clone"),
         ("DCM PROJECT", "history + artifacts"), ("Database", "LND / STG / PRE")]
bw2 = (CW - 3*0.55) / 4
for i, (t1, t2) in enumerate(boxes):
    x = M + i*(bw2+0.55)
    rect(s, x, y+0.35, bw2, 1.25, CHARCOAL if i in (0,3) else RGBColor(0xF5,0xF6,0xF8),
         None if i in (0,3) else LIGHT)
    tf = tb(s, x+0.15, y+0.62, bw2-0.3, 0.8, PP_ALIGN.CENTER)
    para(tf, t1, 15, WHITE if i in (0,3) else CHARCOAL, True, first=True, space_after=4, align=PP_ALIGN.CENTER)
    para(tf, t2, 11, LIGHT if i in (0,3) else SLATE, align=PP_ALIGN.CENTER)
    if i < 3:
        ar = tb(s, x+bw2+0.06, y+0.78, 0.45, 0.4, PP_ALIGN.CENTER)
        para(ar, "→", 20, SLATE, first=True, space_after=0, align=PP_ALIGN.CENTER)
tf = tb(s, M, y+1.78, CW, 0.4)
para(tf, "         FETCH                    PLAN / DEPLOY", 12, SLATE, first=True, space_after=0)
y2 = y + 2.35
rect(s, M, y2, CW, 1.15, RGBColor(0xF5,0xF6,0xF8), LIGHT)
tf = tb(s, M+0.35, y2+0.22, CW-0.7, 0.8)
para(tf, "Nightly task, 05:00 UTC     →     drift log     →     email alert", 16, CHARCOAL, True, first=True, space_after=6)
para(tf, "Runs PLAN only. Never deploys.", 13, SLATE)
kicker(s, y2+1.45, "PLAN is automated. DEPLOY is a decision a person makes after reading one.")

# ---------------------------------------------------------------- 10 three copies
s = blank()
y = title(s, "Three copies of the same files", "All three can be stale, independently, and nothing warns you")
y = table(s, M, y+0.2, CW,
    [["", "Lives in", "Updated by", "Read by"],
     ["GitHub repo", "github.com", "your push", "everyone"],
     ["GIT REPOSITORY", "a Snowflake schema", "ALTER … FETCH", "plan, deploy, the task"],
     ["Workspace", "your personal database", "Pull button", "you, in the editor"]],
    [3.1, 3.0, 2.7, CW-8.8], rh=0.58, size=14)
y = bullets(s, y+0.4, [
    "A GIT REPOSITORY is a snapshot, not a live link — FETCH or it is stale",
    "A workspace is invisible to automation. A scheduled task cannot read one",
], size=16, gap=0.5)
kicker(s, y+0.3, "GitHub is authoritative. The other two are caches.")

# ---------------------------------------------------------------- 11 one direction
s = blank()
y = title(s, "A change travels in one direction only")
y += 0.5
flow = ["edit", "commit", "GitHub", "FETCH", "PLAN", "review", "DEPLOY", "database"]
bw3 = (CW - 7*0.16) / 8
for i, t in enumerate(flow):
    x = M + i*(bw3+0.16)
    hot = t in ("GitHub", "database")
    rect(s, x, y, bw3, 0.78, CHARCOAL if hot else RGBColor(0xF5,0xF6,0xF8), None if hot else LIGHT)
    tf = tb(s, x+0.05, y+0.26, bw3-0.1, 0.4, PP_ALIGN.CENTER)
    para(tf, t, 12, WHITE if hot else CHARCOAL, True, first=True, space_after=0, align=PP_ALIGN.CENTER)
rect(s, M, y+1.15, CW, 0.045, LIGHT)
tf = tb(s, M, y+1.32, CW, 0.5, PP_ALIGN.CENTER)
para(tf, "no path back", 15, SLATE, True, first=True, space_after=0, align=PP_ALIGN.CENTER)
tf = tb(s, M, y+2.15, CW, 1.2)
para(tf, "A hand-made ALTER never flows back into the repo.", 20, CHARCOAL, True, first=True, space_after=10)
para(tf, "That asymmetry is precisely why drift detection has to exist.", 18, SLATE)

# ---------------------------------------------------------------- 12 three diffs
s = blank()
y = title(s, "Three questions. Git answers two.")
y += 0.3
qs = [("What changed in the definition?", "git diff", False),
      ("What will change in the database?", "DCM PLAN", False),
      ("What changed without going through either?", "drift check", True)]
for i, (q, a, hot) in enumerate(qs):
    yy = y + i*1.16
    rect(s, M, yy, CW, 1.0, CHARCOAL if hot else RGBColor(0xF5,0xF6,0xF8), None if hot else LIGHT)
    tf = tb(s, M+0.4, yy+0.28, CW-4.6, 0.5)
    para(tf, q, 18, WHITE if hot else CHARCOAL, hot, first=True, space_after=0)
    tf2 = tb(s, W-M-3.7, yy+0.28, 3.4, 0.5, PP_ALIGN.RIGHT)
    para(tf2, a, 17, LIGHT if hot else SLATE, True, MONO, first=True, space_after=0, align=PP_ALIGN.RIGHT)
tf = tb(s, M, y+3.75, CW, 0.6)
para(tf, "The third is the one we have never been able to see.", 18, CHARCOAL, True, first=True, space_after=0)

# ---------------------------------------------------------------- 13 verdicts
s = blank()
y = title(s, "Three verdicts. Two states would be wrong most of the time.")
vw = (CW - 0.5) / 3
vs = [("CLEAN", LIGHT, CHARCOAL, "changeset empty",
       "Database matches the repo.\nLogged. No alert sent."),
      ("DRIFT", SLATE, WHITE, "changeset non-empty",
       "Someone changed something.\nRevertible. Alert names\nthe column and datatype."),
      ("ERROR", CHARCOAL, WHITE, "plan failed to compile",
       "Drift exists, CANNOT be\nauto-reverted, and is hiding\nwhatever sits behind it.")]
for i, (nm, fill, txt, sub, body) in enumerate(vs):
    x = M + i*(vw+0.25)
    rect(s, x, y+0.2, vw, 2.75, fill)
    tf = tb(s, x+0.3, y+0.5, vw-0.6, 2.2)
    para(tf, nm, 24, txt, True, HDR, first=True, space_after=4)
    para(tf, sub, 12, txt, False, MONO, space_after=16)
    for line in body.split("\n"):
        para(tf, line, 13, txt, space_after=3)
kicker(s, y+3.25, "45 of our 53 columns are not the last column in their table — so ERROR is the common case.")

# ---------------------------------------------------------------- 14 what it returns
s = blank()
y = title(s, "It names the column, not just the table")
y = code(s, M, y+0.25, CW, [
    'ALTER TABLE "DEVELOP"."PRE"."DIM_PBI_CAPACITIES"',
    '',
    '  columns:  removed  "HAND_ADDED_BY_A_HUMAN"',
    '                     VARCHAR(100), nullable',
], size=15)
y = bullets(s, y+0.5, [
    "Column name, datatype, and which direction the fix runs",
    "The difference between an alert worth waking for and one people mute",
    "Views report more still — the before-and-after SELECT",
], size=17, gap=0.55)

# ---------------------------------------------------------------- 15 audit gap
s = blank()
y = title(s, "The drift check is the one thing Snowflake forgets")
tf = tb(s, M, y, CW, 0.5)
para(tf, "Measured after a full test run — 7+ plans, 4 deploys:", 16, SLATE, first=True)
y = code(s, M, y+0.6, CW, [
    "SELECT PHASE, COUNT(*) FROM DCM_DEPLOYMENT_HISTORY(...)",
    "",
    "   PHASE     N",
    "   DEPLOY    4        <-- no PLAN rows. none.",
], size=15)
y = bullets(s, y+0.45, [
    "Deployments: full immutable artifacts, 12-month retention",
    "Plans: not recorded at all, and no ACCOUNT_USAGE view exists",
], size=16, gap=0.5)
kicker(s, y+0.3, "So we keep our own log. It answers: when did this drift start?")

# ---------------------------------------------------------------- 16 findings
s = blank()
y = title(s, "Thirteen findings. Four came from deliberate sabotage.")
y = table(s, M, y+0.2, CW,
    [["", "Finding"],
     ["F5", "Drift is detected and reported at column level — the verdict"],
     ["F6", "DCM records DEPLOY, never PLAN — an audit table is mandatory"],
     ["F7", "Dropping a column that is not last is un-revertible"],
     ["F9", "Our own monitor sat suspended while its health view said OK"],
     ["F11", "Has now run unattended two consecutive nights, ~30s per run"]],
    [1.3, CW-1.3], rh=0.62, size=15)
kicker(s, y+0.5, "Every failure we found was something reporting success without checking what it claimed to check.")

# ---------------------------------------------------------------- 17 demo
s = blank()
y = title(s, "What we will demo", "Live, end to end, about 20 minutes")
items = [
    "CREATE TABLE IF NOT EXISTS succeeding against a table it never looked at",
    "Build a project from nothing — scaffold, definitions, plan, deploy",
    "Push to git — the repo fills up",
    "Snowflake pulls its own copy; the plan agrees from both directions",
    "Add a table, push, fetch, deploy — a change travelling through git",
    "Tamper with the database by hand — GitHub shows nothing, the check names it",
    "The un-revertible case, and why it changes the design",
]
for i, it in enumerate(items):
    yy = y + 0.1 + i*0.60
    hot = i == 5
    if hot: rect(s, M, yy-0.08, CW, 0.56, RGBColor(0xF5,0xF6,0xF8), LIGHT)
    tf = tb(s, M+0.25, yy, 0.6, 0.45)
    para(tf, f"{i+1}", 16, SLATE, True, MONO, first=True, space_after=0)
    tf2 = tb(s, M+0.85, yy, CW-1.1, 0.45)
    para(tf2, it, 16, CHARCOAL, hot, first=True, space_after=0)

# ---------------------------------------------------------------- 18 limits
s = blank()
y = title(s, "What this does not yet prove")
cw2 = (CW - 0.5) / 2
for i, (hd, tone, items) in enumerate([
    ("LIMITS", SLATE, ["One slice: 8 tables, 53 columns, no data",
                       "Untested at full-estate scale (52 tables, 70 statements)",
                       "DCM Projects is a preview feature",
                       "Grants, tasks and streams unproven",
                       "ERROR recovery rehearsed only on empty tables"]),
    ("NEXT", CHARCOAL, ["Widen to a second slice",
                        "Rehearse recovery on a table holding data",
                        "Scheduled PLAN first — it is read-only",
                        "DEPLOY stays a human decision",
                        "Revisit when the feature reaches GA"])]):
    x = M + i*(cw2+0.5)
    rect(s, x, y, cw2, 3.4, WHITE, LIGHT)
    rect(s, x, y, cw2, 0.5, tone)
    tf = tb(s, x+0.28, y+0.11, cw2-0.5, 0.35)
    para(tf, hd, 14, WHITE, True, HDR, first=True, space_after=0)
    for j, it in enumerate(items):
        rect(s, x+0.32, y+0.87+j*0.5, 0.07, 0.07, SLATE)
        tf2 = tb(s, x+0.55, y+0.76+j*0.5, cw2-0.85, 0.45)
        para(tf2, it, 14, CHARCOAL, first=True, space_after=0)
kicker(s, y+3.75, "The database can now tell us every morning whether it still matches the repo — and name the column when it does not.")

prs.save("DCM_Presentation.pptx")
print("slides:", len(prs.slides.__iter__.__self__._sldIdLst))
