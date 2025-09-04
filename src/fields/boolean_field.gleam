// Boolean field renderer

import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import form/model.{type FormMsg, FieldBlurred, FieldChanged}
import schema/types

// Render a boolean field
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

// Render boolean as radio buttons
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

// Alternative: Render as checkbox
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

// Alternative: Render as toggle switch
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

// Render field label
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

// Render checkbox label (positioned after the checkbox)
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

// Render help text
fn render_help_text(property: types.SchemaProperty) -> Element(FormMsg) {
  case property.description {
    Some(desc) ->
      html.div([attribute.class("formosh-help")], [
        html.text(desc),
      ])
    None -> html.text("")
  }
}