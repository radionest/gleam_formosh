# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project Overview

Formosh is a JSON Schema-based form generator library for Gleam/Lustre that creates dynamic, type-safe forms using the Model-View-Update (MVU) architecture. It parses JSON Schema (draft 2020-12) and generates fully functional forms with validation.

## Documentation

`docs/` (OKF bundle) is the **single source of truth** for library behaviour — this file and `.zcode/rules/` only summarize and link. Start at `docs/index.md`; the per-topic map lives in `.zcode/rules/docs.md`. When a change alters behaviour described in `docs/`, update the affected page in the same PR. Planned work and known API debts live in `ROADMAP.md`.

## Topic digests (`.zcode/rules/`)

The detailed invariants this file used to inline now live in per-topic digests — read the relevant one on demand:

| Digest | Covers |
|---|---|
| `arrays.md` | Array reconcile (`ensure_min_items`), reindex rule, collapse-state invariants |
| `schema-composition.md` | Parse-time `allOf`/`anyOf` merge rules and strictness; retired `x-*` keys |
| `unions.md` | Runtime `anyOf` branch selection, switching, inference persistence |
| `ui-schema.md` | `ui:*` key semantics (OR-merge, orderable, collapseCompleted, layout, accept/maxFileSize) |
| `web-component.md` | `<formosh-form>` surface, review mode, styling rules (`::part`, `@layer formosh`, inline-style policy) |
| `hidden-fields.md` | Hidden/readOnly suppression, the strict submit gate, warn sites |
| `error-pipeline.md` | How validation errors reach the DOM (touch gate) |
| `rendering.md` | Widget-choice rules for field renderers |
| `decoder-patterns.md` / `ffi-patterns.md` | Schema decoding / JS FFI conventions |
| `generated-files.md` | What is auto-generated (never edit) |
| `docs.md` | The docs map |

## Worktree Workflow

- Feature development: always enter a worktree via `EnterWorktree` before making changes. Never `git checkout -b` on main — `block-branch-switch.sh` blocks it. Code-architect / code-explorer / code-reviewer agents also require a worktree (`require-worktree-agent.sh`) — enter it before Phase 2 of feature-dev, not after the architect agents fail
- If unstaged changes are already on main: `git stash` → `EnterWorktree` → `git stash pop`
- Edits under `.zcode/` (config, hooks, rules) — allowed directly on main; `require-worktree.sh` whitelists `.zcode/*` (and the legacy `.claude/*`) and blocks `Edit`/`Write` elsewhere
- Worktrees contain only git-tracked files. `.zcode/` (config.json, hooks, rules) is tracked, so a fresh worktree gets the full hook setup
- Before `gh pr create`: `git fetch origin main` and check `git log --oneline main..origin/main` — if origin moved while the worktree was alive, rebase first or the diff will include unrelated reverts (the `block-branch-switch` hook injects the squash-merge recipe as context). Always run `Agent(subagent_type="pr-diff-reviewer", ...)` first — advisory, no hook enforces it; the reviewer's report is the gate
- After `gh pr create` succeeds: `pr-monitor.sh` (PostToolUse Bash) auto-spawns `pr-watch.sh` in the background. CI report lands at `/tmp/pr-<N>-report.md` — read that file when the user asks about CI status, do not re-poll `gh pr checks`. Default to `ExitWorktree(keep)` silently — do not ask; the worktree stays until the PR merges
- `EnterWorktree(path)` borrows a worktree but does not own its lifecycle — `ExitWorktree(remove)` will refuse to delete it. Files placed outside git tracking (build artefacts, scratch dirs) are not cleaned up; remove them manually before exit. `ExitWorktree(remove)` requires `discard_changes=true` if there are commits not in main
- Post-merge cleanup: `ExitWorktree(remove)` first, then `git pull --ff-only origin main`. Do not use `gh pr merge --delete-branch` while a worktree exists — local branch deletion will fail
- The Stop hook blocks session end in a worktree — ask the user to choose:
  1. **Push + PR**: commit all → `git push -u origin <branch>` → run `pr-diff-reviewer` → `gh pr create` → `ExitWorktree(keep)`
  2. **Keep**: `ExitWorktree(keep)` — worktree stays for later
  3. **Discard**: `ExitWorktree(remove, discard_changes=true)`

## Essential Commands

```bash
# Install dependencies
gleam deps download

# Build the project
gleam build

# Run tests (gleeunit always runs every *_test.gleam in test/ — no per-module filter)
gleam test

# Format code (ALWAYS run before committing)
gleam format

# Build CDN bundle (cdn.min.mjs) for production
npm run build

# Run interactive demo (port 1234) — picks a JSON Schema, renders it with <formosh-form>
make demo

# Run echo test_server.py for form submission (port 8888)
make demo-server
```

`demo/` is a standalone Gleam project (`demo/gleam.toml`, depends on the library via `formosh = { path = ".." }`): it mounts `<formosh-form>` and lets you click through all schemas in `demo/schemas/`, then edit the schema, ui-schema and form stylesheet live. The stylesheet editor is seeded from `demo/form-theme.css`, which holds every form rule — a new form style goes there, and the Pages workflow copies it into the site; `index.html` keeps the page chrome plus the palette variables and fonts the theme uses. `make demo` runs `gleam run -m lustre/dev start` inside `demo/`.

## Architecture

The codebase strictly follows Model-View-Update separation:
- **Model** (`formosh/form/model.gleam`): Immutable state with path-based field addressing
- **Update** (`formosh/form/update.gleam`): Pure functions for all state transitions
- **View** (`formosh/form/view.gleam`): Declarative HTML generation

**Paths** — critical for nested data handling; always use `form/path.gleam` utilities, never manual string concatenation. Segments are `PropertySegment(name)` / `ArraySegment(index)`, e.g. `[PropertySegment("lesions"), ArraySegment(0), PropertySegment("side")]` → `lesions.[0].side`. Form values live in `model.values` as a single hierarchical `Value` tree (always `ObjectValue` at the root); read/write via `path.get_at_path` / `path.set_at_path`, never a Dict↔Value conversion. `model.errors` is keyed by dot-notation strings produced by `path.to_string` (e.g. `"lesions.[0].side"`); `path.get_field_name` extracts a path's final segment.

Canonical key format is owned by `formosh/path_format.gleam` (`array_index_segment` + segment join rules). `path.to_string` delegates to it — treat `path_format.gleam` as the single source of truth and never re-implement the join elsewhere.

## Common Pitfalls

- **Paths**: always use `form/path.gleam` utilities for nested fields, never string concatenation
- **Validation timing**: check `touched_fields` before displaying errors (gate details: `.zcode/rules/error-pipeline.md`)
- **Array indexing**: reindex array fields after any add/remove — and every path-keyed model list with them (invariants: `.zcode/rules/arrays.md`)
- **Circular $refs**: the resolver maintains a visited set — do not bypass it
- **View refactors**: the required-asterisk (` *` with `class="formosh-required"`) and error wrappers are easy to drop when unifying renderers. Use `field_common.render_required_marker` and let the field dispatcher own error display — re-render the marker explicitly per container, not «implicitly via the parent»

## Web Component

Registers as `<formosh-form>` custom element. Attributes: `schema`, `ui-schema`, `submit-url`, `submit-method`, `initial-values`, `show-readonly-fields`, `read-only`, `upload-base-url`. Emits events: `formosh-ready`, `formosh-submitting`, `formosh-submit`, `formosh-change`. Full guide: `docs/guides/web-component.md`; surface, review mode and styling rules: `.zcode/rules/web-component.md`.

## UiSchema

Presentation hints live in a parallel `UiSchema` (react-jsonschema-form-style `ui:*` JSON) — the only hint source since v0.11. Full reference: `docs/reference/ui-schema.md`; key semantics: `.zcode/rules/ui-schema.md`; parse-time `allOf`/`anyOf` handling: `.zcode/rules/schema-composition.md`; runtime union branches: `.zcode/rules/unions.md`.

## Notes

- All `.mjs` files are auto-generated — do not read or edit them (exceptions: `.zcode/rules/generated-files.md`)
- `ui:widget: "image-upload"` works only on top-level properties; nested image-upload fields (inside objects/arrays) are not yet supported
- An array with `uniqueItems: true` whose scalar `items` carry options (`enum` of 2+ values / `oneOf` const+title) renders as a checkbox group (`types.is_multi_select` → `string_field.render_checkboxes`); `uniqueItems` is validated on every array. See `docs/reference/widgets.md#checkbox-group-multi-select`
- `ui:widget: "hidden"` fields still validate and submit; the submit gate stays strict — `.zcode/rules/hidden-fields.md`
- HTTP submissions use the `rsvp` library for effect management
