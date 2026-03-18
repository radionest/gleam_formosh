# Formosh

JSON Schema form generator for Gleam. Parses JSON Schema (draft 2020-12) and renders dynamic forms using [Lustre](https://hexdocs.pm/lustre/) MVU architecture.

> **Alpha / learning project.** API is unstable and will change. Use at your own risk.

## Installation

```toml
[dependencies]
formosh = ">= 0.2.0"
```

## Quick Start

```gleam
import formosh
import lustre

pub fn main() {
  let schema = "
  {
    \"type\": \"object\",
    \"title\": \"Contact\",
    \"properties\": {
      \"name\": { \"type\": \"string\", \"title\": \"Name\" },
      \"email\": { \"type\": \"string\", \"format\": \"email\" }
    },
    \"required\": [\"name\", \"email\"]
  }"

  let assert Ok(app) = formosh.from_json_string(schema)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
}
```

## Configuration

Builder pattern for customizing form behavior:

```gleam
import formosh
import formosh/schema/parser

let assert Ok(schema) = parser.parse_schema(json_string)

let app = formosh.config(schema)
  |> formosh.with_submit_url("https://api.example.com/submit")
  |> formosh.with_css_prefix("my-form")
  |> formosh.with_show_errors_on_change(True)
  |> formosh.with_show_readonly_fields(True)
  |> formosh.with_initial_values(dict.from_list([
    #("patient_id", StringValue("12345")),
  ]))
  |> formosh.from_config()

let assert Ok(_) = lustre.start(app, "#app", Nil)
```

### Submission options

**HTTP POST/PUT:**

```gleam
formosh.config(schema)
  |> formosh.with_http_submit(
    "https://api.example.com/forms",
    "POST",
    [#("Authorization", "Bearer token123"), #("Content-Type", "application/json")]
  )
```

**Custom handler:**

```gleam
formosh.config(schema)
  |> formosh.with_custom_submit(fn(model) {
    let values = formosh.get_values(model)
    // your logic
    Ok("Done")
  })
```

**No submission** (default) — read values manually via `formosh.get_values(model)`.

## Web Component

Use as a custom HTML element without writing Gleam:

```html
<script type="module">
  import { register } from "./build/dev/javascript/formosh/formosh/component.mjs";
  register();
</script>

<formosh-form
  schema='{"type": "object", "properties": {"name": {"type": "string"}}}'
  submit-url="https://api.example.com/submit"
  submit-method="POST"
  css-prefix="my-form"
  initial-values='{"name": "John"}'>
</formosh-form>

<script>
  const form = document.querySelector('formosh-form');
  form.addEventListener('formosh-change', (e) => {
    console.log('Values:', e.detail.values);
    console.log('Valid:', e.detail.isValid);
  });
  form.addEventListener('formosh-submit', (e) => {
    console.log('Submitted:', e.detail);
  });
</script>
```

Events: `formosh-ready`, `formosh-change`, `formosh-submitting`, `formosh-submit`.

Or use inside a Lustre app programmatically:

```gleam
import formosh/component

// After component.register()
component.element([
  component.schema(my_schema),
  component.submit_url("https://api.example.com/submit"),
  component.on_change(HandleFormChange),
])
```

## Schema Examples

### Nested objects

```json
{
  "type": "object",
  "properties": {
    "address": {
      "type": "object",
      "title": "Address",
      "properties": {
        "street": { "type": "string" },
        "city": { "type": "string" }
      },
      "required": ["street", "city"]
    }
  }
}
```

### Arrays with add/remove

```json
{
  "type": "object",
  "properties": {
    "skills": {
      "type": "array",
      "title": "Skills",
      "items": {
        "type": "object",
        "properties": {
          "name": { "type": "string", "title": "Skill" },
          "level": {
            "type": "string",
            "enum": ["Beginner", "Intermediate", "Advanced", "Expert"]
          }
        }
      }
    }
  }
}
```

### Conditional fields (if/then/else)

Fields appear/disappear based on other field values:

```json
{
  "type": "object",
  "properties": {
    "hasLicense": { "type": "boolean", "title": "Do you have a license?" }
  },
  "if": {
    "properties": { "hasLicense": { "const": true } }
  },
  "then": {
    "properties": {
      "licenseNumber": { "type": "string", "title": "License Number" },
      "expiryDate": { "type": "string", "format": "date", "title": "Expiry Date" }
    },
    "required": ["licenseNumber"]
  }
}
```

Also supports multiple conditionals via `allOf`:

```json
{
  "allOf": [
    {
      "if": { "properties": { "type": { "const": "company" } } },
      "then": { "properties": { "companyName": { "type": "string" } } }
    },
    {
      "if": { "properties": { "type": { "const": "individual" } } },
      "then": { "properties": { "fullName": { "type": "string" } } }
    }
  ]
}
```

### $ref and $defs

```json
{
  "$defs": {
    "address": {
      "type": "object",
      "properties": {
        "street": { "type": "string" },
        "city": { "type": "string" }
      }
    }
  },
  "type": "object",
  "properties": {
    "billing": { "$ref": "#/$defs/address", "title": "Billing Address" },
    "shipping": { "$ref": "#/$defs/address", "title": "Shipping Address" }
  }
}
```

Supports `#/$defs/...` and `#/definitions/...` JSON Pointers. Circular references are detected and rejected.

### oneOf (select from schema variants)

```json
{
  "type": "object",
  "properties": {
    "status": {
      "type": "string",
      "title": "Status",
      "oneOf": [
        { "const": "active", "title": "Active" },
        { "const": "inactive", "title": "Inactive" },
        { "const": "pending", "title": "Pending Review" }
      ]
    }
  }
}
```

## Field Rendering Rules

The widget is chosen automatically based on schema:

| Schema | Widget |
|--------|--------|
| `string` | text input |
| `string` + `maxLength > 100` | textarea |
| `string` + `enum` (≤5 options) | radio buttons |
| `string` + `enum` (>5 options) | select dropdown |
| `string` + `oneOf` with const/title | radio buttons |
| `string` + `format: "email"` | email input |
| `string` + `format: "url"` or `"uri"` | url input |
| `string` + `format: "date"` | date picker |
| `string` + `format: "time"` | time input |
| `string` + `format: "datetime"` | datetime-local input |
| `number` / `integer` | number input (with `step` from `multipleOf`) |
| `boolean` | Yes/No radio buttons |
| `array` | dynamic list with add/remove controls |
| `object` | nested fieldset |
| `readOnly: true` | hidden by default; shown as readonly input with `with_show_readonly_fields(True)` |

## What's Implemented

### JSON Schema keywords

- **Types:** `string`, `number`, `integer`, `boolean`, `array`, `object`, `null`
- **Structure:** `properties`, `items`, `required`, `$defs`/`definitions`, `$ref`
- **Metadata:** `title`, `description`, `default`, `readOnly`
- **Enum:** `enum`, `const` (converted to single-value enum)
- **Composition:** `oneOf` (with const+title options), `allOf` (for conditional extraction)
- **Conditional:** `if`/`then`/`else` — fully dynamic, re-evaluated on every field change
- **String constraints:** `minLength`, `maxLength`, `format` (date, email, url/uri, time, datetime, uuid)
- **Number constraints:** `minimum`, `maximum`, `exclusiveMinimum`, `exclusiveMaximum`, `multipleOf`

### Validation

- Required field checks
- String length bounds (minLength, maxLength)
- Number bounds (min, max, exclusive, multipleOf)
- Basic format validation: email (checks `@` and `.`), url (checks `http(s)://` prefix)

### Other

- HTTP form submission (POST, PUT) via [rsvp](https://hexdocs.pm/rsvp/)
- Custom submission handlers
- Web Component (`<formosh-form>`) with attribute listeners and custom events
- Configurable CSS class prefix
- Initial values pre-population
- Touch tracking — errors shown only after field interaction
- Conditional field visibility — fields appear/disappear based on form state
- Schema serialization back to JSON

## What's NOT Implemented

- `anyOf` — parsed but not processed
- `not`
- `pattern` — stored but regex validation not wired up (no regex library)
- `minItems`, `maxItems` — array length constraints
- `additionalProperties`, `patternProperties`
- `dependencies`, `dependentRequired`, `dependentSchemas`
- `prefixItems` (tuple validation)
- `minProperties`, `maxProperties`
- `discriminator`
- Nested arrays within objects (shows error message)
- GET submission method
- Enum value validation (function stub exists, always passes)
- RFC-compliant email/URL format validation

## CSS Classes

All classes use a configurable prefix (default: `formosh`):

```
{prefix}-container, {prefix}-form, {prefix}-field-wrapper,
{prefix}-label, {prefix}-required, {prefix}-input, {prefix}-textarea,
{prefix}-radio-group, {prefix}-radio-item, {prefix}-select,
{prefix}-checkbox-*, {prefix}-toggle-*, {prefix}-help,
{prefix}-field-error, {prefix}-header, {prefix}-title, {prefix}-description
```

No default styles are included — bring your own CSS.

## Development

```bash
gleam deps download    # install dependencies
gleam build            # build
gleam test             # run tests
gleam format           # format code
gleam run -m lustre/dev start   # dev server with hot reload (port 1234)
gleam run -m lustre/dev build app   # production build
```

## API Reference

```gleam
// Create from JSON string
formosh.from_json_string(json: String) -> Result(App, ParseError)

// Create from parsed schema
formosh.from_schema(schema: JsonSchema) -> App

// Configuration builder
formosh.config(schema: JsonSchema) -> FormConfig
formosh.from_config(config: FormConfig) -> App
formosh.with_submit_url(config, url) -> FormConfig
formosh.with_http_submit(config, url, method, headers) -> FormConfig
formosh.with_custom_submit(config, handler) -> FormConfig
formosh.with_css_prefix(config, prefix) -> FormConfig
formosh.with_show_errors_on_change(config, show) -> FormConfig
formosh.with_show_readonly_fields(config, show) -> FormConfig
formosh.with_initial_values(config, values) -> FormConfig

// Read form state
formosh.get_values(model: FormModel) -> Dict(String, Value)

// Web Component
component.register() -> Result(Nil, Error)
component.element(attributes) -> Element(msg)
```

## License

MIT
