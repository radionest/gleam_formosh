#!/bin/bash
# PreToolUse Bash hook: blocks direct push to remote main/master from worktrees.
# Catches `git push origin HEAD:main` / `<branch>:main` / `origin main` / --all / --mirror.
# Pushes from the root checkout are allowed (e.g. `/bump` flow on main).

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | grep -oP '"command"\s*:\s*"\K[^"]*' || true)
[ -z "$COMMAND" ] && exit 0

# Not a git push — exit fast
echo "$COMMAND" | grep -qP 'git\s+(.*\s)?push\b' || exit 0

# Does this push land on main/master?
PUSHES_MAIN=0
if echo "$COMMAND" | grep -qP 'push\b[^|;&]*\s(--all|--mirror)\b'; then
  PUSHES_MAIN=1
elif echo "$COMMAND" | grep -qP 'push\b[^|;&]*:(main|master)\b'; then
  PUSHES_MAIN=1
elif echo "$COMMAND" | grep -qP 'push\b[^|;&]+\s\+?(main|master)(\s|$)'; then
  PUSHES_MAIN=1
fi

[ "$PUSHES_MAIN" = "1" ] || exit 0

# Resolve target git dir (handle `git -C <path>`)
TARGET_DIR=$(echo "$COMMAND" | grep -oP 'git\s+-C\s+\K\S+' || true)

if [ -n "$TARGET_DIR" ]; then
  GIT_DIR=$(git -C "$TARGET_DIR" rev-parse --git-dir 2>/dev/null) || exit 0
  COMMON_DIR=$(git -C "$TARGET_DIR" rev-parse --git-common-dir 2>/dev/null) || exit 0
else
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
  GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
  COMMON_DIR=$(git rev-parse --git-common-dir 2>/dev/null)
fi

# Worktree (GIT_DIR != COMMON_DIR) — block
if [ "$(realpath "$GIT_DIR")" != "$(realpath "$COMMON_DIR")" ]; then
  cat >&2 <<'EOF'
BLOCKED: Direct push to origin main/master from a worktree is not allowed.
Open a pull request from your feature branch instead:
  gh pr create --base main --head <your-branch>
Version bumps must run via `/bump` from the root checkout on main.
EOF
  exit 2
fi

exit 0
