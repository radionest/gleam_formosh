#!/bin/bash
# Bump version in gleam.toml, commit, tag, push, and create a GitHub Release.
#
# Usage:
#   scripts/bump.sh          # auto-increment patch (0.2.3 → 0.2.4)
#   scripts/bump.sh 0.3.0    # set explicit version
#
# Must be on main branch with clean working tree.
# Set BUMP_NO_RELEASE=1 to push tag only and skip the GitHub Release step.

set -euo pipefail

MANIFEST="gleam.toml"

if [ ! -f "$MANIFEST" ]; then
  echo "Error: $MANIFEST not found" >&2
  exit 1
fi

BRANCH=$(git branch --show-current)
if [ "$BRANCH" != "main" ]; then
  echo "Error: must be on main branch (current: $BRANCH)" >&2
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "Error: working tree is not clean" >&2
  git status --short >&2
  exit 1
fi

if [ "${BUMP_NO_RELEASE:-0}" != "1" ]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "Error: gh CLI not found (set BUMP_NO_RELEASE=1 to skip the release step)" >&2
    exit 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo "Error: gh CLI is not authenticated (run \`gh auth login\` or set BUMP_NO_RELEASE=1)" >&2
    exit 1
  fi
fi

CURRENT=$(python3 -c "
import re, sys
m = re.search(r'^version\s*=\s*\"([^\"]+)\"', open('$MANIFEST').read(), re.M)
if not m: sys.exit(1)
print(m.group(1))
") || { echo "Error: could not read version from $MANIFEST" >&2; exit 1; }

if [ $# -ge 1 ]; then
  NEW="$1"
else
  NEW=$(python3 -c "
import re, sys
v = '$CURRENT'
m = re.match(r'^(.+\.)(\d+)$', v)
if not m:
    print(f'Error: cannot auto-increment version \"{v}\"', file=sys.stderr)
    sys.exit(1)
print(f'{m.group(1)}{int(m.group(2)) + 1}')
") || exit 1
fi

if [ "$NEW" = "$CURRENT" ]; then
  echo "Error: new version ($NEW) is same as current ($CURRENT)" >&2
  exit 1
fi

if git rev-parse -q --verify "refs/tags/v$NEW" >/dev/null 2>&1; then
  echo "Error: tag v$NEW already exists" >&2
  exit 1
fi

echo "$CURRENT → $NEW"

python3 -c "
import re
path = '$MANIFEST'
text = open(path).read()
text = re.sub(
    r'^(version\s*=\s*\")([^\"]+)(\")',
    r'\g<1>$NEW\3',
    text,
    count=1,
    flags=re.M,
)
open(path, 'w').write(text)
"

git add "$MANIFEST"
git commit -m "chore: version bump to $NEW"
git tag "v$NEW"
git push --atomic origin HEAD "v$NEW"

if [ "${BUMP_NO_RELEASE:-0}" = "1" ]; then
  echo "Done: v$NEW pushed (release skipped via BUMP_NO_RELEASE=1)"
  exit 0
fi

if ! gh release create "v$NEW" --verify-tag --title "v$NEW" --generate-notes; then
  echo "Error: gh release create failed. Tag v$NEW is already on origin." >&2
  echo "Recover with: gh release create v$NEW --verify-tag --title v$NEW --generate-notes" >&2
  exit 1
fi

echo "Done: v$NEW released"
