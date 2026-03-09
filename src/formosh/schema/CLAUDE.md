# Schema Module

JSON Schema parsing, validation, resolution, and serialization pipeline.

## Processing Pipeline

```
JSON string
  → parser.gleam (parse_schema)        → JsonSchema
    → resolver.gleam (resolve_refs)    → JsonSchema (with $refs resolved)
      → conditional_resolver.gleam     → JsonSchema (with if/then/else applied at runtime)

validator.gleam    — validates field values against schema constraints
serializer.gleam   — converts JsonSchema back to JSON (for Web Component attributes)
```

`parser.gleam` calls `resolver.resolve_refs()` internally, so `parse_schema()` returns a fully resolved schema.
`conditional_resolver` is called at runtime from `form/update.gleam` on every field change.

## Module Contracts

### types.gleam — Shared Type Definitions
All other modules in the directory import from here. Key types:

- **Value**: `StringValue | NumberValue | IntegerValue | BooleanValue | NullValue | ArrayValue | ObjectValue`
- **FieldType**: `StringType | NumberType | IntegerType | BooleanType | ArrayType | ObjectType | NullType`
- **SchemaProperty**: Complete field definition (type, title, description, constraints, enum_values, ref, nested properties/items, required list, read_only)
- **JsonSchema**: Root schema (title, description, type, properties dict, required list, defs, conditionals list, constraint fields)
- **ConditionalRule**: `if_schema` (SchemaProperty) + optional `then_schema` / `else_schema`
- **StringConstraints**: min_length, max_length, pattern, format (all Optional)
- **NumberConstraints**: minimum, maximum, exclusive_minimum, exclusive_maximum, multiple_of (all Optional)
- **StringFormat**: `DateFormat | EmailFormat | UriFormat | UrlFormat | UuidFormat | RegexFormat | CustomFormat(String)`
- **ValidationError**: field_name, message, rule

Helper constructors: `empty_string_constraints()`, `empty_number_constraints()`, `empty_property()`

### parser.gleam — JSON → JsonSchema
- **Entry**: `parse_schema(json_string: String) -> Result(JsonSchema, ParseError)`
- **ParseError**: `InvalidJson | MissingField | InvalidType | UnexpectedValue | DecodingError`

Key internal patterns:
- `property_decoder()` uses `decode.one_of()` with fallback: full object first, then bare type string
- Constraints extracted via `decode.run(data, decode.at([...], decoder))` after initial structured decode
- `const` keyword converted to single-element `enum_values` for uniform handling
- `value_decoder` tries types in order: String → Int → Float → Bool → Array → Object → Null
- Unknown format strings become `CustomFormat(string)` (no error)
- Supports both direct `if/then/else` and `allOf` arrays containing conditionals

### resolver.gleam — $ref Resolution
- **Entry**: `resolve_refs(schema: JsonSchema) -> Result(JsonSchema, ResolveError)`
- **ResolveError**: `ReferenceNotFound | CircularReference | InvalidReference`

Key behavior:
- Resolves `#/$defs/Name` and `#/definitions/Name` references
- Maintains `visited: List(String)` set to detect circular refs
- `merge_properties()`: referencing fields override referenced via `option.or()`
- After resolution, `property.ref` is set to `None`
- Only resolves top-level properties (does not modify `$defs` dict itself)
- Recursively resolves nested properties and array items

### conditional_resolver.gleam — if/then/else at Runtime
- **Entry**: `resolve_conditional_schema(base_schema: JsonSchema, form_values: Dict(String, Value)) -> JsonSchema`
- **Utility**: `is_field_visible(field_name, base_schema, form_values) -> Bool`

Key behavior:
- Uses `list.fold()` to apply all conditionals sequentially
- Conditions evaluated by checking if all properties in `condition.properties` match form values
- Single enum_value acts as const match; multiple enum_values act as OR
- `dict.merge()` merges conditional properties into base (conditional overrides base)
- `is_field_visible` checks both base properties AND any conditional that could add the field

### validator.gleam — Field Validation
- **Entry**: `validate_field(field_name, value: Option(Value), property: SchemaProperty, is_required: Bool) -> List(ValidationError)`

Key behavior:
- If value is `None`/`NullValue`: only checks required constraint, skips type validation
- Type dispatch: StringType → validate_string, NumberType/IntegerType → validate_number, BooleanType → validate_boolean
- String validation: minLength, maxLength, format (email = has `@` and `.`, url = starts with `http(s)://`)
- Number validation: minimum, maximum, exclusive bounds, multiple_of
- Errors accumulate via `list.flatten()` — all constraint violations reported

**Incomplete features:**
- `validate_enum()` — always returns `[]` (not implemented)
- Pattern validation — marked as TODO
- Format validators are basic string checks, not RFC-compliant

### serializer.gleam — JsonSchema → JSON
- **Entry**: `schema_to_json(schema: JsonSchema) -> json.Json`

Key behavior:
- Fluent field-building via pipe chain with accumulating field list
- `add_optional_*` helpers skip None values
- Empty properties/required/defs are omitted from output
- Conditionals: 0 → nothing, 1 → direct if/then/else fields, 2+ → allOf array
- Always includes `$schema` header pointing to draft 2020-12

## Common Decoding Patterns

```gleam
// Modern decode with use statements
use type_value <- decode.field("type", decode.string)
use properties <- decode.optional_field("properties", dict.new(), decode.dict(decode.string, decode.dynamic))

// Dynamic extraction for optional/conditional fields
let constraints = case decode.run(data, decode.at(["minLength"], decode.int)) {
  Ok(n) -> Some(n)
  Error(_) -> None
}
```

**Critical**: `decode.optional_field(key, default, decoder)` — default is the SECOND argument, not third.

## Adding a New Constraint or Format

1. Add type/field to `types.gleam` (StringConstraints, NumberConstraints, or new type)
2. Parse it in `parser.gleam` — extract via `decode.run()` or add to the structured decoder
3. Validate it in `validator.gleam` — add check in `validate_string()` or `validate_number()`
4. Serialize it in `serializer.gleam` — add `add_optional_*` call in the builder chain
5. Add tests in `test/` (parser, serializer, and ideally validator)
