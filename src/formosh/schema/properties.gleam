/// Operations over JSON Schema's `properties` list.
///
/// `JsonSchema.properties` and `SchemaProperty.properties` are stored as
/// `List(#(String, SchemaProperty))` — an ordered list of key/value pairs
/// — to preserve the schema author's declared field order, which the
/// renderer relies on. Never convert this list to a `Dict`; ordering is
/// part of the contract.
///
/// This module is the single owner of property-list operations. Other
/// modules should look up, check, and merge property lists through here
/// rather than calling `list.key_find` or hand-rolling merge logic.
import formosh/schema/types.{type SchemaProperty}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

pub type PropertyList =
  List(#(String, SchemaProperty))

/// Look up a property by key.
pub fn get(properties: PropertyList, key: String) -> Option(SchemaProperty) {
  list.key_find(properties, key) |> option.from_result
}

/// Check whether a property with the given key exists.
pub fn has_key(properties: PropertyList, key: String) -> Bool {
  list.key_find(properties, key) |> result.is_ok
}

/// Return the property keys in declared order.
pub fn keys(properties: PropertyList) -> List(String) {
  list.map(properties, fn(pair) { pair.0 })
}

/// Return the underlying list of entries. Identity over the type alias;
/// kept for symmetry with `from_pairs` and as an explicit "leave the
/// module" point for callers that need the raw list (e.g. `list.map`
/// over entries).
pub fn to_list(properties: PropertyList) -> List(#(String, SchemaProperty)) {
  properties
}

/// Build a `PropertyList` from key/value pairs. Identity over the type
/// alias; kept as an explicit "enter the module" point and for symmetry
/// with `to_list`.
pub fn from_pairs(pairs: List(#(String, SchemaProperty))) -> PropertyList {
  pairs
}

/// Merge two ordered property lists.
///
/// Existing keys keep their position but receive the override value from
/// `additions`. Keys only present in `additions` are appended at the end,
/// preserving their relative order — and deduplicated so a key cannot
/// surface twice in the rendered form. This matches the typical UX for
/// conditional fields: static fields stay where authored, dynamic ones
/// surface after them.
pub fn merge(base: PropertyList, additions: PropertyList) -> PropertyList {
  let deduped_additions = dedup_by_key(additions)
  let #(base_keys, updated_base) =
    list.map_fold(base, [], fn(seen, entry) {
      let #(key, _) = entry
      let merged = case list.key_find(deduped_additions, key) {
        Ok(new_prop) -> #(key, new_prop)
        Error(_) -> entry
      }
      #([key, ..seen], merged)
    })
  let new_only =
    list.filter(deduped_additions, fn(entry) {
      !list.contains(base_keys, entry.0)
    })
  list.append(updated_base, new_only)
}

/// Reorder an ordered key/value list according to a `ui:order` list.
///
/// Generic over the value type so it can be applied to any ordered list of
/// `#(String, _)` entries — primarily `PropertyList`, but also UiSchema
/// children and arbitrary test fixtures. Keys listed in `order` come first
/// in the given sequence; everything else follows in its original position.
/// Unknown keys in `order` (not present in `entries`) are silently dropped.
/// Returns the input unchanged when `order` is `None`.
pub fn apply_order(
  entries: List(#(String, a)),
  order: Option(List(String)),
) -> List(#(String, a)) {
  case order {
    None -> entries
    Some(ordered_keys) -> {
      let ordered =
        list.filter_map(ordered_keys, fn(key) {
          list.key_find(entries, key)
          |> result.map(fn(value) { #(key, value) })
        })
      let unordered =
        list.filter(entries, fn(entry) { !list.contains(ordered_keys, entry.0) })
      list.append(ordered, unordered)
    }
  }
}

/// Keep only the first occurrence of each key, preserving order.
fn dedup_by_key(entries: PropertyList) -> PropertyList {
  let #(_, reversed) =
    list.fold(entries, #([], []), fn(state, entry) {
      let #(seen, acc) = state
      case list.contains(seen, entry.0) {
        True -> state
        False -> #([entry.0, ..seen], [entry, ..acc])
      }
    })
  list.reverse(reversed)
}
