# Formosh

JSON Schema form generator for Gleam. Parses JSON Schema (draft 2020-12) and renders dynamic forms using [Lustre](https://hexdocs.pm/lustre/) MVU architecture.

> **Alpha / learning project.** API is unstable and will change. Use at your own risk.

## Documentation

Full documentation lives in [`docs/`](docs/index.md) — concepts, guides
(quickstart, web component, styling, configuration), the API reference, and
the JSON Schema support matrix. This README is a quick introduction;
`docs/` is the source of truth. Planned work: [`ROADMAP.md`](ROADMAP.md).

## Installation

Not yet published on Hex — add Formosh as a path (or git) dependency:

```toml
target = "javascript"

[dependencies]
# clone https://github.com/radionest/gleam_formosh next to your project:
formosh = { path = "../gleam_formosh" }
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
import formosh/schema/types
import gleam/dict

let assert Ok(schema) = parser.parse_schema(json_string)

let app = formosh.config(schema)
  |> formosh.with_submit_url("https://api.example.com/submit")
  |> formosh.with_show_readonly_fields(True)
  |> formosh.with_initial_values(dict.from_list([
    #("patient_id", types.StringValue("12345")),
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

Set `read-only="true"` (or `component.read_only(True)` programmatically) to
render the form as a static label→value summary instead of inputs: enums show
their label, booleans Yes/No, nested objects as groups, arrays of flat objects
as tables; Submit/Reset are hidden. Useful for displaying stored values of
records that are not editable. Style it via the `readonly-*` parts (see below).

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

`minItems` / `maxItems` bound the row count: the form auto-creates rows (with
item-field defaults applied) up to `minItems`, hides the remove button when
shrinking would violate `minItems`, and hides the add button once `maxItems`
is reached. Violations coming from externally supplied values are reported
as validation errors on the array itself and are always visible (they skip
the usual touched gate — button gating means they can never be caused by
form interaction, so the message is the only explanation for a blocked
submit). A schema with `minItems > maxItems` (unsatisfiable) is normalized
at parse time so `minItems` wins: the array renders as fixed-size at
`minItems` rows.

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

Conditionals compose with array constraints: declare a whole array inside `then`
with `minItems` to make it appear — pre-populated with its first default-hydrated
row — only once the condition is met. See
[`demo/schemas/carcinomatosis_radiology.json`](demo/schemas/carcinomatosis_radiology.json)
for a worked example (`lesions` appears per-zone when `affected` is true).
`$ref` is resolved inside `if`/`then`/`else` branches, so conditional branches
can reference `$defs` definitions directly.

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

### anyOf (union types)

```json
{
  "type": "object",
  "properties": {
    "contact": {
      "title": "Contact",
      "anyOf": [
        { "type": "integer", "title": "Phone extension" },
        { "type": "string", "title": "Note" },
        { "$ref": "#/$defs/Address" }
      ]
    },
    "optional_score": {
      "anyOf": [
        { "type": "integer" },
        { "type": "null" }
      ]
    }
  },
  "$defs": {
    "Address": {
      "type": "object",
      "title": "Address",
      "properties": {
        "street": { "type": "string" },
        "city": { "type": "string" }
      }
    }
  }
}
```

Two or more non-null members (`contact` above) render as a branch chooser —
radio buttons for ≤5 branches, a select dropdown for more (same threshold as
`enum`; override with `ui:widget: "select"` or `"radio"`) — followed by the
active branch's own widget. Each option's label is the member's `title`
(`$ref` members inherit the referenced `$defs` title, so `Address` shows up
correctly), falling back to the JSON type name, then `"Option N"`. Switching
branches clears the field's previous value and re-applies the new branch's
own defaults; inside an array row, switching only resets that row, not its
neighbors. A **bare** `anyOf` directly as an array's `items` schema (no
object wrapper) does not render a chooser — wrap it in an object property.

A single non-null member alongside `{"type": "null"}` collapses into a plain
nullable field instead of a chooser — this is what a Pydantic `Optional[int]`
serializes to: `optional_score` above renders as an ordinary number input
that happens to be nullable. Leaving it empty submits `null`, and it shows no
required asterisk even when the field is named in `required`.

`oneOf` does not get this treatment: only `const`+`title` options (above)
render; general schema-variant `oneOf` is parsed but not selectable.

## Field Rendering Rules

The widget is chosen automatically based on schema:

| Schema | Widget |
|--------|--------|
| `string` | text input |
| `string` + `maxLength > 100` | textarea |
| `string` + `enum` (≤5 options) | radio buttons |
| `string` + `enum` (>5 options) | select dropdown |
| `string` + `oneOf` with const/title | radio buttons |
| `anyOf` (2+ non-null branches) | branch chooser (radio ≤5, select >5) + the active branch's own widget |
| `anyOf` (one non-null branch + `null`, i.e. `Optional[X]`) | plain `X` widget — nullable, no required asterisk, empty submits `null` |
| `string` + `format: "email"` | email input |
| `string` + `format: "url"` or `"uri"` | url input |
| `string` + `format: "date"` | date input — native picker |
| `string` + `format: "time"` | time input — native picker |
| `string` + `format: "password"` or `ui:widget: "password"` | password input — masked; wins over the `maxLength > 100` textarea rule above regardless of route |
| `string` + `format: "date-time"` | text input — deliberately not wired (see `ROADMAP.md`) |
| `number` / `integer` | number input (with `step` from `multipleOf`) |
| `boolean` | Yes/No radio buttons |
| `array` | dynamic list with add/remove controls |
| `object` | nested fieldset |
| `readOnly: true` | hidden by default; shown as readonly input with `with_show_readonly_fields(True)` |
| `object` + `ui:widget: "swipe-review"` | tap/swipe-based zone burndown |

## What's Implemented

### JSON Schema keywords

- **Types:** `string`, `number`, `integer`, `boolean`, `array`, `object`, `null`
- **Structure:** `properties`, `items` (objects and arrays nest to any depth, including arrays inside array items), `required`, `$defs`/`definitions`, `$ref`
- **Metadata:** `title`, `description`, `default`, `readOnly`
- **Enum:** `enum`, `const` (converted to single-value enum)
- **Composition:** `oneOf` (with const+title options), `allOf` (deep-merges member schemas — properties, required, bounds, `$ref` mixins — at parse time, lifts member conditionals to the parent, and can type an otherwise-typeless schema root or resolve a root-level `$ref`; an unsatisfiable composition — conflicting `type`s or crossed bounds in a composed node's merged constraints — fails parsing with `UnsatisfiableSchema` rather than silently producing one that validates nothing; see [`demo/schemas/composition_test.json`](demo/schemas/composition_test.json) for a worked example), `anyOf` (null members collapse into a `nullable` flag; a single surviving member merges into the node; 2+ surviving members render as a runtime branch chooser — see [anyOf (union types)](#anyof-union-types) above)
- **Conditional:** `if`/`then`/`else` — fully dynamic, re-evaluated on every field change
- **String constraints:** `minLength`, `maxLength`, `format` (date, email, password, url/uri, time, date-time, uuid)
- **Number constraints:** `minimum`, `maximum`, `exclusiveMinimum`, `exclusiveMaximum`, `multipleOf`
- **Array constraints:** `minItems`, `maxItems` — length validation, add/remove button gating, and auto-created rows up to `minItems`

### Validation

- Required field checks
- String length bounds (minLength, maxLength)
- Number bounds (min, max, exclusive, multipleOf)
- Array length bounds (minItems, maxItems)
- Basic format validation: email (checks `@` and `.`), url (checks `http(s)://` prefix)

### Other

- HTTP form submission (POST, PUT) via [rsvp](https://hexdocs.pm/rsvp/)
- Custom submission handlers
- Web Component (`<formosh-form>`) with attribute listeners and custom events
- Initial values pre-population
- Touch tracking — errors shown only after field interaction
- Conditional field visibility — fields appear/disappear based on form state
- Schema serialization back to JSON

## What's NOT Implemented

- `oneOf` schema-variant (polymorphic) dispatch — only `const`+`title` options render as a choice widget; unlike `anyOf`, general `oneOf` schema branches are parsed but not selectable
- A bare `anyOf` directly as an array's `items` schema (no object wrapper) — no branch chooser renders; wrap the union in an object property instead
- Unions inside array rows: hidden-field suppression and read-only table columns do not per-row-resolve the active branch (issue #86)
- `not`
- `allOf` enum/`oneOf` intersection — colliding `enum`/`oneOf` values take the later member's list wholesale
- `allOf` inside a `$defs` entry does not survive schema serialization round-trip (`$defs` stay raw; the serializer re-emits flattened schemas)
- `additionalProperties`, `patternProperties`
- `dependencies`, `dependentRequired`, `dependentSchemas`
- `prefixItems` (tuple validation)
- `minProperties`, `maxProperties`
- `discriminator`
- GET submission method
- RFC-compliant email/URL format validation

## Styling

The component runs inside an open Shadow DOM. There are three customization surfaces:

1. **`::part()` selectors** — every styled element exposes a `part` name (the class suffix without `formosh-`). Style from outside:

   ```css
   formosh-form::part(input)         { border: 1px solid #d33; }
   formosh-form::part(label)         { font-weight: 600; }
   formosh-form::part(error)         { color: orange; }
   formosh-form::part(submit)        { background: #08a; color: white; }
   ```

2. **`data-*` attributes for state** — error and readonly states on the field wrapper:

   ```css
   formosh-form::part(field)[data-error]    { border-color: red; }
   formosh-form::part(field)[data-readonly] { opacity: 0.6; }
   ```

3. **Parent stylesheets are auto-adopted** — Lustre clones the parent document's CSS into the shadow root, so plain class selectors still work:

   ```css
   .formosh-input { padding: 0.5rem; }
   .formosh-error { color: red; }
   ```

Part names available (one per styled element): `container`, `header`, `title`, `description`, `form`, `footer`, `submit`, `reset`, `success`, `error-message`, `loading`, `field`, `field-wrapper`, `label`, `required`, `help`, `errors`, `error`, `input`, `number`, `textarea`, `select`, `radio-group`, `radio-item`, `boolean`, `checkbox-wrapper`, `checkbox-group`, `array-field`, `array-items`, `array-item`, `array-item-fields`, `array-item-header`, `array-add`, `union`, `union-radio`, `union-select`, `image-upload`, `image-grid`, `image-card`, `image-preview`, `image-add`, `image-remove`, `image-uploading`, `image-spinner`, `image-error`, `image-error-text`. Read-only (review) mode adds: `readonly-field`, `readonly-label`, `readonly-value`, `readonly-group`, `readonly-group-label`, `readonly-group-body`, `readonly-table`, `readonly-th`, `readonly-td`. Swipe-review widget adds: `swipe-review`, `swipe-sheet`, `swipe-regions`, `swipe-region-group`, `swipe-region`, `swipe-zones`, `swipe-row`, `swipe-zone-title`, `swipe-choices`, `swipe-choice`, `swipe-progress`, `swipe-controls`, `swipe-toggle`, `swipe-undo`, `swipe-fill`, `swipe-review-summary`, `swipe-review-title`, `swipe-review-list`, `swipe-review-row`, `swipe-review-zone`, `swipe-review-answer`. Collapse-completed arrays (`ui:options.collapseCompleted`) add: `array-collapse-header`, `array-toggle`, `array-progress`, `array-item-summary`, `array-item-summary-value`, `array-item-summary-sep`.

Notes:

- **Cascade**: adopted parent stylesheets and host-level `::part()` rules cascade by normal CSS specificity. To override a `.formosh-*` class rule, give your `::part()` selector higher specificity or use a more specific compound condition (`::part(input):not(:disabled)`).
- **Compound parts**: elements that carry two part tokens (e.g. `part="radio-group boolean"`) are reachable through either token. `::part()` does not support descendant combinators — so `radio-item` inside a boolean group cannot be addressed differently from one inside an enum group through Shadow Parts alone.

No default styles are included — bring your own CSS.

## Development

```bash
gleam deps download    # install dependencies
gleam build            # build
gleam test             # run tests
gleam format           # format code
make demo              # interactive demo on http://localhost:1234 (picks a schema, mounts <formosh-form>)
make demo-server       # echo backend for form submissions on port 8888 (optional)
npm run build          # build CDN bundle into dist/
```

The interactive demo lives in `demo/` as a standalone Gleam project that depends on the library via `formosh = { path = ".." }`. Add JSON Schemas to `demo/schemas/` and they become selectable in the UI (see `demo/src/demo.gleam`).

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
formosh.with_show_errors_on_change(config, show) -> FormConfig  // currently a no-op, see ROADMAP.md
formosh.with_show_readonly_fields(config, show) -> FormConfig
formosh.with_initial_values(config, values) -> FormConfig

// Read form state
formosh.get_values(model: FormModel) -> Value   // tree, ObjectValue at root

// Web Component
component.register() -> Result(Nil, Error)
component.element(attributes) -> Element(msg)
```

## License

MIT
