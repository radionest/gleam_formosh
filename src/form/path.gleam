import form/converter
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import schema/types

/// Represents a path to a field in a nested data structure.
/// This allows addressing fields at any depth, including nested objects and arrays.
pub type FieldPath =
  List(PathSegment)

/// A single segment in a field path.
pub type PathSegment {
  /// References a property by name (e.g., "lesions" or "description")
  PropertySegment(name: String)
  /// References an array element by index (e.g., [0] or [2])
  ArraySegment(index: Int)
}

/// Create a path from a simple field name.
pub fn from_field_name(field_name: String) -> FieldPath {
  [PropertySegment(field_name)]
}

/// Create a path to an array item's field.
pub fn to_array_item_field(
  array_name: String,
  index: Int,
  field_name: String,
) -> FieldPath {
  [
    PropertySegment(array_name),
    ArraySegment(index),
    PropertySegment(field_name),
  ]
}

/// Convert a path to a human-readable string for debugging.
pub fn to_string(path: FieldPath) -> String {
  path
  |> list.map(fn(segment) {
    case segment {
      PropertySegment(name) -> name
      ArraySegment(index) -> "[" <> int.to_string(index) <> "]"
    }
  })
  |> string.join(".")
}

/// Get the field name from a path (the last property segment).
/// 
/// This is useful for extracting the display name of a field from its path.
/// For array items, returns the field name within the array item.
/// 
/// ## Examples
/// - `[PropertySegment("email")]` -> `Some("email")`
/// - `[PropertySegment("items"), ArraySegment(0), PropertySegment("name")]` -> `Some("name")`
/// - `[ArraySegment(0)]` -> `None`
pub fn get_field_name(path: FieldPath) -> String {
  case list.last(path) {
    Ok(PropertySegment(name)) -> name
    Ok(ArraySegment(_)) -> "field"
    Error(_) -> "field"
  }
}

/// Helper function to get an item from a list by index.
fn get_list_item(items: List(a), index: Int) -> Option(a) {
  case index, items {
    0, [first, ..] -> Some(first)
    n, [_, ..rest] if n > 0 -> get_list_item(rest, n - 1)
    _, _ -> None
  }
}

/// Get a value at a specific path from a FieldValue.
pub fn get_at_path(
  value: types.FieldValue,
  path: FieldPath,
) -> Option(types.FieldValue) {
  case path {
    [] -> Some(value)
    [segment, ..rest] -> {
      case segment, value {
        PropertySegment(name), types.ObjectValue(fields) -> {
          case list.find(fields, fn(field) { field.0 == name }) {
            Ok(#(_key, json_value)) -> {
              json_value
              |> converter.json_to_field_value
              |> option.then(fn(field_value) { get_at_path(field_value, rest) })
            }
            Error(_) -> None
          }
        }
        ArraySegment(index), types.ArrayValue(items) -> {
          case get_list_item(items, index) {
            Some(item) -> {
              item
              |> converter.json_to_field_value
              |> option.then(fn(field_value) { get_at_path(field_value, rest) })
            }
            None -> None
          }
        }
        _, _ -> None
      }
    }
  }
}

/// Set a value at a specific path in a FieldValue.
/// Creates intermediate structures as needed.
pub fn set_at_path(
  root: types.FieldValue,
  path: FieldPath,
  value: types.FieldValue,
) -> types.FieldValue {
  modify_at_path(root, path, fn(_) { value })
}

/// Universal function for modifying a value at a path.
/// Takes a modifier function that is applied to the target value.
pub fn modify_at_path(
  root: types.FieldValue,
  path: FieldPath,
  modifier: fn(types.FieldValue) -> types.FieldValue,
) -> types.FieldValue {
  case path {
    [] -> modifier(root)
    [segment, ..rest] -> {
      case segment {
        PropertySegment(name) ->
          modify_object_field(root, name, fn(field_value) {
            modify_at_path(field_value, rest, modifier)
          })

        ArraySegment(index) ->
          modify_array_item(root, index, fn(item_value) {
            modify_at_path(item_value, rest, modifier)
          })
      }
    }
  }
}

/// Modifies a field in an object.
fn modify_object_field(
  value: types.FieldValue,
  field_name: String,
  modifier: fn(types.FieldValue) -> types.FieldValue,
) -> types.FieldValue {
  let fields = get_object_fields(value)
  let current_value = get_field_value(fields, field_name)
  let new_value = modifier(current_value)
  let updated_fields = set_field_value(fields, field_name, new_value)
  types.ObjectValue(updated_fields)
}

/// Modifies an array item.
fn modify_array_item(
  value: types.FieldValue,
  index: Int,
  modifier: fn(types.FieldValue) -> types.FieldValue,
) -> types.FieldValue {
  let items = get_array_items(value)
  let padded = ensure_array_size(items, index + 1)
  let updated =
    list.index_map(padded, fn(item, i) {
      case i == index {
        True ->
          converter.field_value_to_json_value(
            modifier(converter.json_to_field_value_safe(item)),
          )
        False -> item
      }
    })
  types.ArrayValue(updated)
}

// Helper functions for working with types
fn get_object_fields(
  value: types.FieldValue,
) -> List(#(String, types.JsonValue)) {
  case value {
    types.ObjectValue(fields) -> fields
    _ -> []
  }
}

fn get_array_items(value: types.FieldValue) -> List(types.JsonValue) {
  case value {
    types.ArrayValue(items) -> items
    _ -> []
  }
}

fn get_field_value(
  fields: List(#(String, types.JsonValue)),
  name: String,
) -> types.FieldValue {
  case list.find(fields, fn(f) { f.0 == name }) {
    Ok(#(_, json)) -> converter.json_to_field_value_safe(json)
    Error(_) -> types.NullValue
  }
}

fn set_field_value(
  fields: List(#(String, types.JsonValue)),
  name: String,
  value: types.FieldValue,
) -> List(#(String, types.JsonValue)) {
  let json_value = converter.field_value_to_json_value(value)
  case list.find(fields, fn(f) { f.0 == name }) {
    Ok(_) ->
      list.map(fields, fn(field) {
        case field.0 == name {
          True -> #(name, json_value)
          False -> field
        }
      })
    Error(_) -> list.append(fields, [#(name, json_value)])
  }
}

fn ensure_array_size(
  items: List(types.JsonValue),
  size: Int,
) -> List(types.JsonValue) {
  let current = list.length(items)
  case size > current {
    True -> list.append(items, list.repeat(types.JsonNull, size - current))
    False -> items
  }
}

/// Add an item to an array at a specific path.
pub fn add_array_item_at_path(
  root: types.FieldValue,
  path: FieldPath,
  item: types.JsonValue,
) -> types.FieldValue {
  modify_at_path(root, path, fn(value) {
    // Simple logic: if this is an array - add element
    case value {
      types.ArrayValue(items) -> types.ArrayValue(list.append(items, [item]))
      _ -> types.ArrayValue([item])
    }
  })
}

/// Remove an item from an array at a specific path.
pub fn remove_array_item_at_path(
  root: types.FieldValue,
  path: FieldPath,
  index: Int,
) -> types.FieldValue {
  modify_at_path(root, path, fn(value) {
    case value {
      types.ArrayValue(items) -> {
        let filtered =
          list.index_fold(items, [], fn(acc, item, i) {
            case i == index {
              True -> acc
              False -> list.append(acc, [item])
            }
          })
        types.ArrayValue(filtered)
      }
      _ -> value
    }
  })
}
