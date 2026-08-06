//// Turning a stored `Value` into display text: the shared rules for review
//// rows, review tables and collapsed array-row summaries.
////
//// Lives outside both `readonly_field` and the editable widgets so no
//// renderer has to re-derive them — `readonly_field.gleam` previously carried
//// a deliberate copy of `string_field.extract_one_of_options`, and a third
//// copy is what this module exists to prevent. Password masking lives here
//// too, so a new display position cannot bypass it.

import formosh/schema/types.{type RenderHints, type SchemaProperty, type Value}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const dash = "—"

pub const password_mask = "••••••••"

/// Visible text for a field label: `hints.title` (UiSchema override) wins
/// over `property.title` (JSON Schema), which in turn wins over the field
/// name with underscores replaced by spaces and capitalised.
pub fn label_text(
  field_name: String,
  property: SchemaProperty,
  hints: RenderHints,
) -> String {
  case hints.title, property.title {
    Some(t), _ -> t
    None, Some(t) -> t
    None, None -> field_name |> string.replace("_", " ") |> string.capitalise()
  }
}

/// True when a field should be masked — either the schema declares
/// `format: "password"` or a `ui:widget: "password"` hint applies. The mask is
/// a fixed string: a length-proportional one would leak the value's length.
pub fn is_password(property: SchemaProperty, hints: RenderHints) -> Bool {
  let by_widget = hints.widget == Some(types.CustomWidget("password"))
  let by_format = case property.string_constraints {
    Some(constraints) -> constraints.format == Some(types.PasswordFormat)
    None -> False
  }
  by_widget || by_format
}

/// Format a leaf value for display, mapping enum codes to their oneOf label
/// and masking password fields.
pub fn display_value(
  property: SchemaProperty,
  hints: RenderHints,
  value: Option(Value),
) -> String {
  case value {
    None | Some(types.NullValue) -> dash
    Some(v) ->
      case is_password(property, hints), v {
        True, types.StringValue("") -> dash
        True, _ -> password_mask
        False, _ ->
          case enum_label(property, v) {
            Some(label) -> label
            None -> scalar_to_string(v)
          }
      }
  }
}

pub fn scalar_to_string(value: Value) -> String {
  case value {
    types.StringValue("") -> dash
    types.StringValue(s) -> s
    types.IntegerValue(i) -> int.to_string(i)
    types.NumberValue(n) -> float.to_string(n)
    types.BooleanValue(True) -> "Yes"
    types.BooleanValue(False) -> "No"
    types.NullValue -> dash
    types.ArrayValue(_) | types.ObjectValue(_) -> dash
  }
}

/// Resolve a stored enum code to its human label via `oneOf` const+title
/// options. Plain `enum` lists carry no labels (the code *is* the label), so
/// they fall through to `scalar_to_string`.
pub fn enum_label(property: SchemaProperty, value: Value) -> Option(String) {
  case property.one_of {
    Some(schemas) -> {
      let target = scalar_to_string(value)
      one_of_options(schemas)
      |> list.find(fn(opt) { opt.0 == target })
      |> result.map(fn(opt) { opt.1 })
      |> option.from_result
    }
    None -> None
  }
}

fn one_of_options(one_of: List(SchemaProperty)) -> List(#(String, String)) {
  use schema <- list.filter_map(one_of)
  use vals <- result.try(option.to_result(schema.enum_values, Nil))
  use const_val <- result.try(case vals {
    [val] -> Ok(val)
    _ -> Error(Nil)
  })
  let value = scalar_to_string(const_val)
  Ok(#(value, option.unwrap(schema.title, value)))
}
