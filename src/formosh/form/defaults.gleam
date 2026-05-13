//// Apply JSON Schema `default` values recursively when initialising a form.
////
//// The form root is always a single `ObjectValue` tree (see `model.FormModel`
//// invariant), so this module operates on that shape end-to-end. Defaults are
//// applied at init and reset time; once the user starts editing, conditional
//// branches and array items hydrate without re-running this pass.

import formosh/schema/types.{
  type SchemaProperty, type Value, ArrayValue, NullValue, ObjectType,
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
