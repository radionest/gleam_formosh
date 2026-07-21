//// Apply JSON Schema `default` values recursively when initialising a form.
////
//// The form root is always a single `ObjectValue` tree (see `model.FormModel`
//// invariant), so this module operates on that shape end-to-end. Defaults are
//// applied at init and reset time; once the user starts editing, conditional
//// branches and array items hydrate without re-running this pass.

import formosh/form/path.{type FieldPath, ArraySegment, PropertySegment}
import formosh/form/union_resolver
import formosh/schema/types.{
  type SchemaProperty, type Value, ArrayType, ArrayValue, NullValue, ObjectType,
  ObjectValue,
}
import gleam/list
import gleam/option

/// Merge JSON Schema defaults into a hierarchical Value. Each declared
/// property is walked: existing non-null entries are kept; missing or
/// NullValue entries are filled from `property.default` (or, for ObjectType,
/// from a synthesised inner default tree). Caller-supplied keys not declared
/// in the schema are preserved verbatim and appended after the declared
/// block, matching the previous Dict-based ordering guarantee.
///
/// Form storage is one ObjectValue tree by construction (init/reset build
/// one; every handler writes Value back through `path.set_at_path`), so the
/// `let assert` enforces the invariant: a scalar or array at the form root
/// would be a programming error, not a runtime data shape we silently fall
/// back to.
pub fn apply_schema_defaults(
  properties: List(#(String, SchemaProperty)),
  value: Value,
) -> Value {
  let assert ObjectValue(fields) = value
  ObjectValue(merge_property_defaults(properties, fields))
}

// Walk the declared properties in schema order, materialising each entry's
// post-default value, then append any extra keys (additionalProperties,
// legacy fields) in their original order. NullValue is treated as "absent"
// so a schema `default` can fill it — see `apply_schema_defaults` doc for
// why this only applies during init/reset.
fn merge_property_defaults(
  properties: List(#(String, SchemaProperty)),
  fields: List(#(String, Value)),
) -> List(#(String, Value)) {
  let declared =
    list.filter_map(properties, fn(pair) {
      let #(field_name, property) = pair
      let current = case list.key_find(fields, field_name) {
        Ok(NullValue) -> option.None
        Ok(v) -> option.Some(v)
        Error(_) -> option.None
      }
      case apply_defaults_to_value(property, current) {
        option.Some(v) -> Ok(#(field_name, v))
        option.None -> Error(Nil)
      }
    })
  let declared_names = list.map(properties, fn(pair) { pair.0 })
  let extras =
    list.filter(fields, fn(pair) { !list.contains(declared_names, pair.0) })
  list.append(declared, extras)
}

// Compute the post-default value for a single field. Returns None when the
// field has no current value and no schema default would produce one
// (so the caller leaves the key absent rather than inserting an empty hole).
fn apply_defaults_to_value(
  property: SchemaProperty,
  current: option.Option(Value),
) -> option.Option(Value) {
  case current {
    option.None -> defaults_for_missing(property)
    option.Some(ObjectValue(fields)) ->
      option.Some(merge_object_defaults(property, fields))
    option.Some(ArrayValue(items)) ->
      option.Some(map_array_item_defaults(property, items))
    option.Some(other) -> option.Some(other)
  }
}

// Build a value for a field that currently has nothing set:
// prefer `property.default`, otherwise synthesise an ObjectValue from
// sub-property defaults (so a missing nested object can still surface its
// inner defaults). Arrays are NOT auto-populated — without a hydrated
// array we cannot guess how many items to create.
fn defaults_for_missing(property: SchemaProperty) -> option.Option(Value) {
  case property.default {
    option.Some(d) -> option.Some(d)
    option.None ->
      case property.field_type, property.properties {
        option.Some(ObjectType), option.Some(sub_props) -> {
          let built =
            list.filter_map(sub_props, fn(pair) {
              let #(name, sub_prop) = pair
              case apply_defaults_to_value(sub_prop, option.None) {
                option.Some(v) -> Ok(#(name, v))
                option.None -> Error(Nil)
              }
            })
          case built {
            [] -> option.None
            _ -> option.Some(ObjectValue(built))
          }
        }
        _, _ -> option.None
      }
  }
}

// Recurse into an existing ObjectValue, filling missing sub-fields from
// their defaults. Delegates to `merge_property_defaults` so schema order
// and extra-key preservation are handled in a single place.
fn merge_object_defaults(
  property: SchemaProperty,
  fields: List(#(String, Value)),
) -> Value {
  case property.properties {
    option.Some(sub_props) ->
      ObjectValue(merge_property_defaults(sub_props, fields))
    option.None -> ObjectValue(fields)
  }
}

// Recurse into each existing array item using the items-schema. We do not
// create new items — defaults only apply inside elements the caller
// already hydrated. `apply_defaults_to_value` is total for any
// `Some(_)` input, so we can `let assert` the result.
fn map_array_item_defaults(
  property: SchemaProperty,
  items: List(Value),
) -> Value {
  case property.items {
    option.Some(item_schema) ->
      ArrayValue(
        list.map(items, fn(item) {
          let assert option.Some(v) =
            apply_defaults_to_value(item_schema, option.Some(item))
          v
        }),
      )
    option.None -> ArrayValue(items)
  }
}

/// Build a fresh array row from the array's `items` schema: object items
/// get an `ObjectValue` with field `default`s applied (empty object when
/// no default exists anywhere), scalar items get their `default` or
/// `NullValue`. Shared by the add-item handler and `ensure_min_items` so
/// manual and auto-created rows hydrate identically.
pub fn new_array_item(item_schema: SchemaProperty) -> Value {
  case defaults_for_missing(item_schema) {
    option.Some(v) -> v
    option.None ->
      case item_schema.field_type {
        option.Some(ObjectType) -> ObjectValue([])
        _ -> NullValue
      }
  }
}

/// Top up every array in the value tree to its `minItems` row count,
/// walking values in parallel with the (resolved-)schema `properties`.
/// At each array row the item schema is re-resolved against the row's
/// own values (mirroring the validator and renderer), so arrays revealed
/// by per-row `if/then` conditionals are created too.
///
/// Idempotent. Never removes surplus rows and never mutates existing
/// rows — it only appends `new_array_item` rows, and creates the array
/// value itself when a `minItems > 0` array has no value yet. Same root
/// invariant as `apply_schema_defaults`: the form root is one ObjectValue.
///
/// `selected` carries the active union branch per field path (design D4,
/// openspec/changes/add-anyof-union-support) — threaded down so a row whose
/// `anyOf` member materializes to an array with its own `minItems` gets
/// topped up too. An internal `parent_path` accumulator (extended with
/// `PropertySegment`/`ArraySegment` as the walk descends) builds the
/// absolute path each row/field needs to look itself up in `selected`.
pub fn ensure_min_items(
  properties: List(#(String, SchemaProperty)),
  values: Value,
  selected: List(#(FieldPath, Int)),
) -> Value {
  let assert ObjectValue(fields) = values
  ObjectValue(ensure_fields(properties, [], fields, selected))
}

// Fold the declared properties over the current fields; undeclared keys
// pass through untouched, keys are only (re)written when the subtree
// walk produced a value.
fn ensure_fields(
  properties: List(#(String, SchemaProperty)),
  parent_path: FieldPath,
  fields: List(#(String, Value)),
  selected: List(#(FieldPath, Int)),
) -> List(#(String, Value)) {
  list.fold(properties, fields, fn(acc, pair) {
    let #(name, property) = pair
    let current = option.from_result(list.key_find(acc, name))
    let field_path = list.append(parent_path, [PropertySegment(name)])
    case ensure_property(property, field_path, current, selected) {
      option.Some(new_value) -> list.key_set(acc, name, new_value)
      option.None -> acc
    }
  })
}

// None = leave the key alone (absent keys stay absent); Some = write.
fn ensure_property(
  property: SchemaProperty,
  field_path: FieldPath,
  current: option.Option(Value),
  selected: List(#(FieldPath, Int)),
) -> option.Option(Value) {
  case property.field_type {
    option.Some(ArrayType) ->
      ensure_array(property, field_path, current, selected)
    option.Some(ObjectType) ->
      case current, property.properties {
        option.Some(ObjectValue(fields)), option.Some(sub_props) ->
          option.Some(
            ObjectValue(ensure_fields(sub_props, field_path, fields, selected)),
          )
        _, _ -> option.None
      }
    _ -> option.None
  }
}

fn ensure_array(
  property: SchemaProperty,
  field_path: FieldPath,
  current: option.Option(Value),
  selected: List(#(FieldPath, Int)),
) -> option.Option(Value) {
  case property.items {
    option.None -> option.None
    option.Some(item_schema) -> {
      let existing = case current {
        option.Some(ArrayValue(items)) -> items
        _ -> []
      }
      let walked =
        list.index_map(existing, fn(item, idx) {
          ensure_row(
            item_schema,
            list.append(field_path, [ArraySegment(idx)]),
            item,
            selected,
          )
        })
      let min = case property.array_constraints {
        option.Some(c) -> option.unwrap(c.min_items, 0)
        option.None -> 0
      }
      let missing = min - list.length(walked)
      let topped = case missing > 0 {
        True -> {
          let base_index = list.length(walked)
          let new_rows =
            list.repeat(Nil, missing)
            |> list.index_map(fn(_, i) {
              ensure_row(
                item_schema,
                list.append(field_path, [ArraySegment(base_index + i)]),
                new_array_item(item_schema),
                selected,
              )
            })
          list.append(walked, new_rows)
        }
        False -> walked
      }
      case current {
        // An existing array is rewritten (row walk may have topped up
        // nested arrays); a missing/non-array value is only created when
        // minItems actually demands rows.
        option.Some(ArrayValue(_)) -> option.Some(ArrayValue(topped))
        _ ->
          case topped {
            [] -> option.None
            _ -> option.Some(ArrayValue(topped))
          }
      }
    }
  }
}

// Walk one array row: resolve the item schema against the row's own
// values (union branch first, then conditionals — design D4), then recurse
// into the row's fields so nested arrays (including conditionally/union
// revealed ones) are topped up too. Fresh rows built by `new_array_item` go
// through the same walk, so defaults that satisfy a condition immediately
// hydrate what the condition reveals. `item_path` is the row's own absolute
// path (ending in the `ArraySegment` that addresses it) — the key
// `union_resolver` needs to look up `selected` and to build child paths.
fn ensure_row(
  item_schema: SchemaProperty,
  item_path: FieldPath,
  row: Value,
  selected: List(#(FieldPath, Int)),
) -> Value {
  let resolved =
    union_resolver.resolve_effective_property(
      item_schema,
      row,
      item_path,
      selected,
    )
  case row, resolved.properties {
    ObjectValue(fields), option.Some(sub_props) ->
      ObjectValue(ensure_fields(sub_props, item_path, fields, selected))
    _, _ -> row
  }
}
