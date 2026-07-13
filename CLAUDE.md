# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Formosh is a JSON Schema-based form generator library for Gleam/Lustre that creates dynamic, type-safe forms using the Model-View-Update (MVU) architecture. It parses JSON Schema (draft 2020-12) and generates fully functional forms with validation.

## Worktree Workflow

- Feature development: always enter a worktree via `EnterWorktree` before making changes. Never `git checkout -b` on main — `block-branch-switch.sh` blocks it
- Code-architect / code-explorer / code-reviewer agents also require a worktree — `require-worktree-agent.sh` blocks them on main. Enter the worktree before Phase 2 of feature-dev, not after the architect agents fail
- If unstaged changes are already on main: `git stash` → `EnterWorktree` → `git stash pop`
- Edits under `.claude/` (hooks, settings, agents) — allowed directly on main; `require-worktree.sh` whitelists `.claude/*` and blocks `Edit`/`Write` elsewhere
- Worktrees contain only git-tracked files. `hooks/`, `settings.json`, `settings.local.json` live in `$CLAUDE_PROJECT_DIR/.claude/` and are shared
- Before `gh pr create`: `git fetch origin main` and check `git log --oneline main..origin/main` — if origin moved while the worktree was alive, rebase first or the diff will include unrelated reverts (`git-squash-sync.md` has the recipe)
- Before `gh pr create`: always run `Agent(subagent_type="pr-diff-reviewer", ...)` first. This is an advisory rule — no hook enforces it; the reviewer's report is the gate
- After `gh pr create` succeeds: `pr-monitor.sh` (PostToolUse Bash) auto-spawns `pr-watch.sh` in the background. CI report lands at `/tmp/pr-<N>-report.md` — read that file when the user asks about CI status, do not re-poll `gh pr checks`
- After `gh pr create` succeeds: default to `ExitWorktree(keep)` silently — do not ask. Worktree stays until PR merges
- `EnterWorktree(path)` borrows a worktree but does not own its lifecycle — `ExitWorktree(remove)` will refuse to delete it. Files placed outside git tracking (build artefacts, scratch dirs) are not cleaned up; remove them manually before exit
- `ExitWorktree(remove)` requires `discard_changes=true` if there are commits not in main
- Post-merge cleanup: `ExitWorktree(remove)` first, then `git pull --ff-only origin main`. Do not use `gh pr merge --delete-branch` while worktree exists — local branch deletion will fail
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

The `demo/` directory is a standalone Gleam project (`demo/gleam.toml`) that depends on the library via `formosh = { path = ".." }`. It mounts `<formosh-form>` and lets you click through all schemas in `demo/schemas/`. `make demo` runs `gleam run -m lustre/dev start` inside `demo/`.

## Architecture

The codebase strictly follows Model-View-Update separation:
- **Model** (`formosh/form/model.gleam`): Immutable state with path-based field addressing
- **Update** (`formosh/form/update.gleam`): Pure functions for all state transitions
- **View** (`formosh/form/view.gleam`): Declarative HTML generation

### Path-Based Field System
Critical for nested data handling — always use `path.gleam` utilities, never manual string concatenation:
```gleam
// Path segments: PropertySegment(name) or ArraySegment(index)
// Example: [PropertySegment("lesions"), ArraySegment(0), PropertySegment("side")] → lesions[0].side
to_string(path: FieldPath) -> String    // Convert to dot notation
get_field_name(path: FieldPath) -> String  // Extract final segment
```

Form values are stored as `Dict(String, Value)` with dot-notation keys (e.g. `"user.name"` → `StringValue("John")`). The same keys are used for `model.errors`.

Canonical key format is owned by `formosh/path_format.gleam` (`array_index_segment` + segment join rules). `path.to_string` delegates to it — treat `path_format.gleam` as the single source of truth and never re-implement the join elsewhere.

## Common Pitfalls

- **Paths**: Always use `path.gleam` utilities for nested fields, never string concatenation
- **Validation timing**: Check `touched_fields` before displaying errors
- **Array indexing**: Reindex array fields after any add/remove operation
- **Array reconcile (`defaults.ensure_min_items`)**: runs after every values recompute that precedes validation — init, reset, `UpdateFieldPath`, `ClearFieldPath`, `AddArrayItemPath`, `apply_answers`, component re-init — topping arrays up to `minItems`. Deliberately NOT run on `RemoveArrayItemPath`/`MoveArrayItemPath` or in `ValidateForm` (don't fight the user; validation reports under-min instead). New values-recompute paths must call it too
- **Circular $refs**: Resolver maintains visited set — do not bypass it
- **View refactors**: Required-asterisk (` *` with `class="required"`) and error wrappers are easy to drop when unifying renderers. Use `field_common.render_required_marker` and let the field dispatcher own error display — re-render the marker explicitly per container, not «implicitly via the parent»

## Web Component

Registers as `<formosh-form>` custom element. Attributes: `schema`, `ui-schema`, `submit-url`, `submit-method`, `show-readonly-fields`, `read-only`, `upload-base-url`. Emits events: `formosh-ready`, `formosh-submitting`, `formosh-submit`, `formosh-change`.

`read-only="true"` renders the whole form as a static label→value summary (review mode) instead of inputs, hiding Submit/Reset — distinct from `show-readonly-fields`, which only toggles visibility of schema `readOnly` fields in edit mode. Drives the `readonly_field` renderer (`src/formosh/fields/readonly_field.gleam`); exposes `::part(readonly-field|readonly-label|readonly-value|readonly-group|readonly-group-label|readonly-group-body|readonly-table|readonly-th|readonly-td)`.

Styling: the component runs in open Shadow DOM, so target it via `::part()` selectors (`formosh-form::part(input)`, etc.) and `[part=field][data-error]` / `[part=field][data-readonly]` / `[part=toggle][data-state=on]` for field state. Parent stylesheets are also auto-adopted, so plain `.formosh-input { ... }` rules still apply inside the shadow root.

## UiSchema

Presentation hints live in a parallel `UiSchema` (react-jsonschema-form-style JSON: `ui:widget`, `ui:order`, `ui:placeholder`, `ui:help`, `ui:autofocus`, `ui:disabled`, `ui:readonly`, `ui:title`, `ui:description`, `ui:options`, `ui:addable`, `ui:removable`, `ui:orderable`, `ui:accept`, `ui:maxFileSize`). Children are nested inline by field name; `items` is the array-element template. `lookup` (`formosh/schema/ui_resolver`) walks by `FieldPath` — `ArraySegment` ignores the index and descends into `items`.

- `x-widget` / `x-accept` / `x-max-file-size` / `x-addable` / `x-removable` extensions are **deprecated as of v0.7** and read as fallback only. They will be removed in **v0.9**. Use UiSchema instead.
- `ui:disabled` and `ui:readonly` **OR-merge** with the parent / schema. `ui:disabled: false` on a child of a disabled container does NOT re-enable it — mirrors HTML's `disabled` inheritance and JSON Schema's `readOnly`. To selectively enable, hoist the disabled flag to the leaf instead of the container.
- `ui:orderable` toggles the per-row ▲/▼ reorder buttons on an array (default `true`). Set `ui:orderable: false` to hide them. Buttons are disabled at the ends and hidden when the array has one item or fewer; controls expose classes `move-array-item-up` / `move-array-item-down`.
- `ui:accept` / `ui:maxFileSize` are only honoured when `ui:widget: "image-upload"` is set. Without the widget hint they are silently dropped (the `UploadConfig` is not emitted).

## Notes

- All `.mjs` files are auto-generated — do not read or edit them (except `src/formosh/ffi/*_ffi.mjs` which are hand-written FFI)
- `oneOf`/`anyOf` composition keywords are not yet implemented
- `x-widget: "image-upload"` works only on top-level properties; nested image-upload fields (inside objects/arrays) are not yet supported
- `x-widget: "hidden"` / `ui:widget: "hidden"` suppresses rendering at any depth; the field still validates and submits. Combine with JSON Schema `default` for `<input type="hidden">`-like behaviour. The default submit gate (`model.can_submit`) stays **strict** — a required hidden field without a satisfying value blocks submit. To surface the otherwise-invisible cause, a `console.warn` (via `ffi/console`) lists the suppressed-path errors whenever they are the *only* blockers. It is emitted from `component` at form (re)initialisation — the submit button is `disabled` in this state, so `FormSubmit` never fires through `<formosh-form>` — via `component.hidden_blocks_warn` wrapping `update.warn_only_hidden_blocks_effect`; `update.FormSubmit` emits the same warn for headless `model.init` embeddings that have no disabled-button gate. Visible errors keep the warn silent since the UI already explains the block. Callers that want a permissive gate (submit succeeds despite invisible required errors — e.g. the backend supplies the value) can read `model.is_valid_for_submit`. `model.hidden_errors` returns the suppressed slice for custom diagnostics. The same suppression set covers `readOnly` fields when `show_readonly_fields: false`. Walker lives in `formosh/form/visibility`; called on demand from `model.invisible_paths` so no `FormModel` field needs to track it
- HTTP submissions use the `rsvp` library for effect management
