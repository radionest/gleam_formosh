---
type: guide
title: "Quickstart"
description: "Install Formosh and render a validated form from a JSON Schema in five minutes."
---

# Quickstart

This guide takes you from zero to a running form in a Gleam / Lustre project.
If you want to use Formosh **without writing Gleam** (as a drop-in HTML
element), skip ahead to [Web Component](web-component.md).

## 1. Add the dependency

Formosh targets **JavaScript** and is **not yet published on Hex** — add it
as a path (or git) dependency. In your project's `gleam.toml`:

```toml
target = "javascript"

[dependencies]
gleam_stdlib = ">= 0.44.0 and < 2.0.0"
lustre = ">= 5.3.4 and < 6.0.0"
# clone https://github.com/radionest/gleam_formosh next to your project:
formosh = { path = "../gleam_formosh" }
```

(On Gleam versions with git-dependency support you can use
`formosh = { git = "https://github.com/radionest/gleam_formosh.git", ref = "<commit>" }`
instead — pin a commit `ref` to keep builds reproducible.)

Then download dependencies:

```bash
gleam deps download
```

> **Alpha note.** Formosh's API is still moving; a Hex release will come
> once it stabilizes (see `ROADMAP.md`). Until then, pin the checkout you
> tested against.

## 2. Write a schema

A JSON Schema (draft 2020-12) is the single source of truth for both the
form's shape and its validation. Drop one inline, or load it from a file /
API at runtime:

```gleam
const schema_json = "
{
  \"type\": \"object\",
  \"title\": \"Contact\",
  \"properties\": {
    \"name\":  { \"type\": \"string\", \"title\": \"Name\" },
    \"email\": { \"type\": \"string\", \"format\": \"email\" }
  },
  \"required\": [\"name\", \"email\"]
}"
```

See [Schema Keywords](../reference/schema-keywords.md) for everything
Formosh does with this schema (types, `format`, `required`, `$ref`,
`if/then/else`, arrays, etc.).

## 3. Render the form

Formosh returns a normal Lustre `App`. Start it on any DOM selector:

```gleam
import formosh
import gleam/io
import gleam/string
import lustre

pub fn main() {
  case formosh.from_json_string(schema_json) {
    Ok(app) -> {
      let assert Ok(_) = lustre.start(app, "#app", Nil)
      Nil
    }
    Error(err) -> io.println_error("formosh: schema parse error: " <> string.inspect(err))
  }
}
```

`from_json_string` parses the schema **and** builds the app with default
config (no submission handler, errors shown only after a field is touched,
readonly fields hidden). For anything beyond that, use the configuration
builder in the next section.

## 4. Configure (recommended)

The one-shot `from_json_string` is fine for demos, but real forms need
submission, initial values, and presentation tweaks. Use the builder:

```gleam
import formosh
import formosh/schema/parser
import formosh/schema/types
import gleam/dict
import lustre

pub fn main() {
  // Parse the schema once → typed JsonSchema you can reuse
  let assert Ok(schema) = parser.parse_schema(schema_json)

  let config =
    formosh.config(schema)
    |> formosh.with_submit_url("https://api.example.com/contacts")
    |> formosh.with_initial_values(dict.from_list([
      #("name", types.StringValue("Ada")),
    ]))

  let app = formosh.from_config(config)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
}
```

> `types.StringValue` is the `Value` variant for strings; the `Value` type
> and its constructors live in `formosh/schema/types` (Gleam has no
> re-exports, so import that module directly) — see
> [Public API](../reference/api.md) for the full `Value` type.

The full set of builders is covered in [Configuration](configuration.md);
the complete signatures live in [Public API](../reference/api.md).

## 5. Style it

Formosh ships with **no default CSS**. The component renders inside an open
Shadow DOM with `::part()` hooks for every styled element — the fastest way
to a usable form:

```css
formosh-form { display: block; max-width: 32rem; }
formosh-form::part(label) { font-weight: 600; }
formosh-form::part(submit){ background: #08a; color: white; padding: .5rem 1rem; }
formosh-form::part(error) { color: #d33; font-size: .85rem; }
```

See [Styling](styling.md) for the full part catalog and cascade rules.

## Common gotchas

- **`get_values` returns a `Value` tree, not a `Dict`.** This is a recent
  breaking change — older docs show `Dict(String, Value)`. To serialize,
  use `formosh/form/json_utils.value_to_json`; for typed access use
  `formosh/form/path.get_at_path`.
- **The schema must be valid JSON.** `from_json_string` returns
  `Error(ParseError)` for malformed JSON or an unsatisfiable schema
  (unknown keywords are ignored, not rejected); always handle the
  `Error` branch.
- **Target is JavaScript only.** There is no Erlang BEAM target — Lustre
  renders to the DOM.
- **No server-side validation substitute.** Formosh validates for UX, not
  for trust. Re-validate on the server.

## Where to next

- Submission modes and all config options → [Configuration](configuration.md)
- Use as `<formosh-form>` with no Gleam → [Web Component](web-component.md)
- Full function reference → [Public API](../reference/api.md)
