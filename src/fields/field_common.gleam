// Common field rendering utilities

import gleam/option.{None, Some}
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import form/model.{type FormMsg, FieldBlurred, FieldChanged}
import schema/types

// Render field label
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

// Render help text
pub fn render_help_text(property: types.SchemaProperty) -> Element(FormMsg) {
  case property.description {
    Some(desc) ->
      html.div([attribute.class("formosh-help")], [
        html.text(desc),
      ])
    None -> html.text("")
  }
}

// Create field wrapper
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

// Common input attributes
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