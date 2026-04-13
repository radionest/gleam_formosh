Bump the project version, commit, tag, and push.

## Usage

- `/bump` — auto-increment patch (0.2.3 → 0.2.4)
- `/bump 0.3.0` — set explicit version

## Instructions

1. You MUST be on the `main` branch with a clean working tree. If in a worktree — exit first.
2. Run: `bash scripts/bump.sh $ARGUMENTS`
3. Report the result to the user.

Do NOT use Edit/Write tools — the script handles everything via sed + git.
