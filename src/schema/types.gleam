// JSON Schema types for form generation

import gleam/dict.{type Dict}
import gleam/option.{type Option, None}
// JSON value type - simplified for now
pub type JsonValue {
  JsonString(String)
  JsonNumber(Float)
  JsonBool(Bool)
  JsonNull
  JsonArray(List(JsonValue))
  JsonObject(List(#(String, JsonValue)))
}

// Basic field types supported by JSON Schema
pub type FieldType {
  StringType
  NumberType
  IntegerType
  BooleanType
  ArrayType
  ObjectType
  NullType
}

// Validation rules for string fields
pub type StringConstraints {
  StringConstraints(
    min_length: Option(Int),
    max_length: Option(Int),
    pattern: Option(String),
    format: Option(StringFormat),
  )
}

// Standard string formats
pub type StringFormat {
  DateFormat
  DateTimeFormat
  TimeFormat
  EmailFormat
  UriFormat
  UrlFormat
  UuidFormat
  RegexFormat
  CustomFormat(String)
}

// Validation rules for numeric fields
pub type NumberConstraints {
  NumberConstraints(
    minimum: Option(Float),
    maximum: Option(Float),
    exclusive_minimum: Option(Float),
    exclusive_maximum: Option(Float),
    multiple_of: Option(Float),
  )
}


// A single property in a JSON schema - simplified
pub type SchemaProperty {
  SchemaProperty(
    field_type: Option(FieldType),
    title: Option(String),
    description: Option(String),
    default: Option(JsonValue),
    enum_values: Option(List(JsonValue)),
    // Type-specific constraints
    string_constraints: Option(StringConstraints),
    number_constraints: Option(NumberConstraints),
    // For array types
    items: Option(SchemaProperty),
    // For object types
    properties: Option(Dict(String, SchemaProperty)),
    required: List(String),
  )
}


// Root JSON Schema definition - simplified
pub type JsonSchema {
  JsonSchema(
    title: String,
    description: Option(String),
    field_type: FieldType,
    properties: Dict(String, SchemaProperty),
    required: List(String),
    // Root-level constraints
    string_constraints: Option(StringConstraints),
    number_constraints: Option(NumberConstraints),
  )
}

// Form field metadata for rendering
pub type FieldMeta {
  FieldMeta(
    name: String,
    label: String,
    help_text: Option(String),
    placeholder: Option(String),
    required: Bool,
    disabled: Bool,
    readonly: Bool,
    hidden: Bool,
  )
}

// Validation error
pub type ValidationError {
  ValidationError(
    field: String,
    message: String,
    rule: String,
  )
}

// Form field value - simplified
pub type FieldValue {
  StringValue(String)
  NumberValue(Float)
  IntegerValue(Int)
  BooleanValue(Bool)
  ArrayValue(List(JsonValue))
  ObjectValue(List(#(String, JsonValue)))
  NullValue
}

// Helper functions to create empty constraints
pub fn empty_string_constraints() -> StringConstraints {
  StringConstraints(
    min_length: None,
    max_length: None,
    pattern: None,
    format: None,
  )
}

pub fn empty_number_constraints() -> NumberConstraints {
  NumberConstraints(
    minimum: None,
    maximum: None,
    exclusive_minimum: None,
    exclusive_maximum: None,
    multiple_of: None,
  )
}

pub fn empty_property() -> SchemaProperty {
  SchemaProperty(
    field_type: None,
    title: None,
    description: None,
    default: None,
    enum_values: None,
    string_constraints: None,
    number_constraints: None,
    items: None,
    properties: None,
    required: [],
  )
}