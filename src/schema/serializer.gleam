// JSON Schema serialization functions

import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import schema/types.{
  type ConditionalRule, type FieldType, type JsonSchema, type NumberConstraints,
  type SchemaProperty, type StringConstraints, type StringFormat, type Value,
  ArrayType, ArrayValue, BooleanType, BooleanValue, CustomFormat, DateFormat,
  DateTimeFormat, EmailFormat, IntegerType, IntegerValue, NullType, NullValue,
  NumberType, NumberValue, ObjectType, ObjectValue, RegexFormat, StringType,
  StringValue, TimeFormat, UriFormat, UrlFormat, UuidFormat,
}

/// Convert a JsonSchema to a JSON object for serialization.
///
/// This function converts the internal JsonSchema representation to a JSON object
/// that can be serialized to a string. It produces valid JSON Schema draft 2020-12.
pub fn schema_to_json(schema: JsonSchema) -> json.Json {
  let base_fields = [
    #("$schema", json.string("https://json-schema.org/draft/2020-12/schema")),
    #("title", json.string(schema.title)),
    #("type", json.string(field_type_to_string(schema.field_type))),
  ]

  let fields_with_description = case schema.description {
    Some(desc) ->
      list.append(base_fields, [#("description", json.string(desc))])
    None -> base_fields
  }

  let fields_with_properties = case dict.is_empty(schema.properties) {
    True -> fields_with_description
    False -> {
      let props_json =
        schema.properties
        |> dict.to_list()
        |> list.map(fn(pair) {
          let #(key, prop) = pair
          #(key, property_to_json(prop))
        })
        |> json.object()

      list.append(fields_with_description, [#("properties", props_json)])
    }
  }

  let fields_with_required = case schema.required {
    [] -> fields_with_properties
    required -> {
      let required_json = json.array(required, of: json.string)
      list.append(fields_with_properties, [#("required", required_json)])
    }
  }

  let fields_with_defs = case schema.defs {
    Some(defs) -> {
      case dict.is_empty(defs) {
        True -> fields_with_required
        False -> {
          let defs_json =
            defs
            |> dict.to_list()
            |> list.map(fn(pair) {
              let #(key, prop) = pair
              #(key, property_to_json(prop))
            })
            |> json.object()
          list.append(fields_with_required, [#("$defs", defs_json)])
        }
      }
    }
    None -> fields_with_required
  }

  let fields_with_conditionals = case schema.conditionals {
    [] -> fields_with_defs
    conditionals -> {
      // For multiple conditionals, we need to use allOf
      let conditional_jsons =
        conditionals
        |> list.map(conditional_to_json)

      case conditionals {
        [_single] -> {
          // Single conditional - add if/then/else directly
          case conditionals {
            [cond] -> add_conditional_fields(fields_with_defs, cond)
            _ -> fields_with_defs
          }
        }
        _ -> {
          // Multiple conditionals - wrap in allOf
          list.append(fields_with_defs, [
            #("allOf", json.array(conditional_jsons, of: fn(x) { x })),
          ])
        }
      }
    }
  }

  let fields_with_string_constraints = case schema.string_constraints {
    Some(constraints) -> {
      add_string_constraint_fields(fields_with_conditionals, constraints)
    }
    None -> fields_with_conditionals
  }

  let fields_with_number_constraints = case schema.number_constraints {
    Some(constraints) -> {
      add_number_constraint_fields(fields_with_string_constraints, constraints)
    }
    None -> fields_with_string_constraints
  }
  
  json.object(fields_with_number_constraints)
}

/// Convert a SchemaProperty to JSON.
fn property_to_json(prop: SchemaProperty) -> json.Json {
  let base_fields = []

  // Handle $ref first - if present, it takes precedence
  let fields_with_ref = case prop.ref {
    Some(ref) -> list.append(base_fields, [#("$ref", json.string(ref))])
    None -> base_fields
  }

  let fields_with_type = case prop.field_type {
    Some(ft) ->
      list.append(fields_with_ref, [
        #("type", json.string(field_type_to_string(ft))),
      ])
    None -> fields_with_ref
  }

  let fields_with_title = case prop.title {
    Some(t) -> list.append(fields_with_type, [#("title", json.string(t))])
    None -> fields_with_type
  }

  let fields_with_description = case prop.description {
    Some(d) ->
      list.append(fields_with_title, [#("description", json.string(d))])
    None -> fields_with_title
  }

  let fields_with_default = case prop.default {
    Some(def) ->
      list.append(fields_with_description, [#("default", value_to_json(def))])
    None -> fields_with_description
  }

  let fields_with_enum = case prop.enum_values {
    Some(values) -> {
      let enum_json = json.array(values, of: value_to_json)
      list.append(fields_with_default, [#("enum", enum_json)])
    }
    None -> fields_with_default
  }

  let fields_with_string_constraints = case prop.string_constraints {
    Some(constraints) ->
      add_string_constraint_fields(fields_with_enum, constraints)
    None -> fields_with_enum
  }

  let fields_with_number_constraints = case prop.number_constraints {
    Some(constraints) ->
      add_number_constraint_fields(fields_with_string_constraints, constraints)
    None -> fields_with_string_constraints
  }

  let fields_with_items = case prop.items {
    Some(items_prop) -> {
      list.append(fields_with_number_constraints, [
        #("items", property_to_json(items_prop)),
      ])
    }
    None -> fields_with_number_constraints
  }

  let fields_with_properties = case prop.properties {
    Some(props) -> {
      case dict.is_empty(props) {
        True -> fields_with_items
        False -> {
          let props_json =
            props
            |> dict.to_list()
            |> list.map(fn(pair) {
              let #(key, p) = pair
              #(key, property_to_json(p))
            })
            |> json.object()
          list.append(fields_with_items, [#("properties", props_json)])
        }
      }
    }
    None -> fields_with_items
  }

  let final_fields = case prop.required {
    [] -> fields_with_properties
    required -> {
      let required_json = json.array(required, of: json.string)
      list.append(fields_with_properties, [#("required", required_json)])
    }
  }

  json.object(final_fields)
}

/// Convert a FieldType to its JSON Schema string representation.
fn field_type_to_string(field_type: FieldType) -> String {
  case field_type {
    StringType -> "string"
    NumberType -> "number"
    IntegerType -> "integer"
    BooleanType -> "boolean"
    ArrayType -> "array"
    ObjectType -> "object"
    NullType -> "null"
  }
}

/// Convert a Value to JSON.
fn value_to_json(value: Value) -> json.Json {
  case value {
    StringValue(s) -> json.string(s)
    NumberValue(n) -> json.float(n)
    IntegerValue(i) -> json.int(i)
    BooleanValue(b) -> json.bool(b)
    NullValue -> json.null()
    ArrayValue(items) -> json.array(items, of: value_to_json)
    ObjectValue(fields) -> {
      fields
      |> list.map(fn(pair) {
        let #(key, val) = pair
        #(key, value_to_json(val))
      })
      |> json.object()
    }
  }
}

/// Add string constraint fields to a field list.
fn add_string_constraint_fields(
  fields: List(#(String, json.Json)),
  constraints: StringConstraints,
) -> List(#(String, json.Json)) {
  let fields_with_min = case constraints.min_length {
    Some(min) -> list.append(fields, [#("minLength", json.int(min))])
    None -> fields
  }

  let fields_with_max = case constraints.max_length {
    Some(max) -> list.append(fields_with_min, [#("maxLength", json.int(max))])
    None -> fields_with_min
  }

  let fields_with_pattern = case constraints.pattern {
    Some(pattern) ->
      list.append(fields_with_max, [#("pattern", json.string(pattern))])
    None -> fields_with_max
  }

  case constraints.format {
    Some(format) -> {
      let format_string = string_format_to_string(format)
      list.append(fields_with_pattern, [#("format", json.string(format_string))])
    }
    None -> fields_with_pattern
  }
}

/// Add number constraint fields to a field list.
fn add_number_constraint_fields(
  fields: List(#(String, json.Json)),
  constraints: NumberConstraints,
) -> List(#(String, json.Json)) {
  let fields_with_min = case constraints.minimum {
    Some(min) -> list.append(fields, [#("minimum", json.float(min))])
    None -> fields
  }

  let fields_with_max = case constraints.maximum {
    Some(max) -> list.append(fields_with_min, [#("maximum", json.float(max))])
    None -> fields_with_min
  }

  let fields_with_exclusive_min = case constraints.exclusive_minimum {
    Some(min) ->
      list.append(fields_with_max, [#("exclusiveMinimum", json.float(min))])
    None -> fields_with_max
  }

  let fields_with_exclusive_max = case constraints.exclusive_maximum {
    Some(max) ->
      list.append(fields_with_exclusive_min, [
        #("exclusiveMaximum", json.float(max)),
      ])
    None -> fields_with_exclusive_min
  }

  case constraints.multiple_of {
    Some(multiple) ->
      list.append(fields_with_exclusive_max, [
        #("multipleOf", json.float(multiple)),
      ])
    None -> fields_with_exclusive_max
  }
}

/// Convert a StringFormat to its JSON Schema string representation.
fn string_format_to_string(format: StringFormat) -> String {
  case format {
    DateFormat -> "date"
    DateTimeFormat -> "date-time"
    TimeFormat -> "time"
    EmailFormat -> "email"
    UriFormat -> "uri"
    UrlFormat -> "url"
    UuidFormat -> "uuid"
    RegexFormat(pattern) -> "regex:" <> pattern
    CustomFormat(name) -> name
  }
}

/// Convert a ConditionalRule to JSON.
fn conditional_to_json(conditional: ConditionalRule) -> json.Json {
  let base_fields = [#("if", property_to_json(conditional.if_schema))]

  let fields_with_then = case conditional.then_schema {
    Some(then_prop) ->
      list.append(base_fields, [#("then", property_to_json(then_prop))])
    None -> base_fields
  }

  let final_fields = case conditional.else_schema {
    Some(else_prop) ->
      list.append(fields_with_then, [#("else", property_to_json(else_prop))])
    None -> fields_with_then
  }

  json.object(final_fields)
}

/// Add conditional fields directly to schema fields (for single conditional).
fn add_conditional_fields(
  fields: List(#(String, json.Json)),
  conditional: ConditionalRule,
) -> List(#(String, json.Json)) {
  let fields_with_if =
    list.append(fields, [#("if", property_to_json(conditional.if_schema))])

  let fields_with_then = case conditional.then_schema {
    Some(then_prop) ->
      list.append(fields_with_if, [#("then", property_to_json(then_prop))])
    None -> fields_with_if
  }

  case conditional.else_schema {
    Some(else_prop) ->
      list.append(fields_with_then, [#("else", property_to_json(else_prop))])
    None -> fields_with_then
  }
}
