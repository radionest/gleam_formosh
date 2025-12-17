/// Boolean field renderer with multiple presentation options.
/// 
/// This module provides different ways to render boolean fields including
/// radio buttons (Yes/No), checkboxes, and toggle switches. The default
/// render function uses radio buttons for better accessibility and clarity.
import fields/field_common
import form/model.{type FormMsg, UpdateFieldPath}
import form/path
import gleam/option.{type Option, None}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
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
/// - `is_readonly`: Whether the field is read-only
///
/// ## Returns
/// A complete boolean field using radio buttons for Yes/No selection
///
/// ## Alternative Renderers
/// - `render_as_checkbox`: Single checkbox for true/false
/// - `render_as_toggle`: Toggle switch interface
pub fn render(
  field_path: path.FieldPath,
  property: types.SchemaProperty,
  _value: Option(types.Value),
  is_required: Bool,
  is_disabled: Bool,
  is_readonly: Bool,
) -> Element(FormMsg) {
  // For readonly, disable the radio buttons to prevent changes
  let effective_disabled = is_disabled || is_readonly

  // Render as radio buttons (Yes/No) for better UX
  render_as_radio(field_path, property, is_required, effective_disabled)
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
  field_path: path.FieldPath,
  property: types.SchemaProperty,
  is_required: Bool,
  is_disabled: Bool,
) -> Element(FormMsg) {
  let field_name = path.get_field_name(field_path)
  let yes_id = field_name <> "_yes"
  let no_id = field_name <> "_no"

  html.div([attribute.class("formosh-field-wrapper")], [
    field_common.render_label(field_name, property, is_required),
    html.div([attribute.class("formosh-radio-group formosh-boolean")], [
      html.div([attribute.class("formosh-radio-item")], [
        html.input([
          attribute.type_("radio"),
          attribute.id(yes_id),
          attribute.name(field_name),
          attribute.value("true"),
          attribute.required(is_required),
          attribute.disabled(is_disabled),
          event.on_click(UpdateFieldPath(field_path, types.BooleanValue(True))),
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
          attribute.required(is_required),
          attribute.disabled(is_disabled),
          event.on_click(UpdateFieldPath(field_path, types.BooleanValue(False))),
        ]),
        html.label([attribute.for(no_id)], [
          html.text("No"),
        ]),
      ]),
    ]),
    field_common.render_help_text(property),
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
  field_path: path.FieldPath,
  property: types.SchemaProperty,
  value: Option(types.Value),
  is_required: Bool,
  is_disabled: Bool,
) -> Element(FormMsg) {
  let current_value = field_common.extract_boolean_value(value)

  let field_name = path.get_field_name(field_path)

  html.div([attribute.class("formosh-field-wrapper formosh-checkbox-wrapper")], [
    html.div([attribute.class("formosh-checkbox-group")], [
      html.input([
        attribute.type_("checkbox"),
        attribute.id(field_name),
        attribute.name(field_name),
        attribute.checked(current_value),
        attribute.required(is_required),
        attribute.disabled(is_disabled),
        event.on_click(UpdateFieldPath(
          field_path,
          types.BooleanValue(!current_value),
        )),
      ]),
      field_common.render_label(field_name, property, is_required),
    ]),
    field_common.render_help_text(property),
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
  field_path: path.FieldPath,
  property: types.SchemaProperty,
  value: Option(types.Value),
  is_required: Bool,
  is_disabled: Bool,
) -> Element(FormMsg) {
  let current_value = field_common.extract_boolean_value(value)

  let field_name = path.get_field_name(field_path)

  html.div([attribute.class("formosh-field-wrapper")], [
    field_common.render_label(field_name, property, is_required),
    html.div([attribute.class("formosh-toggle-wrapper")], [
      html.button(
        [
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
          event.on_click(UpdateFieldPath(
            field_path,
            types.BooleanValue(!current_value),
          )),
        ],
        [
          html.span([attribute.class("formosh-toggle-slider")], []),
          html.span([attribute.class("formosh-toggle-text")], [
            html.text(case current_value {
              True -> "ON"
              False -> "OFF"
            }),
          ]),
        ],
      ),
    ]),
    field_common.render_help_text(property),
  ])
}
