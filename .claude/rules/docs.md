# Documentation is the source of truth

`docs/` (OKF bundle) is the single source of truth for library behaviour.
CLAUDE.md and these rules only summarize — when they disagree with `docs/`,
trust `docs/`. When a code change alters behaviour described in `docs/`,
update the affected page in the same PR.

| Topic | Page |
|-------|------|
| What Formosh is, alpha scope | `docs/concepts/overview.md` |
| MVU layering, module map of `src/` | `docs/concepts/architecture.md` |
| Install + first form (Gleam) | `docs/guides/quickstart.md` |
| `FormConfig` builders, submission, cross-field validator | `docs/guides/configuration.md` |
| `<formosh-form>` attributes + events | `docs/guides/web-component.md` |
| `::part()` catalog, `data-*` state, cascade | `docs/guides/styling.md` |
| Public functions, types, imports cheat-sheet | `docs/reference/api.md` |
| JSON Schema keyword support matrix | `docs/reference/schema-keywords.md` |
| `ui:*` keys, merge precedence with `x-*` | `docs/reference/ui-schema.md` |
| Widget decision tree + overrides | `docs/reference/widgets.md` |
| Maintainer internals (stubs) | `docs/internals/` |

Features deliberately absent from the API (do not document them as existing)
are tracked in `ROADMAP.md` under «Долги API».
