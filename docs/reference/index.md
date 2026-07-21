# Reference

Lookup material — exact signatures and support matrices. Read top-to-bottom
only if you're auditing coverage; otherwise jump to what you need.

* [Public API](api.md) — every `formosh.*` and `component.*` function plus the public types (`JsonSchema`, `Value`, `FormConfig`, …).
* [Schema Keywords](schema-keywords.md) — JSON Schema (draft 2020-12) support matrix: what's parsed, what's validated, what's ignored.
* [UiSchema](ui-schema.md) — the parallel JSON tree that controls presentation: every `ui:*` key, widget overrides, field ordering, array controls.
* [Widget Selection](widgets.md) — how a schema node becomes a concrete widget (text input, textarea, radio, select, table, swipe-review…).

If you're new and looking for *how to use* the API rather than just its
shape, start with the [Guides](../guides/index.md) and come back here for
the details.
