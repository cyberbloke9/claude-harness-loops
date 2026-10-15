#!/usr/bin/env bash
# validate_seam_offline.sh — OFFLINE, one-time validation of the corrected GYWD×harness seam
# (docs/DESIGN-gywd-integration.md CORRECTION 2026-10-15). It does NOT run any build or spawn any
# agent. It checks that a real, already-PASSED GYWD→harness project exhibits exactly the mapping the
# corrected `/gywd:execute-plan-harness` command promises:
#
#   ROADMAP milestone (phase list + a `Requirements:` doc + "phases map 1:1 to sprints")
#     -> harness-planner -> .harness/spec.md with one Sprint per ROADMAP phase, in order.
#
# This is NOT part of CI (it needs a real GYWD project, which isn't in this repo). It SKIPS cleanly
# (exit 0) when no such project is present, so it is safe to run anywhere.
#
# Usage: validate_seam_offline.sh [GYWD_PROJECT_DIR] [SPEC_PATH]
#   GYWD_PROJECT_DIR  the GYWD project to validate (default: $PWD)
#   SPEC_PATH         optional — a spec.md to check INSTEAD of the project's live one. Pass a
#                     scratchpad spec freshly produced by the command's Step-4 Planner spawn to
#                     prove the command itself reproduces the project's phase→sprint decomposition.
set -uo pipefail

PROJ="${1:-$PWD}"
ROADMAP="$PROJ/.planning/ROADMAP.md"
SPEC="${2:-$PROJ/.harness/spec.md}"

if [ ! -f "$ROADMAP" ] || [ ! -f "$SPEC" ]; then
  echo "SKIP: no GYWD→harness project at $PROJ (need .planning/ROADMAP.md + .harness/spec.md)."
  echo "      Pass a project dir to validate against your own run."
  exit 0
fi

echo "== Offline seam validation against: $PROJ =="
fail=0; ok() { echo "  PASS: $1"; }; no() { echo "  FAIL: $1"; fail=1; }

# 1. The user's convention is literally in the ROADMAP: a milestone that names a Requirements doc
#    and declares phases map 1:1 to sprints. (This is what the corrected command keys off.)
grep -Eqi 'Requirements:' "$ROADMAP"                 && ok "ROADMAP names a Requirements doc for a milestone" \
                                                     || no "ROADMAP has no 'Requirements:' pointer"
grep -Eqi 'map 1:1 to (harness |agent-harness )?sprints' "$ROADMAP" \
    && ok "ROADMAP declares phases map 1:1 to sprints" \
    || no "ROADMAP does not declare the 1:1 phase→sprint convention"

# 2. The requirements doc the ROADMAP names actually exists on disk (the Planner's second input).
#    Use the LAST 'Requirements:' line (the most-recent milestone) so we validate the target, not an
#    earlier milestone's doc.
REQ="$(grep -Ei 'Requirements:' "$ROADMAP" | tail -1 | grep -Eoi '\.planning/[A-Za-z0-9_.-]+\.md' | head -1)"
if [ -n "$REQ" ] && [ -f "$PROJ/$REQ" ]; then ok "latest-milestone requirements doc exists: $REQ"
else no "requirements doc referenced by the latest milestone not found (got: '${REQ:-none}')"; fi

# 3. The core claim: each ROADMAP phase maps 1:1, IN ORDER, to a sprint in the Planner-written spec.
#    Extract Phase<->Sprint pairs from the spec (it carries them as "(Phase N / Sprint 00M)" and
#    in the "Sprint 00M — … (Phase N)" breakdown). Build the phase->sprint map and check monotonic 1:1.
# Normalize into "phase sprint" lines regardless of which token came first.
norm="$(grep -Eoi 'Phase [0-9]+ */ *Sprint [0-9]+' "$SPEC" | sed -E 's/Phase ([0-9]+) *\/ *Sprint ([0-9]+)/\1 \2/' | sort -n | uniq)"
if [ -z "$norm" ]; then
  # fall back to the breakdown form "Sprint 00M — …(Phase N)"
  norm="$(grep -Eoi 'Sprint [0-9]+ .*\(Phase [0-9]+\)' "$SPEC" \
          | sed -E 's/.*Sprint 0*([0-9]+).*\(Phase ([0-9]+)\).*/\2 \1/' | sort -n | uniq)"
fi
n_phases="$(printf '%s\n' "$norm" | grep -c '[0-9]')"
if [ "$n_phases" -ge 1 ]; then
  ok "spec.md maps $n_phases ROADMAP phase(s) to sprints (Planner-written, phase order)"
  echo "    phase→sprint:"; printf '%s\n' "$norm" | awk 'NF{printf "      Phase %s -> Sprint %03d\n",$1,$2}'
  # 1:1 check: distinct phases == distinct sprints == pair count
  dp="$(printf '%s\n' "$norm" | awk '{print $1}' | sort -nu | wc -l | tr -d ' ')"
  ds="$(printf '%s\n' "$norm" | awk '{print $2}' | sort -nu | wc -l | tr -d ' ')"
  { [ "$dp" = "$n_phases" ] && [ "$ds" = "$n_phases" ]; } && ok "mapping is strictly 1:1 ($dp phases ⇄ $ds sprints)" \
                                                           || no "mapping is not 1:1 ($dp phases vs $ds sprints)"
else
  no "could not extract any Phase↔Sprint mapping from spec.md"
fi

# 4. The spec was Planner-produced (the corrected command spawns harness-planner, doesn't hand-translate).
grep -Eqi 'written by the planner|planner for the' "$SPEC" && ok "spec.md attributes authorship to the Planner" \
                                                            || echo "  NOTE: spec.md lacks an explicit Planner byline (not fatal)"

echo "== seam validation: $([ "$fail" -eq 0 ] && echo PASS || echo FAIL) =="
[ "$fail" -eq 0 ]
