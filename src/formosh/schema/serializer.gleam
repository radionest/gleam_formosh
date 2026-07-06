// JSON Schema serialization functions

import formosh/schema/types.{
  type ArrayConstraints, type ConditionalRule, type FieldType, type JsonSchema,
  type NumberConstraints, type SchemaProperty, type StringConstraints,
  type StringFormat, type UploadConfig, type Value, type Widget, ArrayType,
  ArrayValue, BooleanType, BooleanValue, CustomFormat, CustomWidget, DateFormat,
  DateTimeFormat, EmailFormat, HiddenWidget, ImageUploadWidget, IntegerType,
  IntegerValue, NullType, NullValue, NumberType, NumberValue, ObjectType,
  ObjectValue, StringType, StringValue, SwipeReviewWidget, TimeFormat,
  UploadConfig, UriFormat, UrlFormat, UuidFormat,
}
import gleam/dict
import gleam/json
import gleam/list
import gleam/option

// Helper function to add a field if a value exists
fn add_optional_json_field(
  fields: List(#(String, json.Json)),
  name: String,
  value: option.Option(a),
  mapper: fn(a) -> json.Json,
) -> List(#(String, json.Json)) {
  value
  |> option.map(fn(v) { [#(name, mapper(v))] })
  |> option.unwrap([])
  |> list.append(fields, _)
}

// Helper to add multiple fields at once
fn add_fields(
  fields: List(#(String, json.Json)),
  new_fields: List(#(String, json.Json)),
) -> List(#(String, json.Json)) {
  list.append(fields, new_fields)
}

// Helper to add properties object if not empty
fn add_properties_object(
  fields: List(#(String, json.Json)),
  properties: List(#(String, SchemaProperty)),
) -> List(#(String, json.Json)) {
  case properties {
    [] -> fields
    _ -> {
      properties
      |> list.map(fn(pair) {
        let #(key, prop) = pair
        #(key, property_to_json(prop))
      })
      |> json.object()
      |> fn(props_json) { add_fields(fields, [#("properties", props_json)]) }
    }
  }
}

// Helper to add required array if not empty
fn add_required_array(
  fields: List(#(String, json.Json)),
  required: List(String),
) -> List(#(String, json.Json)) {
  case required {
    [] -> fields
    _ ->
      add_fields(fields, [#("required", json.array(required, of: json.string))])
  }
}

// Helper to add definitions
fn add_definitions(
  fields: List(#(String, json.Json)),
  defs: option.Option(dict.Dict(String, SchemaProperty)),
) -> List(#(String, json.Json)) {
  defs
  |> option.map(fn(d) {
    case dict.is_empty(d) {
      True -> fields
      False -> {
        d
        |> dict.to_list()
        |> list.map(fn(pair) {
          let #(key, prop) = pair
          #(key, property_to_json(prop))
        })
        |> json.object()
        |> fn(defs_json) { add_fields(fields, [#("$defs", defs_json)]) }
      }
    }
  })
  |> option.unwrap(fields)
}

// Helper to add conditionals
fn add_conditionals(
  fields: List(#(String, json.Json)),
  conditionals: List(ConditionalRule),
) -> List(#(String, json.Json)) {
  case conditionals {
    [] -> fields
    [single] -> add_conditional_fields(fields, single)
    multiple -> {
      multiple
      |> list.map(conditional_to_json)
      |> json.array(of: fn(x) { x })
      |> fn(all_of) { add_fields(fields, [#("allOf", all_of)]) }
    }
  }
}

/// Convert a JsonSchema to a JSON object for serialization.
///
/// This function converts the internal JsonSchema representation to a JSON object
/// that can be serialized to a string. It produces valid JSON Schema draft 2020-12.
pub fn schema_to_json(schema: JsonSchema) -> json.Json {
  []
  |> add_fields([
    #("$schema", json.string("https://json-schema.org/draft/2020-12/schema")),
    #("type", json.string(field_type_to_string(schema.field_type))),
  ])
  |> add_optional_json_field("title", schema.title, json.string)
  |> add_optional_json_field("description", schema.description, json.string)
  |> add_properties_object(schema.properties)
  |> add_required_array(schema.required)
  |> add_definitions(schema.defs)
  |> add_conditionals(schema.conditionals)
  |> fn(fields) {
    schema.string_constraints
    |> option.map(add_string_constraint_fields(fields, _))
    |> option.unwrap(fields)
  }
  |> fn(fields) {
    schema.number_constraints
    |> option.map(add_number_constraint_fields(fields, _))
    |> option.unwrap(fields)
  }
  |> json.object()
}

// Helper to add enum values if present
fn add_optional_enum(
  fields: List(#(String, json.Json)),
  enum_values: option.Option(List(Value)),
) -> List(#(String, json.Json)) {
  enum_values
  |> option.map(fn(values) {
    add_fields(fields, [#("enum", json.array(values, of: value_to_json))])
  })
  |> option.unwrap(fields)
}

// Helper to add items property
fn add_optional_items(
  fields: List(#(String, json.Json)),
  items: option.Option(SchemaProperty),
) -> List(#(String, json.Json)) {
  items
  |> option.map(fn(items_prop) {
    add_fields(fields, [#("items", property_to_json(items_prop))])
  })
  |> option.unwrap(fields)
}

// Helper to add properties dict if present
fn add_optional_properties(
  fields: List(#(String, json.Json)),
  properties: option.Option(List(#(String, SchemaProperty))),
) -> List(#(String, json.Json)) {
  case properties {
    option.None -> fields
    option.Some(props) -> add_properties_object(fields, props)
  }
}

// Helper to add oneOf array if present
fn add_optional_one_of(
  fields: List(#(String, json.Json)),
  one_of: option.Option(List(SchemaProperty)),
) -> List(#(String, json.Json)) {
  one_of
  |> option.map(fn(schemas) {
    add_fields(fields, [
      #("oneOf", json.array(schemas, of: property_to_json)),
    ])
  })
  |> option.unwrap(fields)
}

/// Convert a SchemaProperty to JSON.
fn property_to_json(prop: SchemaProperty) -> json.Json {
  []
  |> add_optional_json_field("$ref", prop.ref, json.string)
  |> add_optional_json_field("type", prop.field_type, fn(ft) {
    json.string(field_type_to_string(ft))
  })
  |> add_optional_json_field("title", prop.title, json.string)
  |> add_optional_json_field("description", prop.description, json.string)
  |> add_optional_json_field("default", prop.default, value_to_json)
  |> add_optional_enum(prop.enum_values)
  |> add_optional_one_of(prop.one_of)
  |> fn(fields) {
    prop.string_constraints
    |> option.map(add_string_constraint_fields(fields, _))
    |> option.unwrap(fields)
  }
  |> fn(fields) {
    prop.number_constraints
    |> option.map(add_number_constraint_fields(fields, _))
    |> option.unwrap(fields)
  }
  |> fn(fields) {
    prop.array_constraints
    |> option.map(add_array_constraint_fields(fields, _))
    |> option.unwrap(fields)
  }
  |> add_optional_items(prop.items)
  |> add_optional_properties(prop.properties)
  |> add_required_array(prop.required)
  |> add_read_only(prop.read_only)
  |> add_optional_json_field(
    "x-widget",
    option.map(prop.render_hints.widget, widget_to_string),
    json.string,
  )
  |> add_optional_upload_config(prop.render_hints.upload_config)
  |> json.object()
}

/// Add readOnly field if true.
fn add_read_only(
  fields: List(#(String, json.Json)),
  read_only: Bool,
) -> List(#(String, json.Json)) {
  case read_only {
    True -> add_fields(fields, [#("readOnly", json.bool(True))])
    False -> fields
  }
}

/// Add upload config x- fields if present.
fn add_optional_upload_config(
  fields: List(#(String, json.Json)),
  config: option.Option(UploadConfig),
) -> List(#(String, json.Json)) {
  case config {
    option.None -> fields
    option.Some(UploadConfig(accept, max_file_size)) ->
      fields
      |> add_fields([#("x-accept", json.string(accept))])
      |> add_optional_json_field("x-max-file-size", max_file_size, json.int)
  }
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
  fields
  |> add_optional_json_field("minLength", constraints.min_length, json.int)
  |> add_optional_json_field("maxLength", constraints.max_length, json.int)
  |> add_optional_json_field("pattern", constraints.pattern, json.string)
  |> add_optional_json_field("format", constraints.format, fn(fmt) {
    json.string(string_format_to_string(fmt))
  })
}

/// Add number constraint fields to a field list.
fn add_number_constraint_fields(
  fields: List(#(String, json.Json)),
  constraints: NumberConstraints,
) -> List(#(String, json.Json)) {
  fields
  |> add_optional_json_field("minimum", constraints.minimum, json.float)
  |> add_optional_json_field("maximum", constraints.maximum, json.float)
  |> add_optional_json_field(
    "exclusiveMinimum",
    constraints.exclusive_minimum,
    json.float,
  )
  |> add_optional_json_field(
    "exclusiveMaximum",
    constraints.exclusive_maximum,
    json.float,
  )
  |> add_optional_json_field("multipleOf", constraints.multiple_of, json.float)
}

/// Add array constraint fields to a field list.
fn add_array_constraint_fields(
  fields: List(#(String, json.Json)),
  constraints: ArrayConstraints,
) -> List(#(String, json.Json)) {
  fields
  |> add_optional_json_field("minItems", constraints.min_items, json.int)
  |> add_optional_json_field("maxItems", constraints.max_items, json.int)
}

/// Convert a Widget variant back to its `x-widget` JSON Schema string.
fn widget_to_string(widget: Widget) -> String {
  case widget {
    ImageUploadWidget -> "image-upload"
    HiddenWidget -> "hidden"
    SwipeReviewWidget -> "swipe-review"
    CustomWidget(raw) -> raw
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
    CustomFormat(name) -> name
  }
}

/// Convert a ConditionalRule to JSON.
fn conditional_to_json(conditional: ConditionalRule) -> json.Json {
  []
  |> add_fields([#("if", property_to_json(conditional.if_schema))])
  |> add_optional_json_field("then", conditional.then_schema, property_to_json)
  |> add_optional_json_field("else", conditional.else_schema, property_to_json)
  |> json.object()
}

/// Add conditional fields directly to schema fields (for single conditional).
fn add_conditional_fields(
  fields: List(#(String, json.Json)),
  conditional: ConditionalRule,
) -> List(#(String, json.Json)) {
  fields
  |> add_fields([#("if", property_to_json(conditional.if_schema))])
  |> add_optional_json_field("then", conditional.then_schema, property_to_json)
  |> add_optional_json_field("else", conditional.else_schema, property_to_json)
}
