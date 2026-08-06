#!/usr/bin/env bash
# test_external_review.sh — keyless test suite for the external-review bridge.
# Proves the disk contract (line 1 = VERDICT token), the ACCEPT/REJECT paths, and the
# fallback contract (broken/empty/no-provider -> non-zero exit so the orchestrator falls
# back to the proven haiku subagent). No network, no API key.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE="$HERE/external_review.sh"
STUB="$HERE/echo_review_stub.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

CONTRACT="$TMP/contract.md"; SPEC="$TMP/spec.md"; OUT="$TMP/out.md"
printf '# contract\n- deliver x\n- test: run y\n' > "$CONTRACT"
printf '# spec\n- goal: x\n' > "$SPEC"

pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
no()  { echo "  FAIL: $1"; fail=$((fail+1)); }
line1() { head -n1 "$1"; }

echo "== external_review.sh keyless test suite =="

# 1. ACCEPT path: stub emits VERDICT: ACCEPT -> bridge exit 0, out line 1 exact.
rm -f "$OUT"
if HARNESS_REVIEW_CMD="$STUB" bash "$BRIDGE" "$CONTRACT" "$SPEC" "$OUT" 2>/dev/null; then
  [ "$(line1 "$OUT")" = "VERDICT: ACCEPT" ] && ok "ACCEPT -> exit 0 + line1 'VERDICT: ACCEPT'" \
                                            || no "ACCEPT line1 was: $(line1 "$OUT")"
else no "ACCEPT path exited non-zero"; fi

# 2. REJECT path: stub emits VERDICT: REJECT -> bridge exit 0, out line 1 exact.
rm -f "$OUT"
if STUB_VERDICT=REJECT HARNESS_REVIEW_CMD="$STUB" bash "$BRIDGE" "$CONTRACT" "$SPEC" "$OUT" 2>/dev/null; then
  [ "$(line1 "$OUT")" = "VERDICT: REJECT" ] && ok "REJECT -> exit 0 + line1 'VERDICT: REJECT'" \
                                            || no "REJECT line1 was: $(line1 "$OUT")"
else no "REJECT path exited non-zero"; fi

# 3. Structured header present (SCORE/BLOCKERS/HIGH) so the orchestrator parses uniformly.
rm -f "$OUT"
HARNESS_REVIEW_CMD="$STUB" bash "$BRIDGE" "$CONTRACT" "$SPEC" "$OUT" 2>/dev/null
grep -q '^BLOCKERS: ' "$OUT" && grep -q '^HIGH: ' "$OUT" && ok "structured header written" \
                                                          || no "structured header missing"

# 4. FALLBACK — broken stub (no verdict token) -> bridge exit 2, does NOT leave a bad verdict.
rm -f "$OUT"
STUB_BROKEN=1 HARNESS_REVIEW_CMD="$STUB" bash "$BRIDGE" "$CONTRACT" "$SPEC" "$OUT" 2>/dev/null
rc=$?
{ [ "$rc" -eq 2 ] && [ ! -f "$OUT" ]; } && ok "broken output -> exit 2, no out.md (falls back)" \
                                        || no "broken-output fallback: rc=$rc, out exists=$([ -f "$OUT" ] && echo yes || echo no)"

# 5. FALLBACK — empty output -> exit 2.
rm -f "$OUT"
HARNESS_REVIEW_CMD="printf ''" bash "$BRIDGE" "$CONTRACT" "$SPEC" "$OUT" 2>/dev/null
[ "$?" -eq 2 ] && ok "empty output -> exit 2 (falls back)" || no "empty output did not exit 2"

# 6. No provider configured -> exit 1 (usage, not fallback).
rm -f "$OUT"
env -u HARNESS_REVIEW_CMD -u HARNESS_REVIEW_ENDPOINT -u HARNESS_REVIEW_MODEL \
    bash "$BRIDGE" "$CONTRACT" "$SPEC" "$OUT" 2>/dev/null
[ "$?" -eq 1 ] && ok "no provider -> exit 1" || no "no-provider did not exit 1"

# 7. Missing input file -> exit 1.
env HARNESS_REVIEW_CMD="$STUB" bash "$BRIDGE" "$TMP/nope.md" "$SPEC" "$OUT" 2>/dev/null
[ "$?" -eq 1 ] && ok "missing contract -> exit 1" || no "missing input did not exit 1"

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
