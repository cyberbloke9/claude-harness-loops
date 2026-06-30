#!/usr/bin/env bash
# scripts/validate.sh — static checks for the claude-harness-loops repo.
#
# Deterministic, dependency-free (bash + python3 stdlib ONLY — NO `import yaml`,
# since PyYAML is not guaranteed on ubuntu-latest). Runs identically in CI and
# locally. Prints one PASS/FAIL line per check and a final VALIDATE: line.
# Exit 0 iff ALL checks pass; non-zero on any failure.
#
# Checks:
#   (a) Frontmatter validity   — install/agents/*.md (name, description, tools)
#                                 + install/skills/**/SKILL.md (name, description)
#   (b) bash -n install.sh      — syntax-only; never executes the sync
#   (c) Required SKILL.md sections — (c.1) operating-loop/phases (>=1 "## Step N"
#                                 heading); (c.2, Sprint 005) an "Acceptance Gate"
#                                 section heading; (c.3, Sprint 005) the literal
#                                 token `EVALUATE_SYSTEM` (the gate's Evaluator mode);
#                                 (c.4, Sprint 006) a "Resilience / Resume" section
#                                 heading; (c.5, Sprint 006) the transient-error
#                                 retry-rule anchors (transient, re-read, retry, once,
#                                 backoff, surface); (c.6, Sprint 006) the resume-
#                                 entrypoint anchors (STATUS.md, resum, re-enter,
#                                 recorded phase, mid-sprint, between-sprints,
#                                 acceptance gate). No new check letter.
#   (d) Secret scan             — known key prefixes / private-key blocks in
#                                 git-tracked-or-to-be-tracked files (gitignored
#                                 files are out of scope).
#   (e) Capability isolation    — the harness-evaluator agent's `tools:` list
#                                 (Sprint 002) omits the exact token `Edit`.
#   (f) Generator hygiene clause — the harness-generator agent file (Sprint 003)
#                                 has the "Pre-Handoff Secrets & Git-Hygiene
#                                 Checklist" section AND all four required clauses.
#   (g) Verdict-header schema    — line-1 back-compat + 4-line header (Sprint 004).
#   (h) Evaluator EVALUATE_SYSTEM mode documented (Sprint 005, B10) — the
#                                 harness-evaluator agent file documents the
#                                 cross-sprint, end-to-end regression mode (token +
#                                 `EVALUATE_SYSTEM mode` heading + anchors + PASS/FAIL).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }
pass() { echo "PASS: $1"; }

# ---------------------------------------------------------------------------
# (a) Frontmatter validity — stdlib-only YAML-frontmatter parse + key presence.
#     Globs (not a hardcoded list) so new files are caught. Requires >=1 agent
#     file and >=1 SKILL.md (empty glob = FAIL, not a silent pass).
# ---------------------------------------------------------------------------
if python3 - <<'PY'
import glob, sys

def parse_frontmatter(path):
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return None, "missing opening '---' frontmatter line"
    close = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            close = i
            break
    if close is None:
        return None, "missing closing '---' frontmatter line"
    fm = {}
    for line in lines[1:close]:
        if not line.strip():
            continue
        # Only top-level (non-indented) `key: value` lines define keys.
        if line[0] in (" ", "\t"):
            continue
        if ":" not in line:
            continue
        key, _, val = line.partition(":")
        fm[key.strip()] = val.strip()
    return fm, None

REQUIRED = {
    "agent": ["name", "description", "tools"],   # Sprint 002: tools required on agents
    "skill": ["name", "description"],            # skills NOT required to carry tools
}

agent_files = sorted(glob.glob("install/agents/*.md"))
skill_files = sorted(glob.glob("install/skills/**/SKILL.md", recursive=True))

errors = []
if not agent_files:
    errors.append("no files matched install/agents/*.md (empty-glob guard)")
if not skill_files:
    errors.append("no files matched install/skills/**/SKILL.md (empty-glob guard)")

for kind, files in (("agent", agent_files), ("skill", skill_files)):
    for path in files:
        fm, err = parse_frontmatter(path)
        if err:
            errors.append("%s: %s" % (path, err))
            continue
        for key in REQUIRED[kind]:
            if not fm.get(key):
                errors.append("%s: missing or empty required key '%s'" % (path, key))

if errors:
    for e in errors:
        sys.stderr.write("  - %s\n" % e)
    sys.exit(1)

print("    (%d agent file(s), %d SKILL.md file(s) parsed)" % (len(agent_files), len(skill_files)))
sys.exit(0)
PY
then
    pass "(a) frontmatter validity (agents: name, description, tools; skills: name, description)"
else
    fail "(a) frontmatter validity — see errors above"
fi

# ---------------------------------------------------------------------------
# (b) bash -n install.sh — syntax-only. MUST NOT execute install.sh.
# ---------------------------------------------------------------------------
if [ ! -f install.sh ]; then
    fail "(b) install.sh not found"
elif bash -n install.sh 2>/tmp/_vsh_b.$$; then
    pass "(b) bash -n install.sh (syntax ok)"
else
    echo "  - install.sh: $(cat /tmp/_vsh_b.$$ 2>/dev/null)"
    fail "(b) bash -n install.sh — syntax error in install.sh"
fi
rm -f /tmp/_vsh_b.$$ 2>/dev/null || true

# ---------------------------------------------------------------------------
# (c) Required SKILL.md sections (grows by sprint — §109). All sub-assertions
#     must hold; each reports its own specific failure reason.
#       (c.1) [preserved]  operating-loop/phases: >=1 heading matching
#                          `^#{1,3} Step [0-9]`.
#       (c.2) [Sprint 005] >=1 heading line whose text contains `Acceptance Gate`
#                          (case-insensitive) — the named final loop phase.
#       (c.3) [Sprint 005] the literal token `EVALUATE_SYSTEM` appears (the gate
#                          spawns the Evaluator in that mode).
#       (c.4) [Sprint 006] >=1 heading line matching `^#{1,6} .*Resilience`
#                          (case-insensitive) — the required Resilience/Resume section.
#       (c.5) [Sprint 006] transient-error retry-rule anchors ALL present
#                          (case-insensitive): transient, re-?read, retry, once,
#                          backoff, surface.
#       (c.6) [Sprint 006] resume-entrypoint anchors ALL present (case-insensitive):
#                          STATUS.md, resum, re-?enter, recorded phase, mid-sprint,
#                          between-?sprints, acceptance gate (the three §6 resume
#                          states are enforced, not merely documented).
#     grep -Eqi / grep -qi on SKILL_MAIN only; each sub-assertion names its own
#     specific missing item; (c) PASSes only if ALL of c.1-c.6 hold.
# ---------------------------------------------------------------------------
SKILL_MAIN="install/skills/agent-harness/SKILL.md"
if [ ! -f "$SKILL_MAIN" ]; then
    fail "(c) main skill not found: $SKILL_MAIN"
else
    c_ok=1
    if ! grep -Eq '^#{1,3} Step [0-9]' "$SKILL_MAIN"; then
        echo "  - $SKILL_MAIN: (c.1) missing operating-loop/phases section (expected >=1 heading matching '^#{1,3} Step [0-9]')"
        c_ok=0
    fi
    if ! grep -Eqi '^#{1,6} .*Acceptance Gate' "$SKILL_MAIN"; then
        echo "  - $SKILL_MAIN: (c.2) missing required 'Acceptance Gate' section heading (Sprint 005, §109)"
        c_ok=0
    fi
    if ! grep -q 'EVALUATE_SYSTEM' "$SKILL_MAIN"; then
        echo "  - $SKILL_MAIN: (c.3) missing literal token 'EVALUATE_SYSTEM' (the Acceptance Gate spawns the Evaluator in that mode)"
        c_ok=0
    fi
    # (c.4) [Sprint 006] the required Resilience/Resume section heading.
    if ! grep -Eqi '^#{1,6} .*Resilience' "$SKILL_MAIN"; then
        echo "  - $SKILL_MAIN: (c.4) missing required 'Resilience / Resume' section heading (expected >=1 heading matching '^#{1,6} .*Resilience') (Sprint 006, §109)"
        c_ok=0
    fi
    # (c.5) [Sprint 006] transient-error retry-rule anchors (all must be present).
    for anchor in 'transient' 're-?read' 'retry' 'once' 'backoff' 'surface'; do
        if ! grep -Eqi "$anchor" "$SKILL_MAIN"; then
            echo "  - $SKILL_MAIN: (c.5) missing transient-error retry-rule anchor '$anchor'"
            c_ok=0
        fi
    done
    # (c.6) [Sprint 006] resume-entrypoint anchors (all must be present), incl. the
    #       three §6 resume states (mid-sprint, between-sprints, acceptance gate).
    for anchor in 'STATUS\.md' 'resum' 're-?enter' 'recorded phase' 'mid-sprint' 'between-?sprints' 'acceptance gate'; do
        if ! grep -Eqi "$anchor" "$SKILL_MAIN"; then
            echo "  - $SKILL_MAIN: (c.6) missing resume-entrypoint anchor '$anchor'"
            c_ok=0
        fi
    done
    if [ "$c_ok" -eq 1 ]; then
        pass "(c) required SKILL.md sections present (Step-N phases + Acceptance Gate + EVALUATE_SYSTEM + Resilience/Resume retry + resume anchors) in $SKILL_MAIN"
    else
        fail "(c) required SKILL.md section(s) missing in $SKILL_MAIN (see above)"
    fi
fi

# ---------------------------------------------------------------------------
# (d) Secret scan — known key prefixes / private-key blocks in tracked-or-to-be-
#     tracked files. Uses `git ls-files -co --exclude-standard`: this respects
#     .gitignore (so ruvector.db / .env* / .harness/ are out of scope) and
#     covers BOTH already-tracked files AND not-yet-staged new files, so the
#     local pre-commit run is meaningful even before `git add`. Binary files are
#     skipped. R5 allowlist: placeholders whose tail is all x/X/./placeholder are
#     NOT failures. Self-note: this script's own regex literals contain `[`/`{`
#     and so do not self-match the entropy patterns; the AKIA placeholder literal
#     is caught by the all-X allowlist.
# ---------------------------------------------------------------------------
if python3 - <<'PY'
import re, subprocess, sys, os

PATTERNS = [
    ("OpenAI-style key (sk-)",   re.compile(r'sk-[A-Za-z0-9]{16,}')),
    ("GitHub PAT (ghp_)",        re.compile(r'ghp_[A-Za-z0-9]{20,}')),
    ("GitHub OAuth token (gho_)",re.compile(r'gho_[A-Za-z0-9]{20,}')),
    ("AWS access key (AKIA)",    re.compile(r'AKIA[0-9A-Z]{16}')),
    ("Private key block",        re.compile(r'-----BEGIN [A-Z ]*PRIVATE KEY-----')),
]
PREFIXES = ("sk-", "ghp_", "gho_", "AKIA")
EXPLICIT_PLACEHOLDERS = {"YOUR_KEY_HERE"}

def is_placeholder(token):
    if token in EXPLICIT_PLACEHOLDERS:
        return True
    for p in PREFIXES:
        if token.startswith(p):
            tail = token[len(p):]
            if tail and all(c in "xX." for c in tail):
                return True
    return False

try:
    out = subprocess.run(
        ["git", "ls-files", "-co", "--exclude-standard"],
        capture_output=True, text=True, check=True,
    ).stdout
except Exception as e:
    sys.stderr.write("  - could not enumerate files via git ls-files: %s\n" % e)
    sys.exit(1)

files = [f for f in out.split("\n") if f.strip()]
hits = []
scanned = 0
for path in files:
    if not os.path.isfile(path):
        continue
    try:
        with open(path, "rb") as fh:
            raw = fh.read()
    except OSError:
        continue
    if b"\x00" in raw:           # binary file — skip
        continue
    try:
        content = raw.decode("utf-8")
    except UnicodeDecodeError:
        continue
    scanned += 1
    for lineno, line in enumerate(content.split("\n"), start=1):
        for label, pat in PATTERNS:
            for m in pat.finditer(line):
                token = m.group(0)
                if is_placeholder(token):
                    continue
                hits.append((path, lineno, label, token))

if hits:
    for path, lineno, label, token in hits:
        sys.stderr.write("  - %s:%d  %s  (%s...)\n" % (path, lineno, label, token[:12]))
    sys.exit(1)

print("    (%d text file(s) scanned, 0 secrets)" % scanned)
sys.exit(0)
PY
then
    pass "(d) secret scan (no real keys in tracked-or-to-be-tracked files)"
else
    fail "(d) secret scan — real key material detected (see above)"
fi

# ---------------------------------------------------------------------------
# (e) Capability isolation (Sprint 002, B7) — the harness-evaluator agent's
#     `tools:` list MUST omit the exact token `Edit`. Locate the evaluator by
#     frontmatter `name: harness-evaluator` (empty-match guard: if no such file,
#     FAIL — not a silent pass). Normalize the tools value defensively: split on
#     comma, strip whitespace AND flow brackets `[`/`]`, drop empties, then assert
#     `Edit` is absent. Scope (per B7 letter): exact token `Edit` only; MultiEdit/
#     NotebookEdit are intentionally out of scope this sprint.
# ---------------------------------------------------------------------------
if python3 - <<'PY'
import glob, sys

def parse_frontmatter(path):
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().split("\n")
    if not lines or lines[0].strip() != "---":
        return None
    close = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            close = i
            break
    if close is None:
        return None
    fm = {}
    for line in lines[1:close]:
        if not line.strip() or line[0] in (" ", "\t") or ":" not in line:
            continue
        key, _, val = line.partition(":")
        fm[key.strip()] = val.strip()
    return fm

evaluators = []
for path in sorted(glob.glob("install/agents/*.md")):
    fm = parse_frontmatter(path)
    if fm and fm.get("name") == "harness-evaluator":
        evaluators.append((path, fm))

if not evaluators:
    sys.stderr.write("  - no install/agents/*.md has 'name: harness-evaluator' (empty-match guard)\n")
    sys.exit(1)

bad = []
for path, fm in evaluators:
    raw = fm.get("tools", "")
    if not raw:
        sys.stderr.write("  - %s: evaluator has missing/empty 'tools:' (caught by check (a) too)\n" % path)
        bad.append(path)
        continue
    tokens = []
    for t in raw.split(","):
        t = t.strip().strip("[]").strip()
        if t:
            tokens.append(t)
    if "Edit" in tokens:
        sys.stderr.write("  - %s: evaluator 'tools:' contains forbidden token 'Edit' (%s)\n" % (path, tokens))
        bad.append(path)

if bad:
    sys.exit(1)

print("    (%d evaluator file(s) checked, Edit absent)" % len(evaluators))
sys.exit(0)
PY
then
    pass "(e) capability isolation (harness-evaluator tools omit 'Edit')"
else
    fail "(e) capability isolation — evaluator must omit 'Edit' (see above)"
fi

# ---------------------------------------------------------------------------
# (f) Generator hygiene clause (Sprint 003, B8) — locate the harness-generator
#     agent by frontmatter `name: harness-generator` (empty-match guard: if no
#     such file, FAIL — not a silent pass), then assert (i) the heading
#     `## Pre-Handoff Secrets & Git-Hygiene Checklist` is present and (ii) ALL
#     FOUR required clauses appear in the file (case-insensitive substring):
#       1. `never commit secrets`
#       2. `.gitignore` AND `.env` AND (`uploads` OR `db`)
#       3. `secret scan` AND `before` AND `commit`
#       4. `commit-per-passed-sprint` AND `optional`
#     Heading-only is NOT sufficient; each clause is checked independently so a
#     clause cannot drop silently. Names the offending file and missing item.
# ---------------------------------------------------------------------------
if python3 - <<'PY'
import glob, sys

def parse_frontmatter(path):
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().split("\n")
    if not lines or lines[0].strip() != "---":
        return None
    close = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            close = i
            break
    if close is None:
        return None
    fm = {}
    for line in lines[1:close]:
        if not line.strip() or line[0] in (" ", "\t") or ":" not in line:
            continue
        key, _, val = line.partition(":")
        fm[key.strip()] = val.strip()
    return fm

generators = []
for path in sorted(glob.glob("install/agents/*.md")):
    fm = parse_frontmatter(path)
    if fm and fm.get("name") == "harness-generator":
        generators.append(path)

if not generators:
    sys.stderr.write("  - no install/agents/*.md has 'name: harness-generator' (empty-match guard)\n")
    sys.exit(1)

HEADING = "## pre-handoff secrets & git-hygiene checklist"

errors = []
for path in generators:
    with open(path, encoding="utf-8") as fh:
        content = fh.read()
    low = content.lower()

    if HEADING not in low:
        errors.append("%s: missing required section heading '## Pre-Handoff Secrets & Git-Hygiene Checklist'" % path)
        # still report clause gaps below for completeness

    # clause 1
    if "never commit secrets" not in low:
        errors.append("%s: missing clause 1 anchor 'never commit secrets'" % path)
    # clause 2
    if not (".gitignore" in low and ".env" in low and ("uploads" in low or "db" in low)):
        errors.append("%s: missing clause 2 anchors ('.gitignore' AND '.env' AND ('uploads' OR 'db'))" % path)
    # clause 3
    if not ("secret scan" in low and "before" in low and "commit" in low):
        errors.append("%s: missing clause 3 anchors ('secret scan' AND 'before' AND 'commit')" % path)
    # clause 4
    if not ("commit-per-passed-sprint" in low and "optional" in low):
        errors.append("%s: missing clause 4 anchors ('commit-per-passed-sprint' AND 'optional')" % path)

if errors:
    for e in errors:
        sys.stderr.write("  - %s\n" % e)
    sys.exit(1)

print("    (%d generator file(s) checked, checklist heading + 4 clauses present)" % len(generators))
sys.exit(0)
PY
then
    pass "(f) generator hygiene clause (Pre-Handoff Secrets & Git-Hygiene Checklist + 4 clauses)"
else
    fail "(f) generator hygiene clause — missing section/clause (see above)"
fi

# ---------------------------------------------------------------------------
# (g) Verdict-header schema + line-1 back-compat (Sprint 004, B9/R6) — locate the
#     harness-evaluator agent by frontmatter `name: harness-evaluator` (empty-match
#     guard: if no such file, FAIL). Assert the `## Verdict Header (machine-readable)`
#     heading is present. Extract every fenced code block; a "verdict example block"
#     is any block whose first non-empty content line (after trimming) starts with
#     `VERDICT:`. Require >=1 such block (empty-match guard). For each, after trimming
#     leading/trailing blank lines inside the fence, assert exactly four non-empty
#     lines matching, in order:
#       1. ^VERDICT: (ACCEPT|REJECT|PASS|FAIL)$   <- R6 line-1 back-compat
#       2. ^SCORE: (n/a|[0-5](\.[0-9]+)?)$
#       3. ^BLOCKERS: (0|[1-9][0-9]*)$
#       4. ^HIGH: (0|[1-9][0-9]*)$
#     Cross-field: ACCEPT/PASS => BLOCKERS==0 AND HIGH==0. Coverage: >=1 ACCEPT/REJECT
#     block AND >=1 PASS/FAIL block. A well-formed line 1 with malformed line 2-4 (or
#     a 5th line, or <4 lines) is a FAIL — line-1-only is NOT sufficient. bash +
#     python3 stdlib only (NO import yaml), reusing the parse_frontmatter pattern.
# ---------------------------------------------------------------------------
if python3 - <<'PY'
import glob, re, sys

def parse_frontmatter(path):
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().split("\n")
    if not lines or lines[0].strip() != "---":
        return None
    close = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            close = i
            break
    if close is None:
        return None
    fm = {}
    for line in lines[1:close]:
        if not line.strip() or line[0] in (" ", "\t") or ":" not in line:
            continue
        key, _, val = line.partition(":")
        fm[key.strip()] = val.strip()
    return fm

evaluators = []
for path in sorted(glob.glob("install/agents/*.md")):
    fm = parse_frontmatter(path)
    if fm and fm.get("name") == "harness-evaluator":
        evaluators.append(path)

if not evaluators:
    sys.stderr.write("  - no install/agents/*.md has 'name: harness-evaluator' (empty-match guard)\n")
    sys.exit(1)

HEADING = "## verdict header (machine-readable)"
RE_V = re.compile(r'^VERDICT: (ACCEPT|REJECT|PASS|FAIL)$')
RE_S = re.compile(r'^SCORE: (n/a|[0-5](\.[0-9]+)?)$')
RE_B = re.compile(r'^BLOCKERS: (0|[1-9][0-9]*)$')
RE_H = re.compile(r'^HIGH: (0|[1-9][0-9]*)$')

errors = []
for path in evaluators:
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    lines = text.split("\n")

    if HEADING not in text.lower():
        errors.append("%s: missing required heading '## Verdict Header (machine-readable)'" % path)

    # Extract fenced code blocks (``` delimited). Toggle on any line whose
    # stripped form starts with ```. Markdown does not nest fences.
    blocks, cur, in_fence = [], [], False
    for line in lines:
        if line.lstrip().startswith("```"):
            if in_fence:
                blocks.append(cur); cur = []; in_fence = False
            else:
                in_fence = True; cur = []
            continue
        if in_fence:
            cur.append(line)

    verdict_blocks = []
    for blk in blocks:
        b = blk[:]
        while b and not b[0].strip():
            b.pop(0)
        while b and not b[-1].strip():
            b.pop()
        if b and b[0].strip().startswith("VERDICT:"):
            verdict_blocks.append(b)

    if not verdict_blocks:
        errors.append("%s: no verdict example block (fenced block starting with 'VERDICT:') found (empty-match guard)" % path)
        continue

    tokens_seen = set()
    for b in verdict_blocks:
        if len(b) != 4:
            errors.append("%s: verdict block must be exactly 4 lines, got %d: %r" % (path, len(b), b))
            continue
        m = RE_V.match(b[0])
        if not m:
            errors.append("%s: line 1 violates back-compat '^VERDICT: (ACCEPT|REJECT|PASS|FAIL)$': %r" % (path, b[0]))
            continue
        token = m.group(1)
        tokens_seen.add(token)
        if not RE_S.match(b[1]):
            errors.append("%s: SCORE line violates '^SCORE: (n/a|[0-5](\\.[0-9]+)?)$': %r" % (path, b[1]))
        mb = RE_B.match(b[2])
        if not mb:
            errors.append("%s: BLOCKERS line violates '^BLOCKERS: (0|[1-9][0-9]*)$': %r" % (path, b[2]))
        mh = RE_H.match(b[3])
        if not mh:
            errors.append("%s: HIGH line violates '^HIGH: (0|[1-9][0-9]*)$': %r" % (path, b[3]))
        if token in ("ACCEPT", "PASS") and mb and mh:
            if mb.group(1) != "0" or mh.group(1) != "0":
                errors.append("%s: %s verdict must have BLOCKERS:0 and HIGH:0 (got BLOCKERS:%s HIGH:%s)"
                              % (path, token, mb.group(1), mh.group(1)))

    if not (tokens_seen & {"ACCEPT", "REJECT"}):
        errors.append("%s: no CONTRACT_REVIEW verdict block (ACCEPT/REJECT) found (coverage)" % path)
    if not (tokens_seen & {"PASS", "FAIL"}):
        errors.append("%s: no EVALUATE verdict block (PASS/FAIL) found (coverage)" % path)

if errors:
    for e in errors:
        sys.stderr.write("  - %s\n" % e)
    sys.exit(1)

print("    (%d evaluator file(s) checked; verdict-header schema + line-1 back-compat OK)" % len(evaluators))
sys.exit(0)
PY
then
    pass "(g) verdict-header schema + line-1 back-compat (^VERDICT: token; SCORE/BLOCKERS/HIGH)"
else
    fail "(g) verdict-header schema — malformed/missing header (see above)"
fi

# ---------------------------------------------------------------------------
# (h) Evaluator EVALUATE_SYSTEM mode documented (Sprint 005, B10) — locate the
#     harness-evaluator agent by frontmatter `name: harness-evaluator` (empty-match
#     guard: if no such file, FAIL — not a silent pass, mirroring (e)/(f)/(g)).
#     Assert, naming the specific missing item on failure:
#       (h.1) the literal token `EVALUATE_SYSTEM` appears (mode list / heading).
#       (h.2) a heading line (begins with `#`) contains `EVALUATE_SYSTEM mode`
#             (case-insensitive) — the mode subsection.
#       (h.3) the mode is documented as a cross-sprint end-to-end regression: the
#             anchors `cross-sprint`/`cross sprint` AND `end-to-end`/`end to end`
#             AND `regression` (case-insensitive) are present.
#       (h.4) back-compatible verdict reuse: the tokens `PASS` and `FAIL` and the
#             `VERDICT:` line format are present (no new verdict token invented).
#     bash + python3 stdlib only (NO import yaml), reusing parse_frontmatter.
# ---------------------------------------------------------------------------
if python3 - <<'PY'
import glob, sys

def parse_frontmatter(path):
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().split("\n")
    if not lines or lines[0].strip() != "---":
        return None
    close = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            close = i
            break
    if close is None:
        return None
    fm = {}
    for line in lines[1:close]:
        if not line.strip() or line[0] in (" ", "\t") or ":" not in line:
            continue
        key, _, val = line.partition(":")
        fm[key.strip()] = val.strip()
    return fm

evaluators = []
for path in sorted(glob.glob("install/agents/*.md")):
    fm = parse_frontmatter(path)
    if fm and fm.get("name") == "harness-evaluator":
        evaluators.append(path)

if not evaluators:
    sys.stderr.write("  - no install/agents/*.md has 'name: harness-evaluator' (empty-match guard)\n")
    sys.exit(1)

errors = []
for path in evaluators:
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    low = text.lower()

    # (h.1) token present
    if "EVALUATE_SYSTEM" not in text:
        errors.append("%s: (h.1) missing literal token 'EVALUATE_SYSTEM'" % path)

    # (h.2) mode subsection heading
    heading_found = False
    for line in text.split("\n"):
        if line.lstrip().startswith("#") and "evaluate_system mode" in line.lower():
            heading_found = True
            break
    if not heading_found:
        errors.append("%s: (h.2) no heading line containing 'EVALUATE_SYSTEM mode'" % path)

    # (h.3) cross-sprint / end-to-end / regression anchors
    if not ("cross-sprint" in low or "cross sprint" in low):
        errors.append("%s: (h.3) missing anchor 'cross-sprint' (or 'cross sprint')" % path)
    if not ("end-to-end" in low or "end to end" in low):
        errors.append("%s: (h.3) missing anchor 'end-to-end' (or 'end to end')" % path)
    if "regression" not in low:
        errors.append("%s: (h.3) missing anchor 'regression'" % path)

    # (h.4) back-compatible verdict reuse — no new token invented
    if "PASS" not in text or "FAIL" not in text:
        errors.append("%s: (h.4) missing reused verdict tokens 'PASS'/'FAIL'" % path)
    if "VERDICT:" not in text:
        errors.append("%s: (h.4) missing 'VERDICT:' line format" % path)

if errors:
    for e in errors:
        sys.stderr.write("  - %s\n" % e)
    sys.exit(1)

print("    (%d evaluator file(s) checked; EVALUATE_SYSTEM mode documented)" % len(evaluators))
sys.exit(0)
PY
then
    pass "(h) evaluator EVALUATE_SYSTEM mode documented (token + heading + cross-sprint/end-to-end/regression + PASS/FAIL)"
else
    fail "(h) evaluator EVALUATE_SYSTEM mode — missing token/heading/anchor (see above)"
fi

# ---------------------------------------------------------------------------
echo "---"
if [ "$FAIL" -ne 0 ]; then
    echo "VALIDATE: FAIL"
    exit 1
fi
echo "VALIDATE: PASS"
exit 0
