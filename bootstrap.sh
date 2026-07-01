#!/usr/bin/env bash
# Remote installer for the Claude Code Multi-Agent Harness.
#
#   curl -fsSL https://raw.githubusercontent.com/cyberbloke9/claude-harness-loops/main/bootstrap.sh | bash
#
# Clones (or updates) the repo into a stable location, then runs its install.sh to sync
# the skills + agents into ~/.claude. Re-run any time to update. Idempotent.
set -euo pipefail

REPO_URL="${CLAUDE_HARNESS_REPO:-https://github.com/cyberbloke9/claude-harness-loops.git}"
DEST="${CLAUDE_HARNESS_HOME:-$HOME/.local/share/claude-harness-loops}"
BRANCH="${CLAUDE_HARNESS_BRANCH:-main}"

command -v git  >/dev/null 2>&1 || { echo "bootstrap: 'git' is required but not found." >&2; exit 1; }
command -v bash >/dev/null 2>&1 || { echo "bootstrap: 'bash' is required but not found." >&2; exit 1; }

if [ -d "$DEST/.git" ]; then
  echo "bootstrap: updating existing checkout at $DEST"
  git -C "$DEST" fetch --quiet origin "$BRANCH"
  git -C "$DEST" checkout --quiet "$BRANCH"
  git -C "$DEST" reset --hard --quiet "origin/$BRANCH"
else
  echo "bootstrap: cloning $REPO_URL -> $DEST"
  mkdir -p "$(dirname "$DEST")"
  git clone --quiet --branch "$BRANCH" "$REPO_URL" "$DEST"
fi

echo "bootstrap: running installer"
bash "$DEST/install.sh"

echo
echo "bootstrap: done. Source lives at $DEST"
echo "  update:    curl -fsSL https://raw.githubusercontent.com/cyberbloke9/claude-harness-loops/main/bootstrap.sh | bash"
echo "  uninstall: $DEST/install.sh --uninstall"
