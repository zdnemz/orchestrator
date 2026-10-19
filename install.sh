#!/usr/bin/env bash
# Install the /orchestrator command for opencode.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
COMMANDS_DIR="$CONFIG_DIR/commands"
TARGET="$COMMANDS_DIR/orchestrator.md"

if [ ! -f "$SRC_DIR/commands/orchestrator.md" ]; then
  echo "error: commands/orchestrator.md not found next to this script." >&2
  echo "       Run it from inside the cloned repo: ./install.sh" >&2
  exit 1
fi

mkdir -p "$COMMANDS_DIR"

if [ -f "$TARGET" ]; then
  backup="$TARGET.bak.$(date +%Y%m%d%H%M%S)"
  cp "$TARGET" "$backup"
  echo "backed up existing command -> $backup"
fi

cp "$SRC_DIR/commands/orchestrator.md" "$TARGET"
echo "installed -> $TARGET"

command -v opencode >/dev/null 2>&1 || \
  echo "warning: 'opencode' is not on your PATH. Install it before using the command."

for d in "$HOME/.agents/skills/interview-me" "$HOME/.claude/skills/interview-me"; do
  [ -d "$d" ] && found=1
done
[ "${found:-}" = 1 ] || \
  echo "note: interview-me skill not found. The command falls back to its built-in interview rules."

cat <<'EOF'

Done. Next:
  opencode
  /orchestrator build me <your goal>

The command needs:
  - a git repo (it creates worktrees; it will git init one if you are in an empty dir)
  - subagent support (built in)
EOF
