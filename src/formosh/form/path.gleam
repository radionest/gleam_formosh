import formosh/path_format
import formosh/schema/types
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string

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

/// Parse a path-string back into a `FieldPath`.
///
/// Inverse of `to_string` for paths produced by it: segments separated by
/// `.`, with `[N]` denoting an array index. `to_string(from_string(s)) == s`
/// holds for any `s` originally produced by `to_string` (i.e. when field
/// names contain neither `.` nor `[]`). The empty string maps to `[]`.
pub fn from_string(s: String) -> FieldPath {
  case s {
    "" -> []
    _ ->
      string.split(s, ".")
      |> list.map(parse_segment)
  }
}

fn parse_segment(segment: String) -> PathSegment {
  // Require length > 2 so `"[]"` and similar empty brackets fall through
  // to `PropertySegment(segment)` instead of feeding an empty inner string
  // to `int.parse`. The documented round-trip with `to_string` only emits
  // `"[N]"` with N ≥ 0, so this guard only affects malformed input.
  case
    string.starts_with(segment, "[")
    && string.ends_with(segment, "]")
    && string.length(segment) > 2
  {
    True -> {
      let inner = string.slice(segment, 1, string.length(segment) - 2)
      case int.parse(inner) {
        Ok(i) -> ArraySegment(i)
        Error(_) -> PropertySegment(segment)
      }
    }
    False -> PropertySegment(segment)
  }
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

/// Convert a path to its canonical string form (e.g. `"lesions.[0].visible"`).
///
/// Delegates segment formatting to `formosh/path_format`, which is the single
/// source of truth shared with `formosh/schema/validator`.
pub fn to_string(path: FieldPath) -> String {
  path
  |> list.map(fn(segment) {
    case segment {
      PropertySegment(name) -> name
      ArraySegment(index) -> path_format.array_index_segment(index)
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

/// Get a value at a specific path from a Value.
pub fn get_at_path(value: types.Value, path: FieldPath) -> Option(types.Value) {
  case path {
    [] -> Some(value)
    [segment, ..rest] -> {
      case segment, value {
        PropertySegment(name), types.ObjectValue(fields) -> {
          case list.find(fields, fn(field) { field.0 == name }) {
            Ok(#(_key, value)) -> {
              get_at_path(value, rest)
            }
            Error(_) -> None
          }
        }
        ArraySegment(index), types.ArrayValue(items) -> {
          case get_list_item(items, index) {
            Some(item) -> {
              get_at_path(item, rest)
            }
            None -> None
          }
        }
        _, _ -> None
      }
    }
  }
}

/// Set a value at a specific path in a Value.
/// Creates intermediate structures as needed.
pub fn set_at_path(
  root: types.Value,
  path: FieldPath,
  value: types.Value,
) -> types.Value {
  modify_at_path(root, path, fn(_) { value })
}

/// Universal function for modifying a value at a path.
/// Takes a modifier function that is applied to the target value.
pub fn modify_at_path(
  root: types.Value,
  path: FieldPath,
  modifier: fn(types.Value) -> types.Value,
) -> types.Value {
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
  value: types.Value,
  field_name: String,
  modifier: fn(types.Value) -> types.Value,
) -> types.Value {
  let fields = get_object_fields(value)
  let current_value = get_field_value(fields, field_name)
  let new_value = modifier(current_value)
  let updated_fields = set_field_value(fields, field_name, new_value)
  types.ObjectValue(updated_fields)
}

/// Modifies an array item.
fn modify_array_item(
  value: types.Value,
  index: Int,
  modifier: fn(types.Value) -> types.Value,
) -> types.Value {
  let items = get_array_items(value)
  let padded = ensure_array_size(items, index + 1)
  let updated =
    list.index_map(padded, fn(item, i) {
      case i == index {
        True -> modifier(item)
        False -> item
      }
    })
  types.ArrayValue(updated)
}

// Helper functions for working with types
fn get_object_fields(value: types.Value) -> List(#(String, types.Value)) {
  case value {
    types.ObjectValue(fields) -> fields
    _ -> []
  }
}

fn get_array_items(value: types.Value) -> List(types.Value) {
  case value {
    types.ArrayValue(items) -> items
    _ -> []
  }
}

fn get_field_value(
  fields: List(#(String, types.Value)),
  name: String,
) -> types.Value {
  case list.find(fields, fn(f) { f.0 == name }) {
    Ok(#(_, value)) -> value
    Error(_) -> types.NullValue
  }
}

fn set_field_value(
  fields: List(#(String, types.Value)),
  name: String,
  value: types.Value,
) -> List(#(String, types.Value)) {
  case list.find(fields, fn(f) { f.0 == name }) {
    Ok(_) ->
      list.map(fields, fn(field) {
        case field.0 == name {
          True -> #(name, value)
          False -> field
        }
      })
    Error(_) -> list.append(fields, [#(name, value)])
  }
}

fn ensure_array_size(items: List(types.Value), size: Int) -> List(types.Value) {
  let current = list.length(items)
  case size > current {
    True -> list.append(items, list.repeat(types.NullValue, size - current))
    False -> items
  }
}

/// Add an item to an array at a specific path.
pub fn add_array_item_at_path(
  root: types.Value,
  path: FieldPath,
  item: types.Value,
) -> types.Value {
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
  root: types.Value,
  path: FieldPath,
  index: Int,
) -> types.Value {
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

/// After removing an item at `removed_index` from the array at `array_path`,
/// rewrite a touched/error FieldPath so it still points at the same logical
/// row.
///
/// Returns `None` when the path belonged to the removed row itself (callers
/// should drop it). Paths outside the array, or with array indices below the
/// removed index, pass through unchanged.
pub fn reindex_after_array_removal(
  path: FieldPath,
  array_path: FieldPath,
  removed_index: Int,
) -> Option(FieldPath) {
  case strip_prefix(path, array_path) {
    Some([ArraySegment(i), ..rest]) ->
      case int.compare(i, removed_index) {
        order.Eq -> None
        order.Lt -> Some(path)
        order.Gt -> Some(list.append(array_path, [ArraySegment(i - 1), ..rest]))
      }
    _ -> Some(path)
  }
}

/// Move an array item from `from` to `to` within the array at `path`.
///
/// No-op when `from == to` or when either index is outside `0..length-1`.
pub fn move_array_item_at_path(
  root: types.Value,
  path: FieldPath,
  from: Int,
  to: Int,
) -> types.Value {
  modify_at_path(root, path, fn(value) {
    case value {
      types.ArrayValue(items) -> {
        let len = list.length(items)
        case from == to || from < 0 || to < 0 || from >= len || to >= len {
          True -> value
          False ->
            case list_remove_at(items, from) {
              Some(#(moved, rest)) ->
                types.ArrayValue(list_insert_at(rest, to, moved))
              None -> value
            }
        }
      }
      _ -> value
    }
  })
}

fn list_remove_at(items: List(a), index: Int) -> Option(#(a, List(a))) {
  case items, index {
    [], _ -> None
    [first, ..rest], 0 -> Some(#(first, rest))
    [first, ..rest], n if n > 0 ->
      case list_remove_at(rest, n - 1) {
        Some(#(removed, remaining)) -> Some(#(removed, [first, ..remaining]))
        None -> None
      }
    _, _ -> None
  }
}

fn list_insert_at(items: List(a), index: Int, item: a) -> List(a) {
  case items, index {
    _, 0 -> [item, ..items]
    [], _ -> [item]
    [first, ..rest], n if n > 0 -> [first, ..list_insert_at(rest, n - 1, item)]
    _, _ -> [item, ..items]
  }
}

/// After moving an item from `from` to `to` within the array at `array_path`,
/// rewrite a touched/error FieldPath so it still points at the same logical
/// row. A move never drops a path, so this always returns a path.
pub fn reindex_after_array_move(
  path: FieldPath,
  array_path: FieldPath,
  from: Int,
  to: Int,
) -> FieldPath {
  case strip_prefix(path, array_path) {
    Some([ArraySegment(i), ..rest]) -> {
      let new_i = case i == from {
        True -> to
        False ->
          case int.compare(from, to) {
            order.Lt ->
              case i > from && i <= to {
                True -> i - 1
                False -> i
              }
            order.Gt ->
              case i >= to && i < from {
                True -> i + 1
                False -> i
              }
            order.Eq -> i
          }
      }
      list.append(array_path, [ArraySegment(new_i), ..rest])
    }
    _ -> path
  }
}

fn strip_prefix(path: FieldPath, prefix: FieldPath) -> Option(FieldPath) {
  case prefix, path {
    [], rest -> Some(rest)
    [p, ..ps], [q, ..qs] ->
      case p == q {
        True -> strip_prefix(qs, ps)
        False -> None
      }
    _, _ -> None
  }
}
