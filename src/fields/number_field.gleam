/// Number and integer field renderer.
/// 
/// This module handles rendering of numeric input fields for both integer
/// and floating-point number types, with support for various numeric
/// constraints like min/max values and step increments.
import fields/field_common
import form/model.{type FormMsg, UpdateFieldPath}
import form/path
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import schema/types

/// Render a number or integer input field.
/// 
/// Creates an HTML number input with appropriate constraints and validation.
/// Automatically determines whether to use integer or decimal input based
/// on the field type in the schema property.
/// 
/// ## Parameters
/// - `field_name`: The field name for identification
/// - `property`: Schema property containing type and numeric constraints
/// - `value`: Current field value (NumberValue or IntegerValue)
/// - `is_required`: Whether the field is required
/// - `is_disabled`: Whether the field is disabled
/// 
/// ## Returns
/// A complete number input field with label, input, and help text
/// 
/// ## Features
/// - Integer vs decimal input (step="1" vs step="any")
/// - Min/max value constraints from schema
/// - Exclusive min/max handling
/// - Multiple-of (step) constraints
/// - Proper numeric parsing and validation
pub fn render(
  field_path: path.FieldPath,
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

  let field_name = path.get_field_name(field_path) |> option.unwrap("field")

  html.div([attribute.class("formosh-field-wrapper")], [
    field_common.render_label(field_name, property, is_required),
    html.input([
      attribute.id(path.to_string(field_path)),
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
        handle_number_input(field_path, val, is_integer)
      }),
      ..get_number_constraints_attributes(property)
    ]),
    field_common.render_help_text(property),
  ])
}

/// Handle numeric input parsing and conversion to appropriate field value.
/// 
/// Parses user input and converts it to the appropriate FieldValue type
/// (IntegerValue or NumberValue) based on the field type. Invalid input
/// is temporarily stored as StringValue for validation to handle.
/// 
/// ## Parameters
/// - `field_name`: The field name for the resulting message
/// - `value`: The raw string input from the user
/// - `is_integer`: Whether this should be parsed as integer or float
/// 
/// ## Returns
/// A FieldChanged message with the appropriate FieldValue
/// 
/// ## Parsing Logic
/// - Empty string → NullValue
/// - Integer fields: parse as int → IntegerValue or StringValue if invalid
/// - Number fields: parse as float, fallback to int, then StringValue if invalid
fn handle_number_input(
  field_path: path.FieldPath,
  value: String,
  is_integer: Bool,
) -> FormMsg {
  case value {
    "" -> UpdateFieldPath(field_path, types.NullValue)
    str -> {
      case is_integer {
        True -> {
          case int.parse(str) {
            Ok(i) -> UpdateFieldPath(field_path, types.IntegerValue(i))
            Error(_) -> UpdateFieldPath(field_path, types.StringValue(str))
          }
        }
        False -> {
          case float.parse(str) {
            Ok(f) -> UpdateFieldPath(field_path, types.NumberValue(f))
            Error(_) -> {
              // Try parsing as integer and convert
              case int.parse(str) {
                Ok(i) ->
                  UpdateFieldPath(
                    field_path,
                    types.NumberValue(int.to_float(i)),
                  )
                Error(_) -> UpdateFieldPath(field_path, types.StringValue(str))
              }
            }
          }
        }
      }
    }
  }
}
/// Convert numeric constraints to HTML input attributes.
/// 
/// Takes numeric validation constraints from the JSON Schema and converts
/// them to appropriate HTML5 number input attributes for client-side validation.
/// 
/// ## Parameters
/// - `property`: Schema property containing numeric constraints
/// 
/// ## Returns
/// List of HTML attributes representing the numeric constraints
/// 
/// ## Generated Attributes
/// - `min`/`max`: From minimum/maximum constraints
/// - `min`/`max`: From exclusive constraints (adjusted by small epsilon)
/// - `step`: From multipleOf constraint
/// 
/// ## Exclusive Constraints
/// Since HTML doesn't support exclusive min/max directly, we adjust
/// the values by a small epsilon (0.000001) to approximate the constraint.
fn get_number_constraints_attributes(
  property: types.SchemaProperty,
) -> List(attribute.Attribute(FormMsg)) {
  case property.number_constraints {
    Some(constraints) -> {
      let attrs = []

      let attrs = case constraints.minimum {
        Some(min) -> list.append(attrs, [attribute.min(float.to_string(min))])
        None -> attrs
      }

      let attrs = case constraints.maximum {
        Some(max) -> list.append(attrs, [attribute.max(float.to_string(max))])
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
