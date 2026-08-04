---
type: concept
title: "Formosh overview"
description: "What Formosh is, the problem it solves, and the scope of its current alpha."
---

# Formosh overview

Formosh is a **JSON Schema form generator** for [Gleam](https://gleam.run) /
[Lustre](https://hexdocs.pm/lustre/). You describe your data with a JSON
Schema (draft 2020-12); Formosh renders a live, validated form from it and
hands you back a Lustre application you can mount anywhere.

## The problem

Forms and schemas drift. When the form is hand-written — field by field,
validator by validator — it becomes a second source of truth that has to be
kept in sync with the schema by hand. Every new field, every constraint
change, every rename is a place for the form and the schema to disagree.

Formosh collapses the two: the schema *is* the form definition. The same
artifact that documents your data also drives the inputs, the widgets, the
required-field checks, the conditional visibility, and the bounds
validation. Change the schema; the form follows.

## What Formosh gives you

- **A parser** that turns a JSON Schema string into a typed `JsonSchema`
  tree, resolving `$ref`, composing `allOf`, and normalizing unsatisfiable
  constraints up front.
- **A Lustre MVU application** that renders the schema as an interactive
  form, with one widget family per JSON type and automatic widget selection.
- **Validation** wired to the schema keywords — required fields, string
  length bounds, number bounds, array length bounds, and basic format
  checks (email, url).
- **Conditional fields** (`if`/`then`/`else`) that appear and disappear as
  the user edits the form.
- **Three ways to ship it**: as a Gleam library inside a Lustre app, as a
  standalone Web Component (`<formosh-form>`) with no Gleam required, or
  as a Lustre component embedded in a larger Lustre app.

## What Formosh is *not*

- **Not a full JSON Schema validator.** It implements the subset of the
  draft that maps cleanly onto form UI — see
  [Schema Keywords](../reference/schema-keywords.md) for the exact support
  matrix and the explicit list of what is parsed-but-not-validated or
  unsupported.
- **Not a backend.** Submission is pluggable: HTTP POST/PUT, a custom
  handler, or "none" (you read the values yourself). Formosh does not store
  anything.
- **Not a styling system.** The component ships with no default CSS. Bring
  your own via `::part()`, `data-*` attributes, or adopted parent
  stylesheets — see [Styling](../guides/styling.md).

## Alpha status

Formosh is published as an **alpha / learning project**. Concretely that
means:

- The public API **will** change between minor versions. `get_values`, for
  example, recently switched from returning `Dict(String, Value)` to
  returning a `Value` tree. Expect more of this.
- Some JSON Schema keywords are parsed but not enforced (e.g. `uuid` and
  custom `format` values, polymorphic `oneOf` schema variants), and the
  `email` / `url` checks are lax substring tests. Don't rely on Formosh as
  your only line of defense — validate on the server too.
- The set of supported schema features is deliberately small but growing.
  The [Schema Keywords](../reference/schema-keywords.md) page is the source
  of truth for what works today.

## Where to go next

- **Use it** → [Quickstart](../guides/quickstart.md)
- **Understand the shape of the code** → [Architecture](architecture.md)
- **Read the API** → [Public API](../reference/api.md)
