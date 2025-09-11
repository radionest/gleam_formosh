// Common field rendering utilities

import form/model.{type FormMsg, UpdateFieldPath}
import form/path
import gleam/float
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import schema/types


/// Create a field label from path and property.
/// 
/// Creates a properly associated label element for a form field, using either
/// the property's title or a formatted version of the field name from the path.
/// Required fields get a visual indicator (typically an asterisk).
/// 
/// ## Parameters
/// - `field_path`: The field path to generate the label for
/// - `property`: The schema property containing title information
/// - `is_required`: Whether the field is required
/// 
/// ## Returns
/// A Lustre Element representing the field label
pub fn create_field_label(
  field_path: path.FieldPath,
  property: types.SchemaProperty,
  is_required: Bool,
) -> Element(FormMsg) {
  let field_name = path.get_field_name(field_path)
  let label_text = case property.title {
    Some(title) -> title
    None -> field_name |> string.replace("_", " ") |> string.capitalise()
  }

  html.label(
    [
      attribute.for(field_name),
      attribute.class("formosh-label"),
    ],
    [
      html.text(label_text),
      case is_required {
        True ->
          html.span([attribute.class("formosh-required")], [html.text(" *")])
        False -> html.text("")
      },
    ],
  )
}

/// Render a field label with optional required indicator.
/// 
/// Creates a properly associated label element for a form field, using either
/// the schema's title property or a formatted version of the field name.
/// Required fields get a visual indicator (typically an asterisk).
/// 
/// ## Parameters
/// - `field_name`: The field name, used as fallback for label text and for association
/// - `property`: The schema property that may contain a custom title
/// - `is_required`: Whether to show the required indicator
/// 
/// ## Returns
/// A Lustre Element representing the field label
pub fn render_label(
  field_name: String,
  property: types.SchemaProperty,
  is_required: Bool,
) -> Element(FormMsg) {
  let label_text = case property.title {
    Some(title) -> title
    None -> field_name |> string.replace("_", " ") |> string.capitalise()
  }

  html.label(
    [
      attribute.for(field_name),
      attribute.class("formosh-label"),
    ],
    [
      html.text(label_text),
      case is_required {
        True ->
          html.span([attribute.class("formosh-required")], [html.text(" *")])
        False -> html.text("")
      },
    ],
  )
}

/// Render help text for a field based on its schema description.
/// 
/// If the schema property includes a description, this creates a help text
/// element to provide additional context to users. Returns empty text if
/// no description is available.
/// 
/// ## Parameters
/// - `property`: The schema property that may contain a description
/// 
/// ## Returns
/// A Lustre Element containing the help text, or empty text if none
pub fn render_help_text(property: types.SchemaProperty) -> Element(FormMsg) {
  case property.description {
    Some(desc) ->
      html.div([attribute.class("formosh-help")], [
        html.text(desc),
      ])
    None -> html.text("")
  }
}

/// Create a complete field wrapper with label, input, and help text.
/// 
/// This function provides a consistent structure for all form fields by
/// wrapping the field input element with its label and help text. This
/// ensures consistent styling and accessibility across all field types.
/// 
/// ## Parameters
/// - `field_name`: The field name for label association
/// - `property`: The schema property for label and help text
/// - `is_required`: Whether to show required indicator on the label
/// - `field_element`: The actual input element (input, select, etc.)
/// 
/// ## Returns
/// A Lustre Element containing the complete field structure
pub fn field_wrapper(
  field_name: String,
  property: types.SchemaProperty,
  is_required: Bool,
  field_element: Element(FormMsg),
) -> Element(FormMsg) {
  html.div([attribute.class("formosh-field-wrapper")], [
    render_label(field_name, property, is_required),
    field_element,
    render_help_text(property),
  ])
}

/// Wrap a form field with label and help text using field path.
/// 
/// Creates a consistent structure for all field types with label, input element,
/// and optional help text. This version uses a field path for better handling
/// of nested structures.
/// 
/// ## Parameters
/// - `field_path`: The field path for label generation
/// - `property`: The schema property containing field metadata
/// - `is_required`: Whether the field is required
/// - `field_element`: The actual input/select/textarea element
/// 
/// ## Returns
/// A complete field structure with label and help text
pub fn field_wrapper_with_path(
  field_path: path.FieldPath,
  property: types.SchemaProperty,
  is_required: Bool,
  field_element: Element(FormMsg),
) -> Element(FormMsg) {
  html.div([attribute.class("formosh-field-wrapper")], [
    create_field_label(field_path, property, is_required),
    field_element,
    render_help_text(property),
  ])
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
