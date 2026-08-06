#!/usr/bin/env bash
# echo_review_stub.sh — a keyless, deterministic stand-in for an external review model.
# Reads the prompt on stdin (ignored) and emits a well-formed CONTRACT_REVIEW completion
# on stdout. Used to validate the external_review.sh disk contract + fallback WITHOUT any
# network or API key:
#
#   HARNESS_REVIEW_CMD="scripts/echo_review_stub.sh" scripts/external_review.sh c.md s.md out.md
#
# Set STUB_VERDICT=REJECT to exercise the reject path; default ACCEPT.
# Set STUB_BROKEN=1 to emit output with NO verdict token (exercises the fallback: the bridge
# must exit 2 so the orchestrator falls back to the haiku subagent).
cat >/dev/null  # consume + discard the prompt on stdin

if [ "${STUB_BROKEN:-0}" = "1" ]; then
  echo "I looked at the contract but I'm not going to give a structured verdict."
  exit 0
fi

echo "VERDICT: ${STUB_VERDICT:-ACCEPT}"
echo "This is a stubbed external review used for keyless local validation."
echo "It confirms the disk contract: line 1 is a valid VERDICT token."
