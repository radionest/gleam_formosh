# File Schema Loader Example

Standalone Gleam/Lustre application demonstrating formosh usage with file-based JSON Schema loading and the Web Component integration.

## Relationship to Main Library

Depends on formosh via local path:
```toml
formosh = { path = "../.." }
```

Uses the formosh Web Component (`<formosh-form>`) — not the direct Gleam API.

## Running

```bash
cd examples/file_schema_loader
gleam deps download
gleam run -m lustre/dev start    # Dev server with hot reload
```

## What It Demonstrates

1. **Schema selection UI** — buttons to pick from available schemas
2. **HTTP schema loading** — fetches JSON files from `./schemas/` via rsvp
3. **Schema validation** — validates JSON via `formosh.from_json_string()` before rendering
4. **Web Component usage** — mounts `<formosh-form>` with schema/submit attributes
5. **Custom event handling** — listens to `formosh-submit` and `formosh-change` events
6. **Submission result display** — shows success/error after form submission

## Available Schemas (`schemas/`)

| File | Description | Complexity |
|------|-------------|------------|
| `contact_form.json` | Simple name/email/message | Basic (17 lines) |
| `user_registration.json` | Registration with validation | Medium (~270 lines) |
| `survey_form.json` | Multi-section survey | Complex (~350 lines) |
| `basic_leak_signs.json` | Medical imaging form with conditionals | Complex (~140 lines) |

## Key Architecture

### MVU Pattern
```gleam
type Model {
  selected_schema: Option(String),
  schema_content: Option(String),
  available_schemas: List(String),
  error: Option(String),
  submission_result: Option(String),
}

type Msg {
  LoadSchema(String)              // User selects a schema
  SchemaFetched(Result)           // HTTP fetch completed
  FormSubmitted(Dict)             // Form submission event
  FormChanged(Dict)               // Form change event (TODO: not fully implemented)
  ClearSubmissionResult           // Clear result message
}
```

### Web Component Integration
```gleam
// Registers formosh component
component.register()

// Creates <formosh-form> element with attributes
element.element("formosh-form", [
  attribute.attribute("schema", json_string),
  attribute.attribute("submit-url", "http://localhost:8888"),
  attribute.attribute("submit-method", "POST"),
], [])
```

### Event Decoding
- `formosh-submit` event: extracts data/errors from `event.detail`
- `formosh-change` event: marked as TODO (incomplete)

## FFI

`file_schema_loader_ffi.mjs` provides JavaScript interop for file system operations used during development.

## Known Limitations

- `decode_form_change()` is not fully implemented (TODO)
- Hardcoded submit URL (`http://localhost:8888`)
- Schema display names derived from filenames (underscores → spaces)
