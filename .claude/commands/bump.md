Bump the project version, commit, tag, push, and create a GitHub Release.

## Usage

- `/bump` — auto-increment patch (0.2.3 → 0.2.4)
- `/bump 0.3.0` — set explicit version

## Instructions

1. You MUST be on the `main` branch with a clean working tree. If in a worktree — exit first.
2. `gh` CLI must be installed and authenticated (`gh auth status`). To push only the tag without creating the GitHub Release, set `BUMP_NO_RELEASE=1`.
3. Run: `bash scripts/bump.sh $ARGUMENTS`
4. Report the result. If the script exits after the tag push because `gh release create` failed, surface the recovery command it printed — the tag is already on origin and only the release step needs retry.

Do NOT use Edit/Write tools — the script handles everything via sed + git.
