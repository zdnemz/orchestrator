#!/usr/bin/env bash
# Structural check for the command. Runs locally and in CI.
set -euo pipefail
cd "$(dirname "$0")"

CMD=commands/orchestrator.md
fail=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fail=1; }

[ -s "$CMD" ] && ok "command exists" || bad "command missing"

head -1 "$CMD" | grep -qx -- '---' && ok "frontmatter opens" || bad "frontmatter does not open with ---"
grep -q '^description:' "$CMD" && ok "description set" || bad "no description in frontmatter"
grep -qF '$ARGUMENTS' "$CMD" && ok '$ARGUMENTS interpolated' || bad '$ARGUMENTS missing'

# Real sections — anchored, so a passing mention in prose does not count.
for h in "Loop" "Multi-wave planning" "Rules" "Dependencies" "Blockers" \
         "CODER PROMPT" "PLANNER PROMPT" "REVIEWER PROMPT"; do
  if grep -qxF "## $h" "$CMD"; then ok "section: $h"; else bad "missing section: $h"; fi
done

# The rules that carry the system. Deleting any of these silently breaks a run.
while IFS= read -r phrase; do
  if grep -qF "$phrase" "$CMD"; then ok "$phrase"; else bad "missing rule: $phrase"; fi
done <<'RULES'
Pin the shared contract BEFORE the task table
Add an integration gate
Use those absolute paths
A worker that never reports back
git worktree prune
A task is READY only when every dep is merged
Never invent a value to avoid parking
RULES

n=$(grep -cE '^[[:space:]]*```' "$CMD" || true)
if [ $((n % 2)) -eq 0 ]; then ok "code fences balanced ($n)"; else bad "unbalanced code fences ($n)"; fi

if grep -nE '/home/[a-z]|9router/' "$CMD"; then
  bad "machine-specific path or provider pin in the command"
else
  ok "no machine-specific paths or provider pins"
fi

bash -n install.sh && ok "install.sh syntax" || bad "install.sh syntax"
[ -x install.sh ] && ok "install.sh executable" || bad "install.sh is not executable"

tmp=$(mktemp -d)
XDG_CONFIG_HOME="$tmp" ./install.sh >/dev/null
if [ -s "$tmp/opencode/commands/orchestrator.md" ]; then ok "installs"; else bad "install produced nothing"; fi
if cmp -s "$tmp/opencode/commands/orchestrator.md" "$CMD"; then ok "installed copy matches"; else bad "installed copy differs"; fi
rm -rf "$tmp"

[ "$fail" -eq 0 ] && echo "PASS" || { echo "FAIL"; exit 1; }
