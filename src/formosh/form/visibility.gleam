/// Visibility walker for the form submit gate.
///
/// `invisible_paths` returns the set of canonical path keys whose fields are
/// suppressed from the UI: `widget == Some(HiddenWidget)` (via UiSchema or the
/// deprecated `x-widget` fallback), or `read_only` when `show_readonly_fields`
/// is `False`. For a suppressed container, every descendant path that could
/// legitimately appear in `model.errors` is pushed too — array indices are
/// enumerated from the current `values` length, so the result stays in sync
/// with the actual error keys produced by the validator.
///
/// The walker mirrors the inheritance encoded in `field_common.make_child_ctx`
/// (`is_readonly` OR-merges from parent to child) and reuses
/// `ui_resolver.resolve_hints` for widget selection so it cannot drift from
/// the renderer's notion of "hidden".
///
/// Run after `conditional_resolver.resolve_recursive` so branch switches are
/// reflected. Set keys use `path.to_string`, matching the encoding of
/// `model.errors` keys (canonical format in `formosh/path_format`).
///
/// Known limitation: item-level conditionals inside array `items` are not
/// recursed per row (mirrors `conditional_resolver.resolve_nested_conditionals`
/// — per-row resolve happens at render time, not in the pre-walk). If a
/// conditional flips visibility for some rows but not others, the set is
/// computed against the base `items` template, not the per-row resolved
/// schema. The same per-row gap applies to union branches: a union inside
/// array `items` stays a raw node in the pre-walk (`field_type: None` →
/// skipped), so hidden fields inside a row's active branch are not
/// collected.
import formosh/form/path.{type FieldPath, ArraySegment, PropertySegment}
import formosh/schema/types.{
  type JsonSchema, type SchemaProperty, type Value, ArrayType, ArrayValue,
  ObjectType, ObjectValue,
}
import formosh/schema/ui_resolver
import formosh/schema/ui_schema.{type UiSchema}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}

/// Compute the set of suppressed-field path keys in canonical form.
pub fn invisible_paths(
  schema: JsonSchema,
  ui_schema: UiSchema,
  values: Value,
  show_readonly_fields: Bool,
) -> Set(String) {
  let root_fields = case values {
    ObjectValue(fs) -> fs
    _ -> []
  }
  walk_properties(
    schema.properties,
    [],
    root_fields,
    ui_schema,
    False,
    show_readonly_fields,
    set.new(),
  )
}

fn walk_properties(
  props: List(#(String, SchemaProperty)),
  parent_path: FieldPath,
  values_fields: List(#(String, Value)),
  ui_schema: UiSchema,
  parent_readonly: Bool,
  show_readonly_fields: Bool,
  acc: Set(String),
) -> Set(String) {
  list.fold(props, acc, fn(acc, entry) {
    let #(name, prop) = entry
    let node_path = list.append(parent_path, [PropertySegment(name)])
    let value = option.from_result(list.key_find(values_fields, name))
    walk_node(
      prop,
      node_path,
      value,
      ui_schema,
      parent_readonly,
      show_readonly_fields,
      acc,
    )
  })
}

fn walk_node(
  prop: SchemaProperty,
  node_path: FieldPath,
  value: Option(Value),
  ui_schema: UiSchema,
  parent_readonly: Bool,
  show_readonly_fields: Bool,
  acc: Set(String),
) -> Set(String) {
  let hints = ui_resolver.resolve_hints(ui_schema, node_path, prop)
  let effective_readonly =
    parent_readonly || prop.read_only || option.unwrap(hints.readonly, False)

  case
    ui_resolver.is_suppressed(hints, effective_readonly, show_readonly_fields)
  {
    True -> {
      let acc = set.insert(acc, path.to_string(node_path))
      push_subtree_paths(prop, node_path, value, acc)
    }
    False ->
      descend_visible(
        prop,
        node_path,
        value,
        ui_schema,
        effective_readonly,
        show_readonly_fields,
        acc,
      )
  }
}

fn descend_visible(
  prop: SchemaProperty,
  node_path: FieldPath,
  value: Option(Value),
  ui_schema: UiSchema,
  parent_readonly: Bool,
  show_readonly_fields: Bool,
  acc: Set(String),
) -> Set(String) {
  case prop.field_type {
    Some(ObjectType) ->
      case prop.properties {
        Some(child_props) -> {
          let fields = case value {
            Some(ObjectValue(fs)) -> fs
            _ -> []
          }
          walk_properties(
            child_props,
            node_path,
            fields,
            ui_schema,
            parent_readonly,
            show_readonly_fields,
            acc,
          )
        }
        None -> acc
      }
    Some(ArrayType) ->
      case prop.items, value {
        Some(items_schema), Some(ArrayValue(items)) ->
          list.index_fold(items, acc, fn(acc, item_value, idx) {
            let item_path = list.append(node_path, [ArraySegment(idx)])
            walk_node(
              items_schema,
              item_path,
              Some(item_value),
              ui_schema,
              parent_readonly,
              show_readonly_fields,
              acc,
            )
          })
        _, _ -> acc
      }
    _ -> acc
  }
}

/// Enumerate every error-producible path inside a suppressed subtree.
///
/// Walks down through containers (objects + arrays) pushing each declared
/// child path. Scalar leaves are added by the caller before descending here,
/// so this helper only handles the recursion into containers.
///
/// For objects: every declared child property path is pushed regardless of
/// whether the value tree has an entry — the validator walks the schema and
/// produces errors for missing required fields, so the error key may exist
/// even when the value does not. For arrays: indices are enumerated from
/// `values` since rows that don't exist cannot have errors.
fn push_subtree_paths(
  prop: SchemaProperty,
  node_path: FieldPath,
  value: Option(Value),
  acc: Set(String),
) -> Set(String) {
  case prop.field_type {
    Some(ObjectType) ->
      case prop.properties {
        Some(child_props) -> {
          let fields = case value {
            Some(ObjectValue(fs)) -> fs
            _ -> []
          }
          list.fold(child_props, acc, fn(acc, entry) {
            let #(name, child_prop) = entry
            let child_path = list.append(node_path, [PropertySegment(name)])
            let acc = set.insert(acc, path.to_string(child_path))
            let child_value = option.from_result(list.key_find(fields, name))
            push_subtree_paths(child_prop, child_path, child_value, acc)
          })
        }
        None -> acc
      }
    Some(ArrayType) ->
      case prop.items, value {
        Some(items_schema), Some(ArrayValue(items)) ->
          list.index_fold(items, acc, fn(acc, item_value, idx) {
            let item_path = list.append(node_path, [ArraySegment(idx)])
            let acc = set.insert(acc, path.to_string(item_path))
            push_subtree_paths(items_schema, item_path, Some(item_value), acc)
          })
        _, _ -> acc
      }
    _ -> acc
  }
}
