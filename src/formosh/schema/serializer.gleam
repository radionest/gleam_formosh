// JSON Schema serialization functions

import formosh/schema/types.{
  type ArrayConstraints, type ConditionalRule, type FieldType, type JsonSchema,
  type NumberConstraints, type SchemaProperty, type StringConstraints,
  type StringFormat, type UploadConfig, type Value, type Widget, ArrayType,
  ArrayValue, BooleanType, BooleanValue, CustomFormat, CustomWidget, DateFormat,
  DateTimeFormat, EmailFormat, HiddenWidget, ImageUploadWidget, IntegerType,
  IntegerValue, NullType, NullValue, NumberType, NumberValue, ObjectType,
  ObjectValue, PasswordFormat, StringType, StringValue, SwipeReviewWidget,
  TimeFormat, UploadConfig, UriFormat, UrlFormat, UuidFormat,
}
import formosh/schema/ui_schema.{
  type LayoutNode, type UiProperty, type UiSchema, GroupNode, LeafNode, RowNode,
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

/// Convert a `UiSchema` back to JSON — the inverse of `ui_parser.parse`.
/// Only set fields are emitted, so `empty_ui_schema()` serializes to `{}`.
/// Round-trips only what the parser can produce: `upload` survives
/// re-parsing only beside `widget: Some(ImageUploadWidget)`, and a nested
/// child named `items` is dropped — that key is the array-item template.
pub fn ui_schema_to_json(ui_schema: UiSchema) -> json.Json {
  ui_children_to_fields(ui_schema.properties)
  |> add_optional_json_field("ui:order", ui_schema.order, json.array(
    _,
    json.string,
  ))
  |> add_optional_json_field("ui:layout", ui_schema.layout, layout_to_json)
  |> json.object()
}

fn ui_children_to_fields(
  children: List(#(String, UiProperty)),
) -> List(#(String, json.Json)) {
  list.map(children, fn(child) { #(child.0, ui_property_to_json(child.1)) })
}

fn ui_property_to_json(prop: UiProperty) -> json.Json {
  list.filter(prop.properties, fn(child) { child.0 != "items" })
  |> ui_children_to_fields
  |> add_optional_json_field("ui:widget", prop.widget, fn(widget) {
    json.string(widget_to_string(widget))
  })
  |> add_ui_options(prop.options)
  |> add_optional_json_field("ui:order", prop.order, json.array(_, json.string))
  |> add_optional_json_field("ui:placeholder", prop.placeholder, json.string)
  |> add_optional_json_field("ui:help", prop.help, json.string)
  |> add_optional_json_field("ui:autofocus", prop.autofocus, json.bool)
  |> add_optional_json_field("ui:disabled", prop.disabled, json.bool)
  |> add_optional_json_field("ui:readonly", prop.readonly, json.bool)
  |> add_optional_json_field("ui:title", prop.title, json.string)
  |> add_optional_json_field("ui:description", prop.description, json.string)
  |> add_optional_json_field("ui:addable", prop.addable, json.bool)
  |> add_optional_json_field("ui:removable", prop.removable, json.bool)
  |> add_optional_json_field("ui:orderable", prop.orderable, json.bool)
  |> add_ui_upload(prop.upload)
  |> add_optional_json_field("ui:layout", prop.layout, layout_to_json)
  |> add_optional_json_field("items", prop.items, ui_property_to_json)
  |> json.object()
}

fn add_ui_options(
  fields: List(#(String, json.Json)),
  options: dict.Dict(String, Value),
) -> List(#(String, json.Json)) {
  case dict.is_empty(options) {
    True -> fields
    False ->
      add_fields(fields, [
        #(
          "ui:options",
          dict.to_list(options)
            |> list.map(fn(entry) { #(entry.0, value_to_json(entry.1)) })
            |> json.object(),
        ),
      ])
  }
}

fn add_ui_upload(
  fields: List(#(String, json.Json)),
  upload: option.Option(UploadConfig),
) -> List(#(String, json.Json)) {
  case upload {
    option.None -> fields
    option.Some(UploadConfig(accept, max_file_size)) ->
      fields
      |> add_fields([#("ui:accept", json.string(accept))])
      |> add_optional_json_field("ui:maxFileSize", max_file_size, json.int)
  }
}

fn layout_to_json(nodes: List(LayoutNode)) -> json.Json {
  json.array(nodes, layout_node_to_json)
}

fn layout_node_to_json(node: LayoutNode) -> json.Json {
  case node {
    LeafNode(name) -> json.string(name)
    RowNode(elements) ->
      json.object([
        #("type", json.string("Row")),
        #("elements", layout_to_json(elements)),
      ])
    GroupNode(label, elements) ->
      [#("type", json.string("Group"))]
      |> add_optional_json_field("label", label, json.string)
      |> add_fields([#("elements", layout_to_json(elements))])
      |> json.object()
  }
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

// Helper to add anyOf array if present, appending a null member when the
// node itself is nullable (mirrors add_optional_one_of).
fn add_optional_any_of(
  fields: List(#(String, json.Json)),
  any_of: option.Option(List(SchemaProperty)),
  nullable: Bool,
) -> List(#(String, json.Json)) {
  any_of
  |> option.map(fn(schemas) {
    let members = list.map(schemas, property_to_json)
    let members = case nullable {
      True ->
        list.append(members, [json.object([#("type", json.string("null"))])])
      False -> members
    }
    add_fields(fields, [#("anyOf", json.preprocessed_array(members))])
  })
  |> option.unwrap(fields)
}

// Emit the "type" keyword: a nullable type array for a collapsed optional
// scalar, the plain type string otherwise, or nothing at all when `anyOf`
// is present (the union's members carry their own types).
fn add_type_field(
  fields: List(#(String, json.Json)),
  prop: SchemaProperty,
) -> List(#(String, json.Json)) {
  case prop.any_of {
    option.Some(_) -> fields
    option.None ->
      case prop.nullable, prop.field_type {
        True, option.Some(ft) ->
          add_fields(fields, [
            #(
              "type",
              json.preprocessed_array([
                json.string(field_type_to_string(ft)),
                json.string("null"),
              ]),
            ),
          ])
        _, _ ->
          add_optional_json_field(fields, "type", prop.field_type, fn(ft) {
            json.string(field_type_to_string(ft))
          })
      }
  }
}

/// Convert a SchemaProperty to JSON.
fn property_to_json(prop: SchemaProperty) -> json.Json {
  []
  |> add_optional_json_field("$ref", prop.ref, json.string)
  |> add_type_field(prop)
  |> add_optional_json_field("title", prop.title, json.string)
  |> add_optional_json_field("description", prop.description, json.string)
  |> add_optional_json_field("default", prop.default, value_to_json)
  |> add_optional_enum(prop.enum_values)
  |> add_optional_one_of(prop.one_of)
  |> add_optional_any_of(prop.any_of, prop.nullable)
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
  |> add_unique_items(constraints.unique_items)
}

fn add_unique_items(
  fields: List(#(String, json.Json)),
  unique_items: Bool,
) -> List(#(String, json.Json)) {
  case unique_items {
    True -> add_fields(fields, [#("uniqueItems", json.bool(True))])
    False -> fields
  }
}

/// Convert a Widget variant to its `ui:widget` string.
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
    PasswordFormat -> "password"
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
