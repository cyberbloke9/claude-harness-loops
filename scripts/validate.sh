#!/usr/bin/env bash
# scripts/validate.sh — static checks for the claude-harness-loops repo.
#
# Deterministic, dependency-free (bash + python3 stdlib ONLY — NO `import yaml`,
# since PyYAML is not guaranteed on ubuntu-latest). Runs identically in CI and
# locally. Prints one PASS/FAIL line per check and a final VALIDATE: line.
# Exit 0 iff ALL checks pass; non-zero on any failure.
#
# Checks (Sprint 001 — calibrated to CURRENT files, NO `tools:` requirement):
#   (a) Frontmatter validity   — install/agents/*.md + install/skills/**/SKILL.md
#   (b) bash -n install.sh      — syntax-only; never executes the sync
#   (c) Required SKILL.md sections — operating-loop/phases (>=1 "## Step N" heading)
#   (d) Secret scan             — known key prefixes / private-key blocks in
#                                 git-tracked-or-to-be-tracked files (gitignored
#                                 files are out of scope).
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
    "agent": ["name", "description"],     # NO `tools` requirement — Sprint 002
    "skill": ["name", "description"],
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
    pass "(a) frontmatter validity (name, description present; no tools requirement)"
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
# (c) Required SKILL.md sections — operating-loop/phases section.
#     Calibrated to current content: >=1 heading matching `^#{1,3} Step [0-9]`.
# ---------------------------------------------------------------------------
SKILL_MAIN="install/skills/agent-harness/SKILL.md"
if [ ! -f "$SKILL_MAIN" ]; then
    fail "(c) main skill not found: $SKILL_MAIN"
elif grep -Eq '^#{1,3} Step [0-9]' "$SKILL_MAIN"; then
    pass "(c) required SKILL.md section present (operating-loop/phases: '## Step N' headings) in $SKILL_MAIN"
else
    echo "  - $SKILL_MAIN: missing operating-loop/phases section (expected >=1 heading matching '^#{1,3} Step [0-9]')"
    fail "(c) required SKILL.md section missing in $SKILL_MAIN"
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
echo "---"
if [ "$FAIL" -ne 0 ]; then
    echo "VALIDATE: FAIL"
    exit 1
fi
echo "VALIDATE: PASS"
exit 0
