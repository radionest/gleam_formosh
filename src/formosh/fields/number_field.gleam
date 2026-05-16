/// Number and integer field renderer.
///
/// Renders numeric input fields for both integer and floating-point types
/// with min/max/step constraints from the schema.
import formosh/fields/field_common.{type FieldRenderCtx}
import formosh/form/model.{type FormMsg, UpdateFieldPath}
import formosh/form/path
import formosh/schema/types
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// Render a number or integer input field.
///
/// ## Features
/// - Integer vs decimal input (step="1" vs step="any")
/// - Min/max value constraints from schema
/// - Exclusive min/max handling
/// - Multiple-of (step) constraints
pub fn render(ctx: FieldRenderCtx) -> Element(FormMsg) {
  let is_integer = case ctx.property.field_type {
    Some(types.IntegerType) -> True
    _ -> False
  }

  let current_value = field_common.extract_number_value(ctx.value)
  let field_name = path.get_field_name(ctx.path)

  // Build constraint attributes
  let constraint_attrs = get_number_constraints_attributes(ctx.property)

  // Add readonly attribute if needed
  let readonly_attrs = case ctx.is_readonly {
    True -> [attribute.attribute("readonly", "readonly")]
    False -> []
  }

  let placeholder_attrs = case ctx.hints.placeholder {
    Some(p) -> [attribute.attribute("placeholder", p)]
    None -> []
  }
  let autofocus_attrs = case ctx.hints.autofocus {
    Some(True) -> [attribute.attribute("autofocus", "")]
    _ -> []
  }

  html.div(
    [
      attribute.class("formosh-field-wrapper"),
      attribute.attribute("part", "field-wrapper"),
    ],
    [
      field_common.render_label(
        field_name: field_name,
        property: ctx.property,
        is_required: ctx.is_required,
        hints: ctx.hints,
      ),
      html.input(
        list.flatten([
          [
            attribute.id(path.to_string(ctx.path)),
            attribute.name(field_name),
            attribute.type_("number"),
            attribute.value(current_value),
            attribute.class("formosh-input formosh-number"),
            attribute.attribute("part", "input number"),
            attribute.required(ctx.is_required),
            attribute.disabled(ctx.is_disabled),
            case is_integer {
              True -> attribute.step("1")
              False -> attribute.step("any")
            },
            event.on_change(fn(val) {
              handle_number_input(ctx.path, val, is_integer)
            }),
          ],
          constraint_attrs,
          readonly_attrs,
          placeholder_attrs,
          autofocus_attrs,
        ]),
      ),
      field_common.render_help_text(ctx.property, ctx.hints),
    ],
  )
}

/// Handle numeric input parsing and conversion to appropriate field value.
/// 
/// Parses user input and converts it to the appropriate Value type
/// (IntegerValue or NumberValue) based on the field type. Invalid input
/// is temporarily stored as StringValue for validation to handle.
/// 
/// ## Parameters
/// - `field_name`: The field name for the resulting message
/// - `value`: The raw string input from the user
/// - `is_integer`: Whether this should be parsed as integer or float
/// 
/// ## Returns
/// A FieldChanged message with the appropriate Value
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
