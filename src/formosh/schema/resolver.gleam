// Module for resolving JSON Schema $ref references
// 
// This module handles the resolution of $ref pointers to their corresponding
// schema definitions, supporting the JSON Pointer syntax used in JSON Schema.

import formosh/schema/types.{
  type ConditionalRule, type JsonSchema, type SchemaProperty,
}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

/// Errors that can occur during reference resolution
pub type ResolveError {
  /// Reference points to a non-existent definition
  ReferenceNotFound(String)
  /// Circular reference detected
  CircularReference(String)
  /// Invalid reference format
  InvalidReference(String)
}

/// Resolve all $ref references in a JSON Schema
/// 
/// This function recursively resolves all $ref references in the schema,
/// replacing them with the actual schema definitions they point to.
/// It handles nested references and protects against circular references.
/// 
/// ## Parameters
/// - `schema`: The schema containing references to resolve
/// 
/// ## Returns
/// - `Ok(JsonSchema)` with all references resolved
/// - `Error(ResolveError)` if resolution fails
pub fn resolve_refs(schema: JsonSchema) -> Result(JsonSchema, ResolveError) {
  // Create a context with all definitions for easy lookup
  let context = case schema.defs {
    Some(defs) -> defs
    None -> dict.new()
  }

  // Resolve references in top-level properties
  use resolved_properties <- result.try(
    resolve_properties_refs(schema.properties, context, []),
  )

  // Resolve references inside top-level conditional rules (allOf / if / then / else)
  use resolved_conditionals <- result.try(
    list.try_map(schema.conditionals, resolve_conditional_rule(_, context, [])),
  )

  // Resolve references inside root-level allOf members
  use resolved_all_of <- result.try(
    try_optional(
      schema.all_of,
      list.try_map(_, resolve_property_ref(_, context, [])),
    ),
  )

  Ok(
    types.JsonSchema(
      ..schema,
      properties: resolved_properties,
      conditionals: resolved_conditionals,
      all_of: resolved_all_of,
    ),
  )
}

/// Resolve `$ref`s in a standalone property tree against a `$defs` context.
/// Same recursive walk and visited-set cycle protection as `resolve_refs`;
/// used by the parser for the document root, which parses as a
/// `SchemaProperty` so type absence stays representable until composition
/// has run.
pub fn resolve_property(
  property: SchemaProperty,
  defs: option.Option(Dict(String, SchemaProperty)),
) -> Result(SchemaProperty, ResolveError) {
  resolve_property_ref(property, option.unwrap(defs, dict.new()), [])
}

/// Resolve references in an ordered list of properties, preserving key order.
fn resolve_properties_refs(
  properties: List(#(String, SchemaProperty)),
  context: Dict(String, SchemaProperty),
  visited: List(String),
) -> Result(List(#(String, SchemaProperty)), ResolveError) {
  properties
  |> list.try_map(fn(entry) {
    let #(key, prop) = entry
    use resolved_prop <- result.try(resolve_property_ref(prop, context, visited))
    Ok(#(key, resolved_prop))
  })
}

/// Resolve a single property that might contain a $ref
fn resolve_property_ref(
  property: SchemaProperty,
  context: Dict(String, SchemaProperty),
  visited: List(String),
) -> Result(SchemaProperty, ResolveError) {
  case property.ref {
    None -> {
      // No reference, but might have nested properties or items to resolve
      resolve_nested_refs(property, context, visited)
    }
    Some(ref_path) -> {
      // Check for circular reference
      case list.contains(visited, ref_path) {
        True -> Error(CircularReference(ref_path))
        False -> {
          // Parse the reference path and look it up
          use definition_name <- result.try(parse_ref_path(ref_path))

          case dict.get(context, definition_name) {
            Ok(referenced_property) -> {
              // Recursively resolve any references in the referenced property
              let new_visited = [ref_path, ..visited]
              use resolved <- result.try(resolve_property_ref(
                referenced_property,
                context,
                new_visited,
              ))

              // Resolve refs nested in the referencing node's own subtree
              // (items, properties, allOf members, conditionals) before the
              // merge — an unresolved local ref would otherwise survive it.
              // `visited` (not `new_visited`): a local member re-referencing
              // the same definition is reuse, not a cycle.
              use resolved_local <- result.try(resolve_nested_refs(
                property,
                context,
                visited,
              ))

              // Merge the resolved property with any local overrides
              Ok(merge_properties(resolved_local, resolved))
            }
            Error(_) -> Error(ReferenceNotFound(ref_path))
          }
        }
      }
    }
  }
}

/// Traverse an Option through a fallible function, preserving None.
pub fn try_optional(
  value: option.Option(a),
  f: fn(a) -> Result(b, e),
) -> Result(option.Option(b), e) {
  case value {
    Some(v) -> result.map(f(v), Some)
    None -> Ok(None)
  }
}

/// Resolve references in nested properties and items
fn resolve_nested_refs(
  property: SchemaProperty,
  context: Dict(String, SchemaProperty),
  visited: List(String),
) -> Result(SchemaProperty, ResolveError) {
  use resolved_properties <- result.try(
    try_optional(property.properties, resolve_properties_refs(
      _,
      context,
      visited,
    )),
  )

  use resolved_items <- result.try(
    try_optional(property.items, resolve_property_ref(_, context, visited)),
  )

  use resolved_one_of <- result.try(
    try_optional(
      property.one_of,
      list.try_map(_, resolve_property_ref(_, context, visited)),
    ),
  )

  use resolved_any_of <- result.try(
    try_optional(
      property.any_of,
      list.try_map(_, resolve_property_ref(_, context, visited)),
    ),
  )

  use resolved_conditionals <- result.try(
    list.try_map(property.conditionals, resolve_conditional_rule(
      _,
      context,
      visited,
    )),
  )

  use resolved_all_of <- result.try(
    try_optional(
      property.all_of,
      list.try_map(_, resolve_property_ref(_, context, visited)),
    ),
  )

  Ok(
    types.SchemaProperty(
      ..property,
      properties: resolved_properties,
      items: resolved_items,
      one_of: resolved_one_of,
      any_of: resolved_any_of,
      conditionals: resolved_conditionals,
      all_of: resolved_all_of,
    ),
  )
}

/// Resolve `$ref` references inside a single `ConditionalRule`.
///
/// Walks `if_schema`, `then_schema`, `else_schema` through `resolve_property_ref`
/// so `$ref`-bearing sub-schemas are expanded before `conditional_resolver`
/// merges them at render time. Without this, `then.properties` with a `$ref`
/// stays unresolved and downstream renderers see fields with `field_type: None`.
fn resolve_conditional_rule(
  rule: ConditionalRule,
  context: Dict(String, SchemaProperty),
  visited: List(String),
) -> Result(ConditionalRule, ResolveError) {
  let resolve_one = resolve_property_ref(_, context, visited)
  use if_resolved <- result.try(resolve_one(rule.if_schema))
  use then_resolved <- result.try(try_optional(rule.then_schema, resolve_one))
  use else_resolved <- result.try(try_optional(rule.else_schema, resolve_one))
  Ok(types.ConditionalRule(
    if_schema: if_resolved,
    then_schema: then_resolved,
    else_schema: else_resolved,
  ))
}

/// Parse a JSON Pointer reference path
/// 
/// Extracts the definition name from a reference like "#/$defs/Address"
/// 
/// ## Parameters
/// - `ref_path`: The reference path to parse
/// 
/// ## Returns
/// - `Ok(String)` with the definition name
/// - `Error(ResolveError)` if the path is invalid
fn parse_ref_path(ref_path: String) -> Result(String, ResolveError) {
  case string.starts_with(ref_path, "#/$defs/") {
    True -> {
      let definition_name =
        ref_path
        |> string.drop_start(8)
      // Remove "#/$defs/"

      case string.length(definition_name) > 0 {
        True -> Ok(definition_name)
        False -> Error(InvalidReference(ref_path))
      }
    }
    False -> {
      // Also support "#/definitions/" for compatibility
      case string.starts_with(ref_path, "#/definitions/") {
        True -> {
          let definition_name =
            ref_path
            |> string.drop_start(14)
          // Remove "#/definitions/"

          case string.length(definition_name) > 0 {
            True -> Ok(definition_name)
            False -> Error(InvalidReference(ref_path))
          }
        }
        False -> Error(InvalidReference(ref_path))
      }
    }
  }
}

/// Append two optional allOf member lists. Both sides' members apply when
/// a $ref-bearing node and its referenced definition each carry allOf —
/// composer.flatten_property collapses the combined list after resolution.
/// Referenced members go first: the composer fold is later-wins, so the
/// referencing node's local members keep the local-override precedence.
fn append_all_of(
  left: option.Option(List(SchemaProperty)),
  right: option.Option(List(SchemaProperty)),
) -> option.Option(List(SchemaProperty)) {
  case left, right {
    None, None -> None
    Some(l), None -> Some(l)
    None, Some(r) -> Some(r)
    Some(l), Some(r) -> Some(list.append(l, r))
  }
}

/// Merge two properties, with the referencing property taking precedence
///
/// This allows local overrides of referenced definitions
fn merge_properties(
  referencing: SchemaProperty,
  referenced: SchemaProperty,
) -> SchemaProperty {
  types.SchemaProperty(
    // Use referencing property's values if they exist, otherwise use referenced
    field_type: option.or(referencing.field_type, referenced.field_type),
    title: option.or(referencing.title, referenced.title),
    description: option.or(referencing.description, referenced.description),
    default: option.or(referencing.default, referenced.default),
    enum_values: option.or(referencing.enum_values, referenced.enum_values),
    one_of: option.or(referencing.one_of, referenced.one_of),
    any_of: option.or(referencing.any_of, referenced.any_of),
    all_of: append_all_of(referenced.all_of, referencing.all_of),
    ref: None,
    // Clear the ref since it's been resolved
    string_constraints: option.or(
      referencing.string_constraints,
      referenced.string_constraints,
    ),
    number_constraints: option.or(
      referencing.number_constraints,
      referenced.number_constraints,
    ),
    array_constraints: option.or(
      referencing.array_constraints,
      referenced.array_constraints,
    ),
    items: option.or(referencing.items, referenced.items),
    properties: option.or(referencing.properties, referenced.properties),
    required: case referencing.required {
      [] -> referenced.required
      [_, ..] -> referencing.required
    },
    // readOnly is true if either property has it set
    read_only: referencing.read_only || referenced.read_only,
    nullable: referencing.nullable || referenced.nullable,
    // x-addable / x-removable: AND-merge — most restrictive wins
    addable: referencing.addable && referenced.addable,
    removable: referencing.removable && referenced.removable,
    render_hints: merge_render_hints(
      referencing.render_hints,
      referenced.render_hints,
    ),
    conditionals: list.append(referencing.conditionals, referenced.conditionals),
  )
}

/// Merge two `RenderHints`, with the referencing side winning per-field —
/// except `disabled`/`readonly`, which OR-merge: a `false` on one side must
/// not re-enable a `true` from the other, mirroring `SchemaProperty.read_only`
/// and the UiSchema `ui:disabled` contract.
///
/// Runs during `$ref` resolution, so the inputs carry hints from JSON
/// Schema `x-*` extensions on the referencing/referenced nodes — currently
/// `x-widget`, `x-accept`, `x-max-file-size`. UiSchema merging happens later
/// in `ui_resolver.resolve_hints` and feeds the other `RenderHints` fields
/// (`placeholder`, `help`, etc.), so here they are always `None` on both
/// sides.
///
/// Also reused by `composer` for allOf member merging (first argument wins
/// on the per-field picks).
pub fn merge_render_hints(
  referencing: types.RenderHints,
  referenced: types.RenderHints,
) -> types.RenderHints {
  types.RenderHints(
    widget: option.or(referencing.widget, referenced.widget),
    options: referencing.options,
    upload_config: option.or(
      referencing.upload_config,
      referenced.upload_config,
    ),
    placeholder: option.or(referencing.placeholder, referenced.placeholder),
    help: option.or(referencing.help, referenced.help),
    autofocus: option.or(referencing.autofocus, referenced.autofocus),
    disabled: or_hint(referencing.disabled, referenced.disabled),
    readonly: or_hint(referencing.readonly, referenced.readonly),
    title: option.or(referencing.title, referenced.title),
    description: option.or(referencing.description, referenced.description),
    order: option.or(referencing.order, referenced.order),
    addable: option.or(referencing.addable, referenced.addable),
    removable: option.or(referencing.removable, referenced.removable),
    orderable: option.or(referencing.orderable, referenced.orderable),
  )
}

/// OR-combine two optional boolean hints: `Some(False)` must not override
/// `Some(True)` from the other side.
fn or_hint(
  a: option.Option(Bool),
  b: option.Option(Bool),
) -> option.Option(Bool) {
  case a, b {
    Some(x), Some(y) -> Some(x || y)
    _, _ -> option.or(a, b)
  }
}
