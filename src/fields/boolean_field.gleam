/// Boolean field renderer with multiple presentation options.
/// 
/// This module provides different ways to render boolean fields including
/// radio buttons (Yes/No), checkboxes, and toggle switches. The default
/// render function uses radio buttons for better accessibility and clarity.

import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import form/model.{type FormMsg, FieldBlurred, FieldChanged}
import schema/types

/// Render a boolean field as radio buttons (Yes/No).
/// 
/// This is the default boolean field renderer that uses radio buttons
/// for better user experience and accessibility. Radio buttons make the
/// boolean choice explicit and clear to users.
/// 
/// ## Parameters
/// - `field_name`: The field name for identification
/// - `property`: Schema property for labeling and help text
/// - `value`: Current boolean value (defaults to False if unset)
/// - `is_required`: Whether a selection is required
/// - `is_disabled`: Whether the field is disabled
/// 
/// ## Returns
/// A complete boolean field using radio buttons for Yes/No selection
/// 
/// ## Alternative Renderers
/// - `render_as_checkbox`: Single checkbox for true/false
/// - `render_as_toggle`: Toggle switch interface
pub fn render(
  field_name: String,
  property: types.SchemaProperty,
  value: Option(types.FieldValue),
  is_required: Bool,
  is_disabled: Bool,
) -> Element(FormMsg) {
  let current_value = case value {
    Some(types.BooleanValue(b)) -> b
    _ -> False
  }

  // Render as radio buttons (Yes/No) for better UX
  render_as_radio(field_name, property, current_value, is_required, is_disabled)
}

/// Render boolean field as Yes/No radio button group.
/// 
/// Creates a radio button group with Yes (true) and No (false) options.
/// This provides explicit choice selection that's accessible and clear.
/// 
/// ## Parameters
/// - `field_name`: The field name for radio button grouping
/// - `property`: Schema property for labeling and help text
/// - `current_value`: Current boolean value
/// - `is_required`: Whether a selection is required
/// - `is_disabled`: Whether both radio buttons are disabled
/// 
/// ## Returns
/// A radio button group with Yes/No options
fn render_as_radio(
  field_name: String,
  property: types.SchemaProperty,
  current_value: Bool,
  is_required: Bool,
  is_disabled: Bool,
) -> Element(FormMsg) {
  let yes_id = field_name <> "_yes"
  let no_id = field_name <> "_no"

  html.div([attribute.class("formosh-field-wrapper")], [
    render_label(field_name, property, is_required),
    html.div([attribute.class("formosh-radio-group formosh-boolean")], [
      html.div([attribute.class("formosh-radio-item")], [
        html.input([
          attribute.type_("radio"),
          attribute.id(yes_id),
          attribute.name(field_name),
          attribute.value("true"),
          attribute.checked(current_value),
          attribute.required(is_required),
          attribute.disabled(is_disabled),
          event.on_click(FieldChanged(field_name, types.BooleanValue(True))),
        ]),
        html.label([attribute.for(yes_id)], [
          html.text("Yes"),
        ]),
      ]),
      html.div([attribute.class("formosh-radio-item")], [
        html.input([
          attribute.type_("radio"),
          attribute.id(no_id),
          attribute.name(field_name),
          attribute.value("false"),
          attribute.checked(!current_value),
          attribute.required(is_required),
          attribute.disabled(is_disabled),
          event.on_click(FieldChanged(field_name, types.BooleanValue(False))),
        ]),
        html.label([attribute.for(no_id)], [
          html.text("No"),
        ]),
      ]),
    ]),
    render_help_text(property),
  ])
}

/// Render boolean field as a single checkbox.
/// 
/// Alternative boolean renderer that uses a traditional checkbox input.
/// This is more compact but may be less explicit about the false state
/// compared to radio buttons.
/// 
/// ## Parameters
/// - `field_name`: The field name for identification
/// - `property`: Schema property for labeling and help text
/// - `value`: Current boolean value (defaults to False if unset)
/// - `is_required`: Whether the checkbox must be checked
/// - `is_disabled`: Whether the checkbox is disabled
/// 
/// ## Returns
/// A checkbox field with label positioned after the checkbox
/// 
/// ## Usage
/// Use this for compact boolean inputs or when the false state is implicit.
pub fn render_as_checkbox(
  field_name: String,
  property: types.SchemaProperty,
  value: Option(types.FieldValue),
  is_required: Bool,
  is_disabled: Bool,
) -> Element(FormMsg) {
  let current_value = case value {
    Some(types.BooleanValue(b)) -> b
    _ -> False
  }

  html.div([attribute.class("formosh-field-wrapper formosh-checkbox-wrapper")], [
    html.div([attribute.class("formosh-checkbox-group")], [
      html.input([
        attribute.type_("checkbox"),
        attribute.id(field_name),
        attribute.name(field_name),
        attribute.checked(current_value),
        attribute.required(is_required),
        attribute.disabled(is_disabled),
        event.on_click(FieldChanged(field_name, types.BooleanValue(!current_value))),
        event.on_blur(FieldBlurred(field_name)),
      ]),
      render_checkbox_label(field_name, property, is_required),
    ]),
    render_help_text(property),
  ])
}

/// Render boolean field as a toggle switch.
/// 
/// Alternative boolean renderer that creates a toggle switch interface
/// with ON/OFF states. This provides a modern, mobile-friendly interface
/// for boolean selection.
/// 
/// ## Parameters
/// - `field_name`: The field name for identification
/// - `property`: Schema property for labeling and help text
/// - `value`: Current boolean value (defaults to False if unset)
/// - `is_required`: Whether the field is required (for validation only)
/// - `is_disabled`: Whether the toggle is disabled
/// 
/// ## Returns
/// A toggle switch with ON/OFF visual states
/// 
/// ## Features
/// - Visual ON/OFF indicator
/// - ARIA accessibility attributes (role="switch", aria-checked)
/// - Button-based interaction (not a form input)
/// 
/// ## Usage
/// Use for modern interfaces or settings-style boolean controls.
pub fn render_as_toggle(
  field_name: String,
  property: types.SchemaProperty,
  value: Option(types.FieldValue),
  is_required: Bool,
  is_disabled: Bool,
) -> Element(FormMsg) {
  let current_value = case value {
    Some(types.BooleanValue(b)) -> b
    _ -> False
  }

  html.div([attribute.class("formosh-field-wrapper")], [
    render_label(field_name, property, is_required),
    html.div([attribute.class("formosh-toggle-wrapper")], [
      html.button([
        attribute.type_("button"),
        attribute.class(
          "formosh-toggle"
          <> case current_value {
            True -> " formosh-toggle-on"
            False -> " formosh-toggle-off"
          },
        ),
        attribute.disabled(is_disabled),
        attribute.attribute("role", "switch"),
        attribute.attribute("aria-checked", case current_value {
          True -> "true"
          False -> "false"
        }),
        event.on_click(FieldChanged(field_name, types.BooleanValue(!current_value))),
      ], [
        html.span([attribute.class("formosh-toggle-slider")], []),
        html.span([attribute.class("formosh-toggle-text")], [
          html.text(case current_value {
            True -> "ON"
            False -> "OFF"
          }),
        ]),
      ]),
    ]),
    render_help_text(property),
  ])
}

/// Render field label for boolean fields.
/// 
/// **Note**: This duplicates functionality from field_common.render_label
/// and should ideally use the common implementation for consistency.
/// 
/// ## Parameters
/// - `field_name`: Field name for label association
/// - `property`: Schema property for title text
/// - `is_required`: Whether to show required indicator
/// 
/// ## Returns
/// A label element for the boolean field
fn render_label(
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

/// Render label for checkbox-style boolean fields.
/// 
/// Creates a label specifically styled for checkbox inputs, typically
/// positioned after the checkbox itself for better visual flow.
/// 
/// ## Parameters
/// - `field_name`: Field name for label association
/// - `property`: Schema property for title text
/// - `is_required`: Whether to show required indicator
/// 
/// ## Returns
/// A label element styled for checkbox positioning
fn render_checkbox_label(
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
    attribute.class("formosh-checkbox-label"),
  ], [
    html.text(label_text),
    case is_required {
      True -> html.span([attribute.class("formosh-required")], [html.text(" *")])
      False -> html.text("")
    },
  ])
}

/// Render help text for boolean fields.
/// 
/// **Note**: This duplicates functionality from field_common.render_help_text
/// and should ideally use the common implementation for consistency.
/// 
/// ## Parameters
/// - `property`: Schema property containing description
/// 
/// ## Returns
/// A help text element or empty text if no description
fn render_help_text(property: types.SchemaProperty) -> Element(FormMsg) {
  case property.description {
    Some(desc) ->
      html.div([attribute.class("formosh-help")], [
        html.text(desc),
      ])
    None -> html.text("")
  }
}