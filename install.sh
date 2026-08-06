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
GATE_DST="$CLAUDE_DIR/skills/agent-harness-gate"
RESUME_DST="$CLAUDE_DIR/skills/agent-harness-resume"
GYWD_CMD_DST="$CLAUDE_DIR/commands/gywd"

AGENTS=(harness-planner.md harness-generator.md harness-evaluator.md)
# GYWD × harness bridge command — installed into GYWD's command namespace if it exists.
GYWD_BRIDGE=execute-plan-harness.md

# External-review bridge scripts — installed next to the skill so the SKILL.md hook can
# reference an absolute, cwd-independent path (the orchestrator runs from the user's project).
REVIEW_SCRIPTS=(external_review.sh echo_review_stub.sh test_external_review.sh)

uninstall() {
  echo "Removing harness from $CLAUDE_DIR ..."
  for a in "${AGENTS[@]}"; do rm -f "$AGENTS_DST/$a"; done
  rm -rf "$SKILL_DST" "$GATE_DST" "$RESUME_DST"
  rm -f "$GYWD_CMD_DST/$GYWD_BRIDGE"
  echo "Done. The /agent-harness skill, companion skills, harness-* agents, and the GYWD bridge command are removed."
  exit 0
}

[[ "${1:-}" == "--uninstall" ]] && uninstall

echo "Installing harness -> $CLAUDE_DIR"
mkdir -p "$AGENTS_DST" "$SKILL_DST" "$GATE_DST" "$RESUME_DST"

for a in "${AGENTS[@]}"; do
  cp "$SRC_DIR/install/agents/$a" "$AGENTS_DST/$a"
  echo "  agent: $AGENTS_DST/$a"
done

cp "$SRC_DIR/install/skills/agent-harness/SKILL.md" "$SKILL_DST/SKILL.md"
echo "  skill: $SKILL_DST/SKILL.md"

cp "$SRC_DIR/install/skills/agent-harness-gate/SKILL.md" "$GATE_DST/SKILL.md"
echo "  skill: $GATE_DST/SKILL.md"

cp "$SRC_DIR/install/skills/agent-harness-resume/SKILL.md" "$RESUME_DST/SKILL.md"
echo "  skill: $RESUME_DST/SKILL.md"

# External-review bridge scripts -> alongside the main skill (absolute path for the hook).
mkdir -p "$SKILL_DST/scripts"
for s in "${REVIEW_SCRIPTS[@]}"; do
  cp "$SRC_DIR/scripts/$s" "$SKILL_DST/scripts/$s"
  chmod +x "$SKILL_DST/scripts/$s"
  echo "  script: $SKILL_DST/scripts/$s"
done

# GYWD bridge command — install only when GYWD's command namespace is present, so this stays
# a local opt-in (like GYWD itself) and never creates a stray dir on machines without GYWD.
if [ -d "$GYWD_CMD_DST" ]; then
  cp "$SRC_DIR/install/commands/gywd/$GYWD_BRIDGE" "$GYWD_CMD_DST/$GYWD_BRIDGE"
  echo "  command: $GYWD_CMD_DST/$GYWD_BRIDGE  (GYWD bridge)"
else
  echo "  (skipped GYWD bridge: $GYWD_CMD_DST not found — install GYWD first, then re-run)"
fi

echo
echo "Installed. In any Claude Code session, run:"
echo "    /agent-harness <what to build>"
echo "    /agent-harness-gate <project>     # run the acceptance gate on a finished project"
echo "    /agent-harness-resume <project>   # resume an interrupted run"
echo
echo "The three agents (harness-planner, harness-generator, harness-evaluator)"
echo "coordinate ONLY through a .harness/ directory on disk — state is shared,"
echo "conversation context is never shared between them."
