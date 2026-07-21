// Common field rendering utilities

import formosh/form/model.{type FormModel, type FormMsg, UpdateFieldPath}
import formosh/form/path
import formosh/schema/types.{type RenderHints}
import formosh/schema/ui_resolver
import formosh/validation/error.{type ValidationError}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// Render the required indicator (` *` span with `formosh-required` class)
/// or an empty element when not required.
///
/// Use this everywhere a required marker is shown so the visual cue and
/// CSS hook stay in sync between scalar fields, array containers, and
/// object containers. Inlining the `case is_required { ... }` is what
/// caused the marker to disappear from container labels during the
/// dispatcher unification refactor.
pub fn render_required_marker(is_required: Bool) -> Element(FormMsg) {
  case is_required {
    True ->
      html.span(
        [
          attribute.class("formosh-required"),
          attribute.attribute("part", "required"),
        ],
        [html.text(" *")],
      )
    False -> element.none()
  }
}

/// Visible text for a field label: `hints.title` (UiSchema override) wins
/// over `property.title` (JSON Schema), which in turn wins over the field
/// name with underscores replaced by spaces and capitalised.
pub fn label_text(
  field_name: String,
  property: types.SchemaProperty,
  hints: RenderHints,
) -> String {
  case hints.title, property.title {
    Some(t), _ -> t
    None, Some(t) -> t
    None, None -> field_name |> string.replace("_", " ") |> string.capitalise()
  }
}

/// Render a field label with optional required indicator.
///
/// `hints.title` (UiSchema) wins over `property.title` (JSON Schema), with
/// the field name as final fallback. Required fields get a visual
/// indicator (typically an asterisk).
pub fn render_label(
  field_name name: String,
  property prop: types.SchemaProperty,
  is_required required: Bool,
  hints hints: RenderHints,
) -> Element(FormMsg) {
  html.label(
    [
      attribute.for(name),
      attribute.class("formosh-label"),
      attribute.attribute("part", "label"),
    ],
    [
      html.text(label_text(name, prop, hints)),
      render_required_marker(required),
    ],
  )
}

/// Render a container field label (object/array) without a `for=` association.
///
/// Containers have no single input to point to; the label is a section
/// heading. `css_class` keeps the existing styling hook
/// (`array-label`, `object-label`).
///
/// ## Parameters
/// - `field_name`: The field name, used as fallback for label text
/// - `property`: The schema property that may contain a custom title
/// - `is_required`: Whether to show the required indicator
/// - `css_class`: CSS class to apply to the `<label>` element
///
/// ## Returns
/// A Lustre Element representing the container field label
pub fn render_container_label(
  field_name name: String,
  property prop: types.SchemaProperty,
  is_required required: Bool,
  css_class class: String,
  hints hints: RenderHints,
) -> Element(FormMsg) {
  html.label([attribute.class(class)], [
    html.text(label_text(name, prop, hints)),
    render_required_marker(required),
  ])
}

/// Render help text for a field.
///
/// Priority: `hints.help` (UiSchema override) → `hints.description`
/// (UiSchema description override) → `property.description` (JSON Schema).
/// Returns an empty element when no text is available.
pub fn render_help_text(
  property: types.SchemaProperty,
  hints: RenderHints,
) -> Element(FormMsg) {
  let text = case hints.help, hints.description, property.description {
    Some(t), _, _ -> Some(t)
    None, Some(t), _ -> Some(t)
    None, None, Some(t) -> Some(t)
    None, None, None -> None
  }
  case text {
    Some(t) ->
      html.div(
        [
          attribute.class("formosh-help"),
          attribute.attribute("part", "help"),
        ],
        [html.text(t)],
      )
    None -> element.none()
  }
}

/// Wrap a form field with label and help text using a `FieldRenderCtx`.
///
/// Creates a consistent structure for all field types with label, input
/// element, and optional help text. Pulls every needed value out of the
/// ctx so callers don't have to thread `path`/`property`/`is_required`/
/// `hints` individually.
pub fn field_wrapper(
  ctx: FieldRenderCtx,
  field_element: Element(FormMsg),
) -> Element(FormMsg) {
  html.div(
    [
      attribute.class("formosh-field-wrapper"),
      attribute.attribute("part", "field-wrapper"),
    ],
    [
      render_label(
        field_name: path.get_field_name(ctx.path),
        property: ctx.property,
        is_required: ctx.is_required,
        hints: ctx.hints,
      ),
      field_element,
      render_help_text(ctx.property, ctx.hints),
    ],
  )
}

/// Generate common input attributes for form fields.
/// 
/// Creates a standard set of HTML attributes that most form inputs need,
/// including identification, value, state, and event handlers. This function
/// uses a field path for proper handling of nested structures and consistent
/// messaging throughout the form system.
/// 
/// ## Parameters
/// - `field_path`: The field path for identification and event handling
/// - `value`: The current string value of the field
/// - `is_required`: Whether the field is required (HTML required attribute)
/// - `is_disabled`: Whether the field is disabled (HTML disabled attribute)
/// - `extra_attrs`: Additional field-specific attributes to include
/// 
/// ## Returns
/// A list of HTML attributes ready for use on form input elements
/// 
/// ## Generated Attributes
/// - `id`: Set to the full path string for unique identification in nested structures
/// - `name`: Set to the field name (last segment of path) for form submission
/// - `value`: Current field value
/// - `required`/`disabled`: State attributes
/// - Event handlers: `on_input` for value changes with proper path-based messaging
/// 
/// ## Usage
/// ```gleam
/// // For a simple field
/// let path = path.from_field_name("email")
/// let attrs = input_attributes(path, "user@example.com", True, False, [])
/// 
/// // For a nested field in an array
/// let path = path.to_array_item_field("items", 0, "name")
/// let attrs = input_attributes(path, "Item 1", False, False, [attribute.class("custom")])
/// ```
pub fn input_attributes(
  field_path: path.FieldPath,
  value: String,
  is_required: Bool,
  is_disabled: Bool,
  extra_attrs: List(attribute.Attribute(FormMsg)),
) -> List(attribute.Attribute(FormMsg)) {
  let field_name = path.get_field_name(field_path)

  [
    attribute.id(path.to_string(field_path)),
    attribute.name(field_name),
    attribute.value(value),
    attribute.required(is_required),
    attribute.disabled(is_disabled),
    event.on_input(fn(val) {
      UpdateFieldPath(field_path, types.StringValue(val))
    }),
    ..extra_attrs
  ]
}

/// Extract a string value from a Value.
/// 
/// Converts any Value to its string representation, useful for
/// displaying values in text inputs and other string-based controls.
/// 
/// ## Parameters
/// - `value`: Optional Value to extract from
/// 
/// ## Returns
/// - StringValue: Returns the contained string
/// - IntegerValue: Converts to string representation
/// - NumberValue: Converts to string representation
/// - BooleanValue: Returns "true" or "false"
/// - Others: Returns empty string as fallback
pub fn extract_string_value(value: Option(types.Value)) -> String {
  case value {
    Some(types.StringValue(s)) -> s
    Some(types.IntegerValue(i)) -> int.to_string(i)
    Some(types.NumberValue(n)) -> float.to_string(n)
    Some(types.BooleanValue(True)) -> "true"
    Some(types.BooleanValue(False)) -> "false"
    _ -> ""
  }
}

/// Extract a numeric value from a Value as a string for display.
/// 
/// Specialized extractor for number fields that only handles numeric types,
/// returning an appropriate string representation for HTML number inputs.
/// 
/// ## Parameters
/// - `value`: Optional Value to extract from
/// 
/// ## Returns
/// - NumberValue: Float converted to string
/// - IntegerValue: Integer converted to string
/// - Others: Empty string
pub fn extract_number_value(value: Option(types.Value)) -> String {
  case value {
    Some(types.NumberValue(n)) -> float.to_string(n)
    Some(types.IntegerValue(i)) -> int.to_string(i)
    _ -> ""
  }
}

/// Extract a boolean value from a Value.
/// 
/// Converts a Value to boolean, useful for checkbox and toggle controls.
/// Non-boolean values default to false for safety.
/// 
/// ## Parameters
/// - `value`: Optional Value to extract from
/// 
/// ## Returns
/// - BooleanValue: The contained boolean
/// - Others: False as default
pub fn extract_boolean_value(value: Option(types.Value)) -> Bool {
  case value {
    Some(types.BooleanValue(b)) -> b
    _ -> False
  }
}

/// Shared per-field rendering context.
///
/// Bundles the values every field renderer needs: where the field lives
/// (`path`), what schema describes it (`property`), its current value, the
/// three behavioural flags the parent decides (`is_required`, `is_disabled`,
/// `is_readonly`), and the presentation hints (`hints`) that pick a widget
/// and feed widget-specific options. Children build their own ctx via
/// `make_field_ctx` / `make_child_ctx`.
///
/// **When adding a field here:** also propagate it explicitly in
/// `make_child_ctx` (the inheritance rule must be picked deliberately —
/// passthrough, OR-merge, override, etc.). The constructor in
/// `make_child_ctx` lists every field by name on purpose; gleam will NOT
/// warn you about an omitted new field.
///
/// `hints` is the UiSchema seam: filled by `ui_resolver.resolve_hints`
/// from a path lookup against `model.ui_schema`, with the deprecated
/// `x-*` extensions as fallback.
pub type FieldRenderCtx {
  FieldRenderCtx(
    path: path.FieldPath,
    property: types.SchemaProperty,
    value: Option(types.Value),
    is_required: Bool,
    is_disabled: Bool,
    is_readonly: Bool,
    hints: types.RenderHints,
  )
}

/// Build a `FieldRenderCtx` for a top-level field at the given path.
///
/// The caller decides the three boolean flags (it owns the inheritance
/// rules: parent `required` list, parent `is_readonly`, etc.). The builder
/// only extracts the current value from the model — this is the single
/// place where path-to-value lookup happens during render, so v0.7 can hook
/// `ui_options` lookup here without touching call sites.
///
/// For descendants inside containers, use `make_child_ctx` instead: it
/// encodes the inheritance rules so each container does not re-derive them.
pub fn make_field_ctx(
  model model: FormModel,
  path field_path: path.FieldPath,
  property property: types.SchemaProperty,
  is_required is_required: Bool,
  is_disabled is_disabled: Bool,
  is_readonly is_readonly: Bool,
) -> FieldRenderCtx {
  let hints = ui_resolver.resolve_hints(model.ui_schema, field_path, property)
  FieldRenderCtx(
    path: field_path,
    property: property,
    value: model.get_value_at_path(model, field_path),
    // Nullable fields always accept empty (submitted as `null`), so the
    // required marker is misleading — suppress it even when the field is
    // named in the schema's `required` list.
    is_required: is_required && !property.nullable,
    is_disabled: is_disabled || option.unwrap(hints.disabled, False),
    is_readonly: is_readonly || option.unwrap(hints.readonly, False),
    hints: hints,
  )
}

/// Build a child `FieldRenderCtx` from a parent ctx and the child's own
/// path/schema/required flag.
///
/// Encodes container-to-child inheritance in one place:
/// - `is_disabled` flows through as-is (parent decides whether the whole
///   subtree is disabled)
/// - `is_readonly` OR-merges with `child_prop.read_only` (a readonly parent
///   makes every descendant readonly, regardless of the child's own flag)
/// - `is_required` is supplied by the caller, since required-membership is
///   per-child (parent's `required` list naming the child, or a row-resolved
///   list after `if/then/else`) — then ANDed with `!child_prop.nullable`,
///   since a nullable child always accepts empty and should never show the
///   required marker
///
/// All v0.7+ ctx fields that should inherit by default flow via `..parent`,
/// so adding a new field (e.g. `ui_options`) does not require touching
/// `array_field`/`object_field`.
pub fn make_child_ctx(
  parent parent: FieldRenderCtx,
  model model: FormModel,
  path child_path: path.FieldPath,
  property child_prop: types.SchemaProperty,
  is_required child_required: Bool,
) -> FieldRenderCtx {
  let hints = ui_resolver.resolve_hints(model.ui_schema, child_path, child_prop)
  FieldRenderCtx(
    path: child_path,
    property: child_prop,
    value: model.get_value_at_path(model, child_path),
    // Same nullable-suppresses-required-marker rule as make_field_ctx.
    is_required: child_required && !child_prop.nullable,
    is_disabled: parent.is_disabled || option.unwrap(hints.disabled, False),
    is_readonly: parent.is_readonly
      || child_prop.read_only
      || option.unwrap(hints.readonly, False),
    hints: hints,
  )
}

/// Render a list of validation errors for a single field.
///
/// Wraps the messages in a `formosh-errors` container so the styling matches
/// the rest of the form. Used by `view.gleam` for top-level fields and by
/// `array_field.gleam` for item-level fields inside arrays.
pub fn render_field_errors(errors: List(ValidationError)) -> Element(FormMsg) {
  html.div(
    [
      attribute.class("formosh-errors"),
      attribute.attribute("part", "errors"),
    ],
    list.map(errors, fn(error) {
      html.div(
        [
          attribute.class("formosh-error"),
          attribute.attribute("part", "error"),
        ],
        [html.text(error.message)],
      )
    }),
  )
}
