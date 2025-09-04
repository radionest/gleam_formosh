// Number and integer field renderer

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import form/model.{type FormMsg, FieldBlurred, FieldChanged}
import schema/types

// Render a number or integer field
pub fn render(
  field_name: String,
  property: types.SchemaProperty,
  value: Option(types.FieldValue),
  is_required: Bool,
  is_disabled: Bool,
) -> Element(FormMsg) {
  let is_integer = case property.field_type {
    Some(types.IntegerType) -> True
    _ -> False
  }

  let current_value = case value {
    Some(types.NumberValue(n)) -> float.to_string(n)
    Some(types.IntegerValue(i)) -> int.to_string(i)
    _ -> ""
  }

  html.div([attribute.class("formosh-field-wrapper")], [
    render_label(field_name, property, is_required),
    html.input([
      attribute.id(field_name),
      attribute.name(field_name),
      attribute.type_("number"),
      attribute.value(current_value),
      attribute.class("formosh-input formosh-number"),
      attribute.required(is_required),
      attribute.disabled(is_disabled),
      case is_integer {
        True -> attribute.step("1")
        False -> attribute.step("any")
      },
      event.on_input(fn(val) {
        handle_number_input(field_name, val, is_integer)
      }),
      event.on_blur(FieldBlurred(field_name)),
      ..get_number_constraints_attributes(property),
    ]),
    render_help_text(property),
  ])
}

// Handle number input and conversion
fn handle_number_input(
  field_name: String,
  value: String,
  is_integer: Bool,
) -> FormMsg {
  case value {
    "" -> FieldChanged(field_name, types.NullValue)
    str -> {
      case is_integer {
        True -> {
          case int.parse(str) {
            Ok(i) -> FieldChanged(field_name, types.IntegerValue(i))
            Error(_) -> FieldChanged(field_name, types.StringValue(str))
          }
        }
        False -> {
          case float.parse(str) {
            Ok(f) -> FieldChanged(field_name, types.NumberValue(f))
            Error(_) -> {
              // Try parsing as integer and convert
              case int.parse(str) {
                Ok(i) -> FieldChanged(field_name, types.NumberValue(int.to_float(i)))
                Error(_) -> FieldChanged(field_name, types.StringValue(str))
              }
            }
          }
        }
      }
    }
  }
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

// Get HTML attributes for number constraints
fn get_number_constraints_attributes(
  property: types.SchemaProperty,
) -> List(attribute.Attribute(FormMsg)) {
  case property.number_constraints {
    Some(constraints) -> {
      let attrs = []
      
      let attrs = case constraints.minimum {
        Some(min) ->
          list.append(attrs, [attribute.min(float.to_string(min))])
        None -> attrs
      }
      
      let attrs = case constraints.maximum {
        Some(max) ->
          list.append(attrs, [attribute.max(float.to_string(max))])
        None -> attrs
      }
      
      // For exclusive constraints, we adjust the min/max slightly
      let attrs = case constraints.exclusive_minimum {
        Some(min) -> {
          // Use slightly higher value for HTML min attribute
          let adjusted = min +. 0.000001
          list.append(attrs, [attribute.min(float.to_string(adjusted))])
        }
        None -> attrs
      }
      
      let attrs = case constraints.exclusive_maximum {
        Some(max) -> {
          // Use slightly lower value for HTML max attribute
          let adjusted = max -. 0.000001
          list.append(attrs, [attribute.max(float.to_string(adjusted))])
        }
        None -> attrs
      }
      
      let attrs = case constraints.multiple_of {
        Some(step) ->
          list.append(attrs, [attribute.step(float.to_string(step))])
        None -> attrs
      }
      
      attrs
    }
    None -> []
  }
}