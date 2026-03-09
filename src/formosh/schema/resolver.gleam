// Module for resolving JSON Schema $ref references
// 
// This module handles the resolution of $ref pointers to their corresponding
// schema definitions, supporting the JSON Pointer syntax used in JSON Schema.

import formosh/schema/types.{type JsonSchema, type SchemaProperty}
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

  // Return the schema with resolved properties
  Ok(types.JsonSchema(..schema, properties: resolved_properties))
}

/// Resolve references in a dictionary of properties
fn resolve_properties_refs(
  properties: Dict(String, SchemaProperty),
  context: Dict(String, SchemaProperty),
  visited: List(String),
) -> Result(Dict(String, SchemaProperty), ResolveError) {
  properties
  |> dict.to_list()
  |> list.try_map(fn(entry) {
    let #(key, prop) = entry
    use resolved_prop <- result.try(resolve_property_ref(prop, context, visited))
    Ok(#(key, resolved_prop))
  })
  |> result.map(dict.from_list)
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

              // Merge the resolved property with any local overrides
              Ok(merge_properties(property, resolved))
            }
            Error(_) -> Error(ReferenceNotFound(ref_path))
          }
        }
      }
    }
  }
}

/// Apply a fallible function to an optional value, preserving None
fn resolve_optional(
  value: option.Option(a),
  resolver: fn(a) -> Result(b, ResolveError),
) -> Result(option.Option(b), ResolveError) {
  case value {
    Some(v) -> result.map(resolver(v), Some)
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
    resolve_optional(property.properties, resolve_properties_refs(
      _,
      context,
      visited,
    )),
  )

  use resolved_items <- result.try(
    resolve_optional(property.items, resolve_property_ref(_, context, visited)),
  )

  use resolved_one_of <- result.try(
    resolve_optional(
      property.one_of,
      list.try_map(_, resolve_property_ref(_, context, visited)),
    ),
  )

  Ok(
    types.SchemaProperty(
      ..property,
      properties: resolved_properties,
      items: resolved_items,
      one_of: resolved_one_of,
    ),
  )
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
    items: option.or(referencing.items, referenced.items),
    properties: option.or(referencing.properties, referenced.properties),
    required: case referencing.required {
      [] -> referenced.required
      [_, ..] -> referencing.required
    },
    // readOnly is true if either property has it set
    read_only: referencing.read_only || referenced.read_only,
  )
}
