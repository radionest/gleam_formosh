# Test Directory

Tests for the formosh library using the `gleeunit` framework.

## Running Tests

```bash
gleam test                          # Run all tests
gleam test --module parser_test     # Run specific module
gleam test --module path_test       # Run specific module
```

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

## Test Coverage Map

| Test File | Source Module | LOC | Coverage |
|-----------|-------------|-----|----------|
| `parser_test.gleam` | `schema/parser` | 124 | Basic types (string, object, array), optional fields, error handling |
| `path_test.gleam` | `form/path` | 192 | Path creation, string conversion, nested get/set, array operations |
| `serializer_test.gleam` | `schema/serializer` | 939 | All field types, constraints, refs, conditionals, formats (comprehensive) |
| `ref_test.gleam` | `schema/resolver` | 369 | Simple refs, overrides, nested refs, invalid/circular refs, #/definitions/ compat |
| `conditional_test.gleam` | `schema/conditional_resolver` | 471 | if/then, if/then/else, field visibility, allOf conditionals, const keyword |
| `complex_schema_test.gleam` | Integration | 121 | Complex nested schemas (medical form), enum parsing |
| `basic_leak_signs_test.gleam` | Integration | 114 | File-based schema loading, conditional resolution with real schemas |
| `formosh_test.gleam` | — | 13 | Placeholder (hello_world only) |

## Coverage Gaps

The following areas have **no test coverage**:

- **Public API** (`formosh.gleam`): `from_schema()`, `from_json_string()`, `config()` builder, `get_values()`
- **Form update logic** (`form/update.gleam`): field value updates, validation triggering, conditional re-resolution
- **View rendering** (`form/view.gleam`): field type routing, error display, readonly handling
- **Field renderers** (`fields/`): widget selection rules (radio vs select, textarea threshold), HTML attributes
- **Validator** (`schema/validator.gleam`): constraint validation, format checks
- **Array operations**: add/remove/reorder in update context
- **Form submission**: HTTP submission lifecycle, CustomSubmit, error handling
- **Web Component** (`component.gleam`): attribute handling, event emission

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
4. Run `gleam test --module <module>_test` to verify
5. Run `gleam format` before committing
