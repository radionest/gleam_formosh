// Common field rendering utilities

import gleam/option.{None, Some}
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import form/model.{type FormMsg, FieldBlurred, FieldChanged}
import schema/types

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

  html.label([
    attribute.for(field_name),
    attribute.class("formosh-label"),
  ], [
    html.text(label_text),
    case is_required {
      True -> html.span([attribute.class("formosh-required")], [html.text(" *")])
      False -> html.text("")
    },
  ])
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

/// Generate common input attributes for form fields.
/// 
/// Creates a standard set of HTML attributes that most form inputs need,
/// including identification, value, state, and event handlers. Additional
/// field-specific attributes can be merged with these common ones.
/// 
/// ## Parameters
/// - `field_name`: The field name used for id, name, and event handling
/// - `value`: The current string value of the field
/// - `is_required`: Whether the field is required (HTML required attribute)
/// - `is_disabled`: Whether the field is disabled (HTML disabled attribute)
/// - `extra_attrs`: Additional field-specific attributes to include
/// 
/// ## Returns
/// A list of HTML attributes ready for use on form input elements
/// 
/// ## Generated Attributes
/// - `id` and `name`: Set to field_name for identification and form submission
/// - `value`: Current field value
/// - `required`/`disabled`: State attributes
/// - Event handlers: `on_input` for value changes, `on_blur` for touch tracking
pub fn input_attributes(
  field_name: String,
  value: String,
  is_required: Bool,
  is_disabled: Bool,
  extra_attrs: List(attribute.Attribute(FormMsg)),
) -> List(attribute.Attribute(FormMsg)) {
  [
    attribute.id(field_name),
    attribute.name(field_name),
    attribute.value(value),
    attribute.required(is_required),
    attribute.disabled(is_disabled),
    event.on_input(fn(val) {
      FieldChanged(field_name, types.StringValue(val))
    }),
    event.on_blur(FieldBlurred(field_name)),
    ..extra_attrs
  ]
}