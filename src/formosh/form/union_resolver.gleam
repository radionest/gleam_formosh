/// Union (`anyOf`) branch resolution for dynamic form behavior.
///
/// Mirrors `formosh/schema/conditional_resolver`: this module decides which
/// `any_of` member is "active" for a given field path and materializes that
/// member's content into the node, so every schema walker (render,
/// validation, visibility, defaults, readonly) can operate on a single
/// effective schema without knowing about unions.
///
/// Resolution order (design D4, openspec/changes/add-anyof-union-support):
/// union resolution runs BEFORE conditional resolution — a conditional rule
/// declared inside the active branch must see the branch already
/// materialized. `resolve_effective_property` composes both, union first.
///
/// Branch inference is resolution-time only (design D8): a stored selection
/// in `selected` always wins; otherwise the branch is inferred from the
/// current value (scalar type match, then object key overlap), defaulting to
/// 0. Nothing here writes back to `selected` — every function is pure.
import formosh/form/path.{type FieldPath, PropertySegment}
import formosh/schema/conditional_resolver
import formosh/schema/properties
import formosh/schema/types.{
  type FieldType, type JsonSchema, type SchemaProperty, type Value, ArrayType,
  ArrayValue, BooleanType, BooleanValue, IntegerType, IntegerValue, JsonSchema,
  NullType, NullValue, NumberType, NumberValue, ObjectType, ObjectValue,
  SchemaProperty, StringType, StringValue,
}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// Recompute a whole `JsonSchema`'s top-level properties, materializing every
/// 2+-member `any_of` node to its active branch. Mirrors the shape of
/// `conditional_resolver.resolve_recursive`'s walk: objects descend with
/// their slice of `values` and an extended path; array `items` are left
/// untouched — per-row union resolution happens at render/validate time via
/// `resolve_effective_property`, where the row path is actually available.
pub fn resolve_form_schema(
  schema: JsonSchema,
  values: Value,
  selected: List(#(FieldPath, Int)),
) -> JsonSchema {
  let fields = case values {
    ObjectValue(fs) -> fs
    _ -> []
  }
  JsonSchema(
    ..schema,
    properties: walk_properties(schema.properties, [], fields, selected),
  )
}

/// Resolve a single row/item-rooted property: the same node-level union walk
/// as `resolve_form_schema`, rooted at `row_path`/`row_value`, followed by
/// `conditional_resolver.resolve_conditional_property` — union first so a
/// conditional declared on the active branch already sees it materialized
/// (design D4).
pub fn resolve_effective_property(
  prop: SchemaProperty,
  row_value: Value,
  row_path: FieldPath,
  selected: List(#(FieldPath, Int)),
) -> SchemaProperty {
  walk_node(prop, row_path, Some(row_value), selected)
  |> conditional_resolver.resolve_conditional_property(row_value)
}

/// Decide the active branch index for a union node at `field_path`. A stored
/// `selected` entry always wins; otherwise the branch is inferred from
/// `value` (design D8). Never validates the result against the member
/// count — `materialize_branch` falls back to branch 0 defensively.
pub fn active_branch_index(
  prop: SchemaProperty,
  value: Option(Value),
  field_path: FieldPath,
  selected: List(#(FieldPath, Int)),
) -> Int {
  case list.key_find(selected, field_path) {
    Ok(index) -> index
    Error(_) -> infer_index(option.unwrap(prop.any_of, []), value)
  }
}

/// Materialize `prop`'s branch at `index` into an effective `SchemaProperty`:
/// the member's type/constraints/properties/items become the node's, while
/// `title`/`description`/`render_hints`/`nullable` stay the parent's
/// (Pydantic puts them there, not on the member) and `any_of` resets to the
/// parent's full member list so the dispatcher can still render the chooser
/// (it strips `any_of` itself before recursing into the branch). An
/// out-of-range index falls back to branch 0.
pub fn materialize_branch(prop: SchemaProperty, index: Int) -> SchemaProperty {
  let members = option.unwrap(prop.any_of, [])
  let member = case list.drop(members, index) {
    [m, ..] -> m
    [] ->
      case members {
        [m, ..] -> m
        [] -> prop
      }
  }
  SchemaProperty(
    ..member,
    title: prop.title,
    description: prop.description,
    default: option.or(member.default, prop.default),
    nullable: prop.nullable,
    read_only: prop.read_only || member.read_only,
    render_hints: prop.render_hints,
    conditionals: list.append(prop.conditionals, member.conditionals),
    any_of: prop.any_of,
  )
}

/// Display label for a branch chooser option (design D7): the member's own
/// `title` — already carrying a resolved `$defs` title by the time `$ref`
/// resolution has run (`resolver.gleam` merges `option.or(referencing.title,
/// referenced.title)`) — wins; otherwise the capitalized JSON Schema type
/// name; otherwise `"Option N"` (1-based).
pub fn branch_label(member: SchemaProperty, index: Int) -> String {
  case member.title {
    Some(title) -> title
    None ->
      case member.field_type {
        Some(field_type) -> type_label(field_type)
        None -> "Option " <> int.to_string(index + 1)
      }
  }
}

fn type_label(field_type: FieldType) -> String {
  case field_type {
    StringType -> "String"
    NumberType -> "Number"
    IntegerType -> "Integer"
    BooleanType -> "Boolean"
    ObjectType -> "Object"
    ArrayType -> "Array"
    NullType -> "Null"
  }
}

/// Infer the active branch from a value when no selection is stored (design
/// D8): the first member whose declared type matches a scalar value, the
/// first member whose `properties` overlap an object value's keys, else 0.
fn infer_index(members: List(SchemaProperty), value: Option(Value)) -> Int {
  case value {
    None -> 0
    Some(v) ->
      members
      |> list.index_map(fn(member, idx) { #(idx, member) })
      |> list.find(fn(pair) { value_matches_member(v, pair.1) })
      |> result.map(fn(pair) { pair.0 })
      |> result.unwrap(0)
  }
}

fn value_matches_member(value: Value, member: SchemaProperty) -> Bool {
  case value {
    ObjectValue(fields) ->
      case member.properties {
        Some(props) ->
          list.any(fields, fn(f) { properties.has_key(props, f.0) })
        None -> False
      }
    StringValue(_) -> member.field_type == Some(StringType)
    IntegerValue(_) ->
      member.field_type == Some(IntegerType)
      || member.field_type == Some(NumberType)
    NumberValue(_) -> member.field_type == Some(NumberType)
    BooleanValue(_) -> member.field_type == Some(BooleanType)
    ArrayValue(_) -> member.field_type == Some(ArrayType)
    NullValue -> False
  }
}

/// Node-level union walk shared by `resolve_form_schema` (rooted at the
/// document root) and `resolve_effective_property` (rooted at a row):
/// materialize this node's union if it has one, then descend into object
/// children with their path/value extended. Arrays are never descended —
/// `items` stays untouched, mirroring `conditional_resolver`'s split between
/// pre-applied static rules and render-time per-row resolution.
fn walk_node(
  prop: SchemaProperty,
  node_path: FieldPath,
  value: Option(Value),
  selected: List(#(FieldPath, Int)),
) -> SchemaProperty {
  let materialized = case prop.any_of {
    Some(_) ->
      materialize_branch(
        prop,
        active_branch_index(prop, value, node_path, selected),
      )
    None -> prop
  }

  case materialized.field_type, materialized.properties {
    Some(ObjectType), Some(props) -> {
      let fields = case value {
        Some(ObjectValue(fs)) -> fs
        _ -> []
      }
      SchemaProperty(
        ..materialized,
        properties: Some(walk_properties(props, node_path, fields, selected)),
      )
    }
    _, _ -> materialized
  }
}

fn walk_properties(
  props: List(#(String, SchemaProperty)),
  parent_path: FieldPath,
  values_fields: List(#(String, Value)),
  selected: List(#(FieldPath, Int)),
) -> List(#(String, SchemaProperty)) {
  list.map(props, fn(entry) {
    let #(name, prop) = entry
    let node_path = list.append(parent_path, [PropertySegment(name)])
    let value = option.from_result(list.key_find(values_fields, name))
    #(name, walk_node(prop, node_path, value, selected))
  })
}
