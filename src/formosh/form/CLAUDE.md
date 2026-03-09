# Form Module

MVU (Model-View-Update) core implementing form state, message handling, rendering, and the path-based field addressing system.

## Module Overview

```
model.gleam    — FormModel state, FormMsg messages, field state queries
update.gleam   — Pure state transitions, validation pipeline, HTTP submission
view.gleam     — Declarative HTML rendering, field type routing
path.gleam     — FieldPath addressing for nested structures (CRITICAL)
json_utils.gleam — Value → json.Json conversion (used during submission)
```

## Message Flow

```
User interaction
  → FormMsg (UpdateFieldPath, AddArrayItemPath, RemoveArrayItemPath, FormSubmit, ...)
    → update.gleam processes message
      → Updates values in model (via path operations on hierarchical Value tree)
      → Re-resolves conditional schema (conditional_resolver)
      → Validates ALL fields
      → Returns (FormModel, Effect)
        → view.gleam re-renders from new model
```

## Path System (path.gleam) — Critical

The path system is the foundation for all nested field operations. Understand this first.

```gleam
pub type FieldPath = List(PathSegment)
pub type PathSegment {
  PropertySegment(name: String)    // object field
  ArraySegment(index: Int)         // array index
}

// Examples:
// "email"                          → [PropertySegment("email")]
// "lesions[0].side"                → [PropertySegment("lesions"), ArraySegment(0), PropertySegment("side")]
// "user.profile.name"              → [PropertySegment("user"), PropertySegment("profile"), PropertySegment("name")]
```

### Public API

| Function | Signature | Purpose |
|----------|-----------|---------|
| `from_field_name` | `(String) -> FieldPath` | Single-segment path |
| `to_array_item_field` | `(String, Int, String) -> FieldPath` | `[Property, Array, Property]` path |
| `to_string` | `(FieldPath) -> String` | Dot notation for display/keys |
| `get_field_name` | `(FieldPath) -> String` | Last property segment (fallback: `"field"`) |
| `get_at_path` | `(Value, FieldPath) -> Option(Value)` | Traverse nested Value tree |
| `set_at_path` | `(Value, FieldPath, Value) -> Value` | Set value at path (creates intermediates) |
| `modify_at_path` | `(Value, FieldPath, fn(Value) -> Value) -> Value` | Apply function at path |
| `add_array_item_at_path` | `(Value, FieldPath, Value) -> Value` | Append to array |
| `remove_array_item_at_path` | `(Value, FieldPath, Int) -> Value` | Remove by index |

### Key behaviors:
- All operations are immutable — return new Value trees
- `set_at_path` creates intermediate ObjectValue/ArrayValue as needed
- Arrays are padded with `NullValue` when setting at sparse indices
- `get_field_name` returns `"field"` for empty paths or paths ending with ArraySegment

## Model (model.gleam)

### FormModel State

```gleam
FormModel(
  schema: JsonSchema,              // Original parsed schema
  resolved_schema: JsonSchema,     // After conditional resolution (updated on every field change)
  values: Dict(String, Value),     // Flat dict with dot-notation keys for root fields
  errors: Dict(String, List(ValidationError)),
  is_submitting: Bool,
  is_dirty: Bool,
  is_valid: Bool,
  touched_fields: List(String),    // Only touched fields show errors
  disabled_fields: List(String),
  submission_result: Option(SubmissionResult),
  submit_config: Option(SubmitConfig),
  show_readonly_fields: Bool,
)
```

### FormMsg Messages

```gleam
UpdateFieldPath(path: FieldPath, value: Value)      // Field value changed
AddArrayItemPath(path: FieldPath)                    // Add item to array
RemoveArrayItemPath(path: FieldPath, index: Int)     // Remove array item
FormSubmit                                            // Submit form
FormSubmitted(Result(String, String))                 // Submission result
ValidateForm                                          // Trigger validation
ResetForm                                             // Reset to initial state
```

### Initialization

- `init(schema)` — basic init with NoSubmit
- `init_with_config(schema, submit_config)` — with submission config
- `init_with_full_config(schema, submit_config, show_readonly_fields, initial_values)` — full control

### Field State Queries

Path-based: `get_value_at_path`, `is_required_at_path`, `has_errors_at_path`, `get_errors_at_path`, `set_value_at_path`

String-based (root fields): `get_field_value`, `is_field_required`, `field_has_errors`, `is_field_touched`, `is_field_disabled`

## Update (update.gleam)

### State Transition Details

**UpdateFieldPath** (most complex):
1. Converts flat `model.values` dict → hierarchical `Value` tree via `model_to_root_value()`
2. Calls `path.set_at_path()` on the tree
3. Converts back to flat dict via `root_value_to_model_values()`
4. Re-resolves conditionals: `conditional_resolver.resolve_conditional_schema(schema, new_values)`
5. Validates ALL fields (not just the changed one)

**AddArrayItemPath**: Appends `ObjectValue([])` at path
**RemoveArrayItemPath**: Filters out item by index

**FormSubmit**:
1. Validates all fields
2. Checks `can_submit()` (valid + not already submitting)
3. Creates submission effect based on SubmitConfig

### Submission Configs

- `HttpSubmit(url, method, headers)` — POST via `rsvp.post()`, PUT via `request.to()` builder. GET not supported.
- `CustomSubmit(handler)` — calls `handler(model)` in an effect
- `NoSubmit` / `None` — always returns SubmissionSuccess

### Validation Pipeline

`validate_all_fields(model)` iterates all `resolved_schema.properties`, calling `validator.validate_field()` for each. Errors stored in `model.errors` dict, keyed by field name.

**Important**: Validation runs on EVERY `UpdateFieldPath` message for ALL fields. No debouncing.

## View (view.gleam)

### Rendering Pipeline

```
view(model)
  → render_form_header (title, description)
  → render_form_body
      → for each property in resolved_schema.properties:
          → render_field (checks readonly visibility)
            → render_visible_field (routes to type-specific renderer)
      → render_form_footer_content (Submit/Reset buttons)
  → render_submission_result (success/error message)
```

### Field Type Routing

| field_type | Renderer | Notes |
|------------|----------|-------|
| StringType | `string_field.render()` | |
| NumberType / IntegerType | `number_field.render()` | |
| BooleanType | `boolean_field.render()` | |
| ArrayType | `array_field.view()` | Converts ArrayValue → List(Dict) |
| ObjectType | `object_field.render()` | |
| None + has enum_values | `string_field.render_enum()` | |

### Error Display Logic

Errors shown only when field is **touched AND has errors**. CSS class `formosh-field-error` added to wrapper.

### ReadOnly Handling

- If `show_readonly_fields = False` (default): readonly fields are skipped entirely
- If `show_readonly_fields = True`: readonly fields rendered as disabled

### Button States

- Submit: disabled when `is_submitting` or `!can_submit()`
- Submit text: "Отправить" / "Отправка..." (Russian)
- Reset: disabled when `is_submitting`

## Value Storage Architecture

Root-level values stored in flat `Dict(String, Value)`. For nested/array operations, `update.gleam` converts to a hierarchical `Value` tree, performs path operations, then converts back:

```
Dict(String, Value)  ←→  ObjectValue(List(#(String, Value)))
     flat storage           hierarchical tree (for path ops)
```

This round-trip happens on every `UpdateFieldPath` message via `model_to_root_value()` / `root_value_to_model_values()`.

## Adding a New Field Type

1. Create renderer in `fields/` following the pattern of existing renderers
2. Add routing case in `view.gleam` → `render_visible_field()`
3. Handle the new FieldType in `update.gleam` validation (if needed)
4. Ensure path operations work for the new type's nesting behavior
