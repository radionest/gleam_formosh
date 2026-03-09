# Fields Module

Type-specific field renderers and shared rendering utilities. Each renderer produces `Element(FormMsg)` from schema properties and current values.

## Architecture

```
field_common.gleam     — Shared utilities: labels, help text, wrappers, value extractors
string_field.gleam     — Text inputs, textareas, radio groups, selects (for enums)
number_field.gleam     — Number/integer inputs with constraint attributes
boolean_field.gleam    — Yes/No radio buttons (+ checkbox and toggle alternatives)
array_field.gleam      — Dynamic lists with add/remove controls
object_field.gleam     — Nested fieldsets with recursive rendering
```

## Common Renderer Signature

Most renderers follow this pattern:

```gleam
pub fn render(
  field_path: FieldPath,
  property: SchemaProperty,
  value: Option(Value),
  is_required: Bool,
  is_disabled: Bool,
  is_readonly: Bool,
) -> Element(FormMsg)
```

Exception: `array_field.view()` uses a different signature with `name: String`, `values: List(Dict)`, `errors`, `required`.

## field_common.gleam — Shared Utilities

### Labels
- `create_field_label(field_path, property, is_required)` — label from path
- `render_label(field_name, property, is_required)` — label from string name
- Uses `property.title` if present, else humanizes field_name (underscores → spaces, capitalized)
- Required fields get `*` indicator in `formosh-required` span

### Wrappers
- `field_wrapper_with_path(field_path, property, is_required, field_element)` — wraps field with label + help text in `formosh-field-wrapper` div

### Input Attributes
- `input_attributes(field_path, value, is_required, is_disabled, extra_attrs)` — standard attributes
- Sets `id` to `path.to_string(field_path)` (unique for nested fields)
- Sets `name` to `path.get_field_name(field_path)` (last segment)
- Attaches `event.on_input` → `UpdateFieldPath(field_path, StringValue(val))`

### Value Extractors
- `extract_string_value(value)` — handles StringValue, IntegerValue, NumberValue, BooleanValue → String; others → `""`
- `extract_number_value(value)` — NumberValue/IntegerValue → String; others → `""`
- `extract_boolean_value(value)` — BooleanValue → Bool; others → `False`

## Widget Selection Rules

### string_field.gleam

| Condition | Widget | CSS Class |
|-----------|--------|-----------|
| Has enum_values, ≤5 options | Radio button group | `formosh-radio-group` |
| Has enum_values, >5 options | Select dropdown | `formosh-select` |
| maxLength > 100 | Textarea | `formosh-textarea` |
| format = EmailFormat | `<input type="email">` | `formosh-input` |
| format = UrlFormat | `<input type="url">` | `formosh-input` |
| format = DateFormat | `<input type="date">` | `formosh-input` |
| format = DateTimeFormat | `<input type="datetime-local">` | `formosh-input` |
| format = TimeFormat | `<input type="time">` | `formosh-input` |
| Default | `<input type="text">` | `formosh-input` |

String constraints → HTML attributes: `minlength`, `maxlength`, `pattern`

### number_field.gleam

Always renders `<input type="number">` with:
- Integer type → `step="1"`
- Float type → `step="any"`
- `minimum`/`maximum` → `min`/`max` attributes
- `exclusive_minimum`/`exclusive_maximum` → `min`/`max` ± 0.000001 epsilon (HTML5 workaround)
- `multiple_of` → overrides `step` attribute

**Input parsing**: empty → `NullValue`; integer mode tries `int.parse()` first; float mode tries `float.parse()` → `int.parse()` fallback; unparseable stored as `StringValue` for validation layer.

### boolean_field.gleam

**Default**: Yes/No radio buttons (`render` / `render_as_radio`)

**Alternatives** (public, for direct use):
- `render_as_checkbox(...)` — single checkbox, toggles on click
- `render_as_toggle(...)` — modern toggle switch with `role="switch"` and `aria-checked`

Readonly → disables all interactive elements via `effective_disabled = is_disabled || is_readonly`.

### array_field.gleam

- Renders numbered items ("№ 1", "№ 2", ...)
- Each item: header (number + remove button) + nested fields
- Add button: sends `AddArrayItemPath(path)`
- Remove button: sends `RemoveArrayItemPath(path, index)`
- Nested field paths: `path.to_array_item_field(array_name, index, field_name)`
- UI text in Russian: "Добавить элемент", "Удалить"
- **Limitation**: Only supports string, number/integer, boolean as nested field types (not nested arrays/objects)

### object_field.gleam

- Renders as fieldset-like container with nested fields
- **Recursive**: objects can contain objects
- Constructs nested paths: `list.append(parent_path, [PropertySegment(field_name)])`
- Readonly composes: child is readonly if parent is readonly OR nested property has `read_only = True`
- Handles enum fields (no type but has enum_values) via `string_field.render_enum()`
- **Limitation**: Nested arrays show "Nested array fields not yet supported"

## CSS Class Conventions

All classes use `formosh-` prefix (configurable via `css_prefix` in config):
- `formosh-field-wrapper` — field container
- `formosh-label` — field label
- `formosh-required` — required indicator
- `formosh-help` — description/help text
- `formosh-input` — text/number inputs
- `formosh-textarea` — multiline text
- `formosh-radio-group`, `formosh-radio-item` — radio buttons
- `formosh-select` — dropdown
- `formosh-checkbox-wrapper`, `formosh-checkbox-group` — checkboxes
- `formosh-toggle`, `formosh-toggle-wrapper`, `formosh-toggle-on/off` — toggle switch
- `formosh-number` — additional class on number inputs

Exception: `array_field.gleam` and `object_field.gleam` use unprefixed classes (`array-field`, `array-items`, `object-field`, etc.).

## Message Types Sent by Renderers

| Renderer | Message | When |
|----------|---------|------|
| string, number, boolean, object children | `UpdateFieldPath(path, value)` | Field value changes |
| array | `AddArrayItemPath(path)` | "Add" button clicked |
| array | `RemoveArrayItemPath(path, index)` | "Remove" button clicked |

## Adding a New Field Renderer

1. Create `new_type_field.gleam` in this directory
2. Implement `render(field_path, property, value, is_required, is_disabled, is_readonly) -> Element(FormMsg)`
3. Use `field_common` for labels, wrappers, and value extraction
4. Send `UpdateFieldPath(field_path, value)` on user interaction
5. Add routing in `form/view.gleam` → `render_visible_field()`
6. Add the new FieldType to `schema/types.gleam` if it's a new JSON Schema type
