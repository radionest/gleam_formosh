# Test Directory

Tests for the formosh library using the `gleeunit` framework.

## Running Tests

```bash
gleam test
```

`gleeunit` compiles every `.gleam` file in `test/` (helpers too — discovery is by function name suffix `_test`, not filename). There is no per-module filter: flags like `--module foo_test` are accepted by the CLI but silently ignored by gleeunit.

## Framework & Conventions

- **Framework**: `gleeunit` with `gleeunit/should` assertions
- **Naming**: Functions ending with `_test` are auto-discovered as tests
- **Assertions**:
  - `should.equal(actual, expected)` — value equality
  - `should.be_ok(result)` — Result is Ok
  - `should.be_error(result)` — Result is Error
  - `should.be_true(bool)` / `should.be_false(bool)` — boolean checks
- **Pattern**: Pipe operator (`|>`) with `should.*` for readable assertions
- **Setup**: Tests construct schema structures directly or parse JSON strings via `parser.parse_schema()`

## Coverage layout

Three tiers, fastest/most-isolated first:

1. **`test/public_api_test.gleam`** — the documented `formosh.*` contract:
   `config`, every `with_*` builder, `from_json_string*`, `init_model`,
   `get_values`. Builder-level assertions run directly against `FormConfig`;
   behavioral coverage (typing, validity, submit gating) runs full headless
   sessions through `lustre/dev/simulate` (`simulate.application` /
   `simulate.start` / `simulate.input`) queried with `lustre/dev/query` —
   no browser involved.
2. **`test/component_core_test.gleam`** — the `<formosh-form>` web
   component's MVU core, driven directly through the
   `formosh/internal/component_core` seam (`core.init` / `core.update`)
   instead of through DOM attribute/property plumbing: schema
   (re)initialization, array-to-`minItems` top-up, initial-values
   replacement vs. user edits, read-only toggling, and the event payload
   builders/decoders (`change_event_payload` / `change_values_decoder`,
   `submit_result_payload` / `submit_result_decoder`).
3. **`e2e/`** — real-browser coverage, run via `npm run e2e` (or
   `make e2e`): `puppeteer-core` drives system Chrome
   (`/usr/bin/google-chrome` by default, override with `CHROME_PATH`)
   against `e2e/harness.html` served by `e2e/server.mjs`. Covers what the
   two Gleam tiers can't reach — real custom-element mounting, DOM event
   listeners, attribute swaps, and submit round-trips.

**Known gaps** (ROADMAP debts, not exercised by any tier):

- `on_validate` is a no-op — `component.gleam` never emits
  `formosh-validate`, so the listener registered by `component.on_validate`
  never fires (see `ROADMAP.md`).
- `with_show_errors_on_change` is unwired — the flag is stored on
  `FormConfig` but nothing under `src/` reads it; errors always follow the
  touch gate regardless of its value (see `ROADMAP.md`).

## Test Patterns

### Parsing test
```gleam
pub fn simple_string_schema_test() {
  let json = "{ \"type\": \"object\", \"properties\": { \"name\": { \"type\": \"string\" } } }"
  let result = parser.parse_schema(json)
  result |> should.be_ok()
  let assert Ok(schema) = result
  schema.type_ |> should.equal(Some(types.ObjectType))
}
```

### Path operation test
```gleam
pub fn set_at_path_nested_array_test() {
  let root = types.ObjectValue([
    #("items", types.ArrayValue([types.ObjectValue([#("name", types.StringValue("old"))])])),
  ])
  let path = [PropertySegment("items"), ArraySegment(0), PropertySegment("name")]
  let result = path.set_at_path(root, path, types.StringValue("new"))
  // ... assert nested value was updated
}
```

### Conditional resolution test
```gleam
pub fn conditional_field_appears_when_condition_met_test() {
  let schema = // ... schema with if/then
  let values = dict.from_list([#("trigger_field", types.StringValue("yes"))])
  let resolved = conditional_resolver.resolve_conditional_schema(schema, values)
  dict.has_key(resolved.properties, "conditional_field") |> should.be_true()
}
```

### File-based integration test
```gleam
pub fn parse_basic_leak_signs_schema_test() {
  let assert Ok(json) = simplifile.read("demo/schemas/basic_leak_signs.json")
  let result = parser.parse_schema(json)
  result |> should.be_ok()
}
```

## Adding Tests

1. Create or edit `test/<module>_test.gleam`
2. Import `gleeunit/should` and the module under test
3. Name test functions with `_test` suffix
4. Run `gleam test` to verify (runs the full suite)
5. Run `gleam format` before committing

## Validator tests gotcha

When constructing a `FormModel` for tests that exercise `validate_all_fields` / cross-validators: `touched_fields` must be non-empty, otherwise the cross-validator pass is skipped (intentional — avoids pre-touch errors blocking submit on form init). Either pre-populate `touched_fields` or test through `update.update`, not the model directly. See `cross_validator_test.gleam` for the pattern.
