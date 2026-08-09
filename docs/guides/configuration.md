---
type: guide
title: "Configuration"
description: "The FormConfig builder: submission modes, error visibility, readonly fields, initial values, UiSchema, and cross-field validation."
---

# Configuration

`from_json_string` is the zero-config path. Real forms need a submission
endpoint, initial values, presentation tweaks, and rules JSON Schema can't
express. All of that flows through one builder type: `FormConfig`.

The pattern is always the same — **parse once, configure, start:**

```gleam
import formosh
import formosh/schema/parser

let assert Ok(schema) = parser.parse_schema(schema_json)

let app =
  formosh.config(schema)               // start with defaults
  |> formosh.with_submit_url("...")    // chain any with_* builders
  |> formosh.from_config()             // close the chain into a Lustre App

lustre.start(app, "#app", Nil)
```

`formosh.config(schema)` returns a `FormConfig` with defaults:

| Field | Default |
|-------|---------|
| `submit_config` | `NoSubmit` (read values manually) |
| `show_errors_on_change` | `False` — **currently a no-op**, see [Error visibility](#error-visibility) |
| `show_readonly_fields` | `False` (`readOnly` fields hidden) |
| `initial_values` | empty dict |
| `ui_schema` | empty UiSchema |
| `validator` | `None` |

Each `with_*` builder returns a new `FormConfig` with one field changed, so
you can chain them in any order.

## Submission modes

Pick exactly one of the three. `NoSubmit` (the default) is a valid choice —
it just means the form won't POST anywhere on its own.

### HTTP POST/PUT — `with_submit_url` / `with_http_submit`

```gleam
// Shorthand: POST with Content-Type: application/json
formosh.with_submit_url(config, "https://api.example.com/forms")

// Full control: method + headers
formosh.with_http_submit(config, "https://api.example.com/forms", "PUT", [
  #("Authorization", "Bearer token123"),
  #("Content-Type", "application/json"),
])
```

The current values tree is serialized to JSON and sent as the request body.
The response body becomes the success message shown in the form; an HTTP
error becomes the error message.

### Custom handler — `with_custom_submit`

For anything other than a plain HTTP call — multiple calls, side effects,
transforming the payload, talking to a store — provide a function:

```gleam
formosh.with_custom_submit(config, fn(model) {
  let values = formosh.get_values(model)   // Value tree (ObjectValue at root)
  case my_api.upsert(values) {
    Ok(_)    -> Ok("Saved")
    Error(_) -> Error("Something went wrong")
  }
})
```

The handler receives the full `FormModel` and returns
`Result(String, String)` — the `Ok` / `Error` string is shown as the
success / error message.

### None — read values yourself

The default (`NoSubmit`). Use this when the parent application owns
submission. Read values from the model whenever you need them:

```gleam
import formosh/schema/types

let values: types.Value = formosh.get_values(model)
```

> **API note.** `get_values` used to return `Dict(String, Value)`; it now
> returns the `Value` tree directly (always `ObjectValue` at the root).
> Use `formosh/form/path.get_at_path` for typed access, or
> `formosh/form/json_utils.value_to_json` to serialize.

## Error visibility

Errors are gated by **touch tracking**: a field's validation error stays
hidden until the user interacts with that field (touches it). This avoids
a wall of red on first paint.

> **`with_show_errors_on_change` is currently a no-op.** The builder stores
> the flag on `FormConfig`, but `create_form_with_config` never forwards it
> to the model and nothing reads it — behaviour is always "errors after
> touch". Tracked in `ROADMAP.md`.

The one exception to the touch gate is **array-length violations**: an array
that violates `minItems` / `maxItems` (e.g. from externally supplied values)
is always shown, because the gating buttons can't cause it and the message
is the only explanation for a blocked submit. See the README "Arrays"
section for the full rule.

## Read-only fields

```gleam
|> formosh.with_show_readonly_fields(True)
```

By default, schema properties marked `readOnly: true` are **hidden**.
Enable this to render them as disabled inputs instead. Common pattern:
display a server-generated `patient_id` or `created_at` that the user can
see but not edit.

There is a separate flag for **review mode** (render the whole form as a
static summary) — the web-component's `read-only` attribute; it has no
library-side builder — see [Web Component](web-component.md).

## Initial values

```gleam
import formosh/schema/types
import gleam/dict

|> formosh.with_initial_values(dict.from_list([
  #("patient_id", types.StringValue("12345")),
  #("study_date", types.StringValue("2024-01-15")),
  #("active", types.BooleanValue(True)),
]))
```

Pre-populates the form. The keys are top-level property names; the values
are `Value` variants (`StringValue`, `NumberValue`, `IntegerValue`,
`BooleanValue`, `ObjectValue`, `ArrayValue`, `NullValue`) from
`formosh/schema/types`. Initial values flow through the
same default-hydration pipeline as schema `default` values, so arrays are
topped up to `minItems` and conditionals are resolved against them.

## UiSchema (presentation hints)

JSON Schema describes your data. UiSchema describes how to **present** it —
widget choice, field order, placeholders, help text — without polluting the
data schema. Attach a parsed UiSchema:

```gleam
|> formosh.with_ui_schema(ui)
```

…or parse one inline from JSON (returns `Error(ParseError)` on bad input):

```gleam
let assert Ok(config) =
  formosh.with_ui_schema_json(config, ui_schema_json_string)
```

The full list of `ui:*` keys (`ui:widget`, `ui:order`, `ui:layout`,
`ui:placeholder`, `ui:help`, `ui:addable`, `ui:removable`, `ui:accept`, …),
the JSON tree shape, merge precedence with `x-*` extensions, and three
worked examples are in [UiSchema](../reference/ui-schema.md). The short
version: it
mirrors your schema's shape, `ui:*` keys are settings on the current node,
`items` is the array-row template, every other key is a child property.

## Cross-field validation — `with_validator`

JSON Schema can't express rules like "sum of category budgets ≤ total
budget" or "end date must be after start date". For those, attach a
cross-field validator:

```gleam
import formosh/form/model.{type FormModel}
import formosh/form/path.{PropertySegment}
import formosh/validation/error.{ValidationError}

fn check_budget(m: FormModel) -> List(ValidationError) {
  case sum_categories(m) > total_budget(m) {
    True -> [ValidationError(
      field: [PropertySegment("total_budget")],
      message: "Sum of categories exceeds total",
      rule: "custom",
    )]
    False -> []
  }
}

// ...
|> formosh.with_validator(check_budget)
```

Behavior worth knowing:

- **Runs on every value change** once the user has touched at least one
  field. (It's skipped while `touched_fields` is empty so pre-touch errors
  don't invisibly block submit.)
- **Schema errors take precedence.** If a field already has a schema error,
  the cross-field error for the same field is suppressed until the schema
  error clears.
- **Errors on unknown paths are dropped** (with a console warning) — make
  sure your `field:` path actually exists in the schema. "Exists" is checked
  against an array's raw `items` template, not against each row's own
  resolved conditionals, so an error keyed on a path that only a per-row
  `if`/`then` reveals is dropped even though that row really does have the
  field — see [Collapsing completed
  rows](../reference/widgets.md#collapsing-completed-rows).
- **Cost.** The validator runs on every keystroke. If yours serializes the
  whole tree to JSON or calls an expensive JS function, mind the perf.

The web component exposes this via a `validator` JS property — see
[Web Component](web-component.md).

## Putting it together

```gleam
import formosh
import formosh/schema/parser
import formosh/schema/types
import gleam/dict
import lustre

pub fn main() {
  let assert Ok(schema) = parser.parse_schema(schema_json)

  let app =
    formosh.config(schema)
    |> formosh.with_http_submit("https://api.example.com/forms", "POST", [
      #("Authorization", "Bearer " <> token),
    ])
    |> formosh.with_show_readonly_fields(True)
    |> formosh.with_initial_values(dict.from_list([
      #("patient_id", types.StringValue("12345")),
    ]))
    |> formosh.with_validator(check_budget)
    |> formosh.from_config()

  let assert Ok(_) = lustre.start(app, "#app", Nil)
}
```

## Reference

Full signatures for every builder above → [Public API](../reference/api.md).
