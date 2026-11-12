#!/usr/bin/env bash
# external_review.sh — OPTIONAL, OFF BY DEFAULT external-LLM bridge for the harness's
# single low-stakes phase: CONTRACT_REVIEW.
#
# The harness's CONTRACT_REVIEW is a pure disk-in / disk-out checklist:
#   read contract.md + spec.md  ->  write contract_review.md whose FIRST line is
#   exactly `VERDICT: ACCEPT` or `VERDICT: REJECT`.
# Whether that function is served by a Claude `haiku` subagent or by an external
# (non-Claude) model is an implementation detail behind the SAME disk contract.
# This script serves it with an external model, and is fallback-safe: on ANY failure
# it exits non-zero so the orchestrator falls back to the proven haiku subagent.
#
# It is used ONLY when HARNESS_EXTERNAL_REVIEW=1 (see SKILL.md Step 2b). BUILD / EVALUATE
# / the Acceptance Gate are NEVER externalized — they need tools + multi-turn agency and
# stay on the Claude-subagent model. CONTRACT_REVIEW is the one phase whose provider risk
# is contained, because strong-opus EVALUATE + the gate re-attack anything it lets through.
#
# Usage:
#   external_review.sh <contract.md> <spec.md> <out.md>
#
# Provider interface (pick ONE; CMD wins if both are set):
#   HARNESS_REVIEW_CMD        a command that reads the prompt on stdin and emits the
#                             model completion on stdout (e.g. the local echo-stub, ollama,
#                             a wrapper around any CLI). Keyless-friendly.
#   HARNESS_REVIEW_ENDPOINT   an OpenAI-compatible chat/completions URL, used with
#   HARNESS_REVIEW_MODEL      the model id, and
#   HARNESS_REVIEW_KEY        the bearer token (never echoed).
#
# Validation status: the CMD path is covered by the keyless test suite. The HTTP path is
# validated structurally only (no live endpoint in CI); exercise it against your own
# OpenAI-compatible server before relying on it.
#
# Exit codes:
#   0  a well-formed verdict (line 1 = `VERDICT: ACCEPT|REJECT`) was written to <out.md>
#   1  usage / missing inputs / no provider configured
#   2  provider call failed, or output contained no usable VERDICT token -> caller falls back
set -euo pipefail

die_fallback() { echo "external_review: $*" >&2; exit 2; }

[ "$#" -eq 3 ] || { echo "usage: external_review.sh <contract.md> <spec.md> <out.md>" >&2; exit 1; }
CONTRACT="$1"; SPEC="$2"; OUT="$3"
[ -f "$CONTRACT" ] || { echo "external_review: contract not found: $CONTRACT" >&2; exit 1; }
[ -f "$SPEC" ]     || { echo "external_review: spec not found: $SPEC" >&2; exit 1; }
# Clear any stale output up front: a fallback exit (exit 2) must never leave an old/bogus verdict
# file behind for the orchestrator to misread. On success we rewrite it; on fallback it stays gone.
rm -f "$OUT" 2>/dev/null || true

# --- Build the CONTRACT_REVIEW prompt (same mechanical bar the Evaluator applies) ---
PROMPT="$(cat <<EOF
You are a strict but fair contract reviewer for a software build harness. This is a MECHANICAL
conformance pass on a proposed sprint CONTRACT against its SPEC. No code exists yet — do NOT
review code, only whether the contract is a faithful, complete, testable plan.

Check:
1. Every required user-facing state / behavior in the SPEC has a corresponding adversarial
   contract-test row in the CONTRACT.
2. The CONTRACT does not silently re-invent or contradict any pinned SPEC decision; if it
   restates one, it must match.
3. The CONTRACT lists exact files, exact verification commands, and a concrete acceptance bar.

Respond with your verdict. The VERY FIRST line of your response MUST be exactly one of:
VERDICT: ACCEPT
VERDICT: REJECT
Then, on following lines, a brief justification and any blockers. Do not put anything before
the VERDICT line.

===== SPEC =====
$(cat "$SPEC")

===== CONTRACT =====
$(cat "$CONTRACT")
EOF
)"

# --- Call the provider -> RAW completion on stdout ---
RAW=""
if [ -n "${HARNESS_REVIEW_CMD:-}" ]; then
  RAW="$(printf '%s' "$PROMPT" | eval "$HARNESS_REVIEW_CMD" 2>/dev/null)" || die_fallback "HARNESS_REVIEW_CMD failed"
elif [ -n "${HARNESS_REVIEW_ENDPOINT:-}" ] && [ -n "${HARNESS_REVIEW_MODEL:-}" ]; then
  command -v curl >/dev/null 2>&1 || die_fallback "curl not found for HTTP provider"
  command -v python3 >/dev/null 2>&1 || die_fallback "python3 not found to build JSON payload"
  # Build the JSON body safely (python handles escaping); OpenAI-compatible chat schema.
  BODY="$(HARNESS_PROMPT="$PROMPT" MODEL="$HARNESS_REVIEW_MODEL" python3 -c 'import json,os
print(json.dumps({
  "model": os.environ["MODEL"],
  "messages": [{"role":"user","content": os.environ["HARNESS_PROMPT"]}],
  "temperature": 0
}))')" || die_fallback "failed to build request body"
  # Keep the API key and the (potentially large) request body OFF the process argv: the key goes
  # through a curl -K config on a process-substitution fd (not visible via `ps`/cmdline), and the
  # body goes in on stdin (avoids ARG_MAX on a big spec). Needs bash — the shebang guarantees it.
  if [ -n "${HARNESS_REVIEW_KEY:-}" ]; then
    RESP="$(printf '%s' "$BODY" | curl -fsS "$HARNESS_REVIEW_ENDPOINT" \
        -H "Content-Type: application/json" \
        -K <(printf 'header = "Authorization: Bearer %s"\n' "$HARNESS_REVIEW_KEY") \
        --data-binary @- 2>/dev/null)" || die_fallback "provider HTTP call failed"
  else
    RESP="$(printf '%s' "$BODY" | curl -fsS "$HARNESS_REVIEW_ENDPOINT" \
        -H "Content-Type: application/json" \
        --data-binary @- 2>/dev/null)" || die_fallback "provider HTTP call failed"
  fi
  RAW="$(printf '%s' "$RESP" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin); print(d["choices"][0]["message"]["content"])
except Exception: sys.exit(1)')" || die_fallback "could not parse provider response"
else
  echo "external_review: no provider configured (set HARNESS_REVIEW_CMD or HARNESS_REVIEW_ENDPOINT+MODEL)" >&2
  exit 1
fi

[ -n "${RAW//[[:space:]]/}" ] || die_fallback "provider returned empty output"

# --- Enforce the disk contract: the FIRST non-blank line must be a valid VERDICT token ---
# Guard against prompt-echo / ambiguity: if BOTH ACCEPT and REJECT verdict lines appear anywhere
# (e.g. a model that echoes this script's own prompt, which contains both), the output is
# untrustworthy — fall back rather than pick the first (which would silently fail OPEN to ACCEPT).
if printf '%s\n' "$RAW" | grep -qE '^[[:space:]]*VERDICT:[[:space:]]*ACCEPT[[:space:]]*$' \
   && printf '%s\n' "$RAW" | grep -qE '^[[:space:]]*VERDICT:[[:space:]]*REJECT[[:space:]]*$'; then
  die_fallback "ambiguous output: both ACCEPT and REJECT verdict lines present (prompt echo?)"
fi
# The verdict must BE the first non-blank line, not merely appear somewhere in the prose.
FIRST_NONBLANK="$(printf '%s\n' "$RAW" | sed -e '/^[[:space:]]*$/d' | head -n1)"
VERDICT_LINE="$(printf '%s\n' "$FIRST_NONBLANK" | grep -E '^[[:space:]]*VERDICT:[[:space:]]*(ACCEPT|REJECT)[[:space:]]*$' || true)"
[ -n "$VERDICT_LINE" ] || die_fallback "first non-blank line is not 'VERDICT: ACCEPT|REJECT'"
# Canonicalize (strip surrounding whitespace, collapse to `VERDICT: TOKEN`).
TOKEN="$(printf '%s' "$VERDICT_LINE" | sed -E 's/^[[:space:]]*VERDICT:[[:space:]]*//; s/[[:space:]]*$//')"

# The external model's prose is not parsed for counts, so SCORE/BLOCKERS/HIGH are 'n/a'
# rather than a fabricated 0 — the orchestrator routes on the VERDICT first line only.
{
  printf 'VERDICT: %s\n' "$TOKEN"
  printf 'SCORE: n/a\n'
  printf 'BLOCKERS: n/a\n'
  printf 'HIGH: n/a\n'
  printf '\n---\n(external review via %s)\n\n' "${HARNESS_REVIEW_MODEL:-HARNESS_REVIEW_CMD}"
  printf '%s\n' "$RAW"
} > "$OUT"

echo "external_review: wrote $OUT (VERDICT: $TOKEN)" >&2
exit 0
