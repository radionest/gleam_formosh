---
type: reference
title: "Public API"
description: "Every formosh.* and component.* public function and type, with signatures and links into source."
---

# Public API

The public surface of Formosh is intentionally small. Almost everything you
touch lives in two modules: `formosh` (the library entry point, used inside
Lustre apps) and `formosh/component` (the web component + Lustre component
helper). The types you'll reference live in `formosh/schema/types`.

## Construction

`formosh.*` — turning a schema into a Lustre `App`.

```gleam
// One-shot: JSON string → App. Default config (no submit, errors on blur).
formosh.from_json_string(json_string: String)
  -> Result(lustre.App(Nil, FormModel, FormMsg), ParseError)

// One-shot with explicit submit config.
formosh.from_json_string_with_config(
  json_string: String,
  submit_config: SubmitConfig,
) -> Result(lustre.App(Nil, FormModel, FormMsg), ParseError)

// From an already-parsed JsonSchema.
formosh.from_schema(schema: JsonSchema) -> lustre.App(Nil, FormModel, FormMsg)

// From a fully-built FormConfig (the recommended path).
formosh.from_config(config: FormConfig) -> lustre.App(Nil, FormModel, FormMsg)
```

> **Parsing.** If you want to inspect or reuse the parsed schema before
> building a config, call `formosh/schema/parser.parse_schema` directly —
> the `from_json_string*` helpers do this internally and throw the schema
> away.

## Configuration

`formosh.*` — the `FormConfig` builder. `config/1` starts the chain; every
`with_*` returns a new config; `from_config/1` closes the chain.

```gleam
formosh.config(schema: JsonSchema) -> FormConfig

// Submission (pick one)
formosh.with_submit_url(config, url: String) -> FormConfig
formosh.with_http_submit(
  config, url: String, method: String, headers: List(#(String, String))
) -> FormConfig
formosh.with_custom_submit(
  config, handler: fn(FormModel) -> Result(String, String)
) -> FormConfig

// Presentation
formosh.with_show_errors_on_change(config, show: Bool) -> FormConfig
formosh.with_show_readonly_fields(config, show: Bool) -> FormConfig
formosh.with_initial_values(config, values: Dict(String, Value)) -> FormConfig

// UiSchema (presentation hints)
formosh.with_ui_schema(config, ui_schema: UiSchema) -> FormConfig
formosh.with_ui_schema_json(config, json_string: String)
  -> Result(FormConfig, ParseError)
formosh.parse_ui_schema(json_string: String) -> Result(UiSchema, ParseError)

// Cross-field validation
formosh.with_validator(
  config, validator: fn(FormModel) -> List(ValidationError)
) -> FormConfig
```

See [Configuration](../guides/configuration.md) for prose on each, and
[Schema Keywords](schema-keywords.md) for what the schema-driven validation
covers. Cross-field validation semantics (precedence, gating, cost) are
spelled out in the `with_validator` doc comment in
`src/formosh.gleam:212-259`.

## Reading form state

```gleam
// The full value tree. Always ObjectValue at the root.
formosh.get_values(model: FormModel) -> Value
```

> **Breaking change.** Earlier versions returned `Dict(String, Value)`.
> The model now stores a single `Value`; this returns it directly. Use
> `formosh/form/path.get_at_path` for typed access at a path, or
> `formosh/form/json_utils.value_to_json` to serialize.

## Web component

`formosh/component.*` — for the custom-element deployment.

```gleam
// Register <formosh-form> in the global custom-elements registry.
component.register() -> Result(Nil, lustre.Error)

// Embed inside a Lustre view without attribute ceremony.
component.element(attributes: List(Attribute(msg))) -> Element(msg)
```

Attribute helpers (each returns an `Attribute(msg)` and maps one-to-one to
an HTML attribute on `<formosh-form>`):

| Helper | HTML attribute | Maps to |
|--------|----------------|---------|
| `component.schema(JsonSchema)` | `schema` | serialized schema |
| `component.schema_string(String)` | `schema` | raw JSON string |
| `component.submit_url(String)` | `submit-url` | `with_submit_url` |
| `component.submit_method(String)` | `submit-method` | method of HTTP submit |
| `component.initial_values_string(String)` | `initial-values` | `with_initial_values` |
| `component.show_readonly_fields(Bool)` | `show-readonly-fields` | `with_show_readonly_fields` |
| `component.read_only(Bool)` | `read-only` | review mode |
| `component.upload_base_url(String)` | `upload-base-url` | image upload base |
| `component.ui_schema_string(String)` | `ui-schema` | `with_ui_schema_json` |
| `component.on_submit(fn(Dict) -> msg)` | — | `formosh-submit` listener |
| `component.on_change(fn(Dict) -> msg)` | — | `formosh-change` listener |

See [Web Component](../guides/web-component.md) for the attribute table and
custom-event detail shapes.

## Public types

Defined in `formosh/schema/types.gleam` — import that module to use them
(see the [imports cheat-sheet](#imports-cheat-sheet) at the bottom).

### `Value` — the form data type

A single sum type represents every value a schema or form field can hold:

```gleam
pub type Value {
  StringValue(String)
  NumberValue(Float)
  IntegerValue(Int)
  BooleanValue(Bool)
  NullValue
  ArrayValue(List(Value))
  ObjectValue(List(#(String, Value)))   // order-preserving
}
```

`ObjectValue` carries a `List` of pairs, **not** a `Dict` — field order
matters for rendering and must round-trip through serialization.

### `FieldType` — JSON Schema primitive types

```gleam
pub type FieldType {
  StringType
  NumberType
  IntegerType
  BooleanType
  ArrayType
  ObjectType
  NullType
}
```

### `StringFormat`

```gleam
pub type StringFormat {
  DateFormat
  DateTimeFormat
  TimeFormat
  EmailFormat
  UriFormat
  UrlFormat
  UuidFormat
  CustomFormat(String)
}
```

Maps to the HTML input `type` attribute in `string_field.get_input_type`
(`EmailFormat` → `email`, `UrlFormat`/`UriFormat` → `url`, `DateFormat` →
`date`, `TimeFormat` → `time`, `DateTimeFormat` → `datetime-local`;
`UuidFormat` and `CustomFormat` fall back to `text`).

> **Reachability caveat.** The parser's `format_decoder` only ever produces
> `EmailFormat`, `UrlFormat`, `UuidFormat`, and `CustomFormat` — the
> date/time variants are currently unreachable from a parsed schema, so
> `format: "date"` renders as a plain text input (see `ROADMAP.md`).

### `Widget` — widget overrides

```gleam
pub type Widget {
  ImageUploadWidget
  HiddenWidget
  SwipeReviewWidget
  CustomWidget(String)   // e.g. "textarea", "select", "radio"
}
```

Driven by `ui:widget` in UiSchema (primary) and `x-widget` on the schema
node (deprecated fallback). See [Widget Selection](widgets.md).

### `JsonSchema` and `SchemaProperty`

The parsed schema tree. `JsonSchema` is the root; `SchemaProperty` is one
field. Full field lists in `src/formosh/schema/types.gleam:138-230` — the
relevant highlights:

- `SchemaProperty` carries `field_type`, `title`, `description`, `default`,
  `enum_values`, `one_of`, `ref`, the three constraint records, `items`,
  `properties` (order-preserving), `required`, `read_only`, `addable`,
  `removable`, `render_hints`, and `conditionals`.
- `JsonSchema` adds the root-level `defs` (`$defs` / `definitions`),
  root `conditionals`, and root `all_of` (always `None` after parsing).

You normally don't construct these by hand — you parse them from JSON and
mutate via the builder. But if you want to synthesize a schema
programmatically, `types.empty_property()` and `types.empty_hints()` give
you the defaults.

### `FormConfig`

The builder state. Fields mirror the `with_*` functions:

```gleam
pub type FormConfig {
  FormConfig(
    schema: JsonSchema,
    submit_config: SubmitConfig,
    show_errors_on_change: Bool,
    show_readonly_fields: Bool,
    initial_values: Dict(String, Value),
    ui_schema: UiSchema,
    validator: Option(Validator(FormModel)),
  )
}
```

`SubmitConfig` is defined in `formosh/form/model` and has three
variants: `NoSubmit`, `HttpSubmit(url, method, headers)`,
`CustomSubmit(handler)`.

### `UiSchema` and `UiProperty`

Presentation hints parallel to the JSON Schema. See the full field list in
`src/formosh/schema/ui_schema.gleam` — every field is an optional override
(widget, options, order, placeholder, help, autofocus, disabled, readonly,
title, description, addable, removable, orderable, upload, properties,
items).

### `ValidationError`

```gleam
// from formosh/validation/error
pub type ValidationError {
  ValidationError(field: FieldPath, message: String, rule: String)
}
```

`field` is a `FieldPath` (`List(PathSegment)`) — `PropertySegment(String)`
for object keys, `ArraySegment(Int)` for array indices. Produced by both
schema validation and custom validators.

### `ParseError`

```gleam
pub type ParseError {
  InvalidJson(String)
  MissingField(String)
  InvalidType(String)
  UnexpectedValue(String)
  DecodingError(List(decode.DecodeError))
  UnsatisfiableSchema(String)   // #/path/to/node breadcrumb in message
}
```

`UnsatisfiableSchema` is returned when an `allOf` composition validates
nothing — conflicting `type`s or crossed bounds — rather than silently
producing a schema that rejects everything.

## Imports cheat-sheet

Gleam has no re-export mechanism, so — apart from `formosh.ParseError`,
which is a type **alias** defined in `src/formosh.gleam` — every type and
constructor must be imported from its defining module. `formosh.StringValue`
or `formosh.FormModel` will **not** compile:

| You need | Import |
|----------|--------|
| `Value` + constructors (`StringValue`, …), `JsonSchema`, `Widget`, `StringFormat`, `ParseError` | `formosh/schema/types` |
| `FormModel`, `FormMsg`, `SubmitConfig` (`NoSubmit`, `HttpSubmit`, `CustomSubmit`) | `formosh/form/model` |
| `FieldPath`, `PropertySegment`, `ArraySegment`, `get_at_path` | `formosh/form/path` |
| `ValidationError` | `formosh/validation/error` |
| `UiSchema` | `formosh/schema/ui_schema` |
| `value_to_json` | `formosh/form/json_utils` |

(Ergonomic wrapper constructors on the root module are a candidate
improvement — see `ROADMAP.md`.)
