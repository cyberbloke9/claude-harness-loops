#!/usr/bin/env bash
# Install the Claude Code Multi-Agent Harness globally (~/.claude),
# making /agent-harness and the three harness-* agents available in EVERY session.
#
# Idempotent: re-run any time to update. Use --uninstall to remove.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
AGENTS_DST="$CLAUDE_DIR/agents"
SKILL_DST="$CLAUDE_DIR/skills/agent-harness"

AGENTS=(harness-planner.md harness-generator.md harness-evaluator.md)

uninstall() {
  echo "Removing harness from $CLAUDE_DIR ..."
  for a in "${AGENTS[@]}"; do rm -f "$AGENTS_DST/$a"; done
  rm -rf "$SKILL_DST"
  echo "Done. The /agent-harness skill and harness-* agents are removed."
  exit 0
}

[[ "${1:-}" == "--uninstall" ]] && uninstall

echo "Installing harness -> $CLAUDE_DIR"
mkdir -p "$AGENTS_DST" "$SKILL_DST"

for a in "${AGENTS[@]}"; do
  cp "$SRC_DIR/install/agents/$a" "$AGENTS_DST/$a"
  echo "  agent: $AGENTS_DST/$a"
done

cp "$SRC_DIR/install/skills/agent-harness/SKILL.md" "$SKILL_DST/SKILL.md"
echo "  skill: $SKILL_DST/SKILL.md"

echo
echo "Installed. In any Claude Code session, run:"
echo "    /agent-harness <what to build>"
echo
echo "The three agents (harness-planner, harness-generator, harness-evaluator)"
echo "coordinate ONLY through a .harness/ directory on disk — state is shared,"
echo "conversation context is never shared between them."
