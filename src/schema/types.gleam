// JSON Schema types for form generation

import gleam/dict.{type Dict}
import gleam/option.{type Option, None}
/// JSON value type representing any valid JSON data.
/// 
/// This type models all possible JSON values that can appear in schemas,
/// form data, or validation constraints. It's used throughout the library
/// for handling dynamic JSON content.
pub type JsonValue {
  JsonString(String)
  JsonNumber(Float)
  JsonBool(Bool)
  JsonNull
  JsonArray(List(JsonValue))
  JsonObject(List(#(String, JsonValue)))
}

/// Field types supported by JSON Schema.
/// 
/// These correspond to the standard JSON Schema primitive types and are used
/// to determine how form fields should be rendered and validated.
pub type FieldType {
  StringType
  NumberType
  IntegerType
  BooleanType
  ArrayType
  ObjectType
  NullType
}

/// Validation constraints for string fields.
/// 
/// These constraints correspond to JSON Schema string validation rules
/// and are used to generate appropriate HTML attributes and validation logic.
pub type StringConstraints {
  StringConstraints(
    min_length: Option(Int),
    max_length: Option(Int),
    pattern: Option(String),
    format: Option(StringFormat),
  )
}

/// Standard string formats defined by JSON Schema.
/// 
/// These formats provide semantic meaning to string fields and enable
/// appropriate input types (email, url, date) and validation rules.
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

/// Validation constraints for numeric fields.
/// 
/// These constraints correspond to JSON Schema numeric validation rules
/// including bounds checking and multiple-of validation.
pub type NumberConstraints {
  NumberConstraints(
    minimum: Option(Float),
    maximum: Option(Float),
    exclusive_minimum: Option(Float),
    exclusive_maximum: Option(Float),
    multiple_of: Option(Float),
  )
}


/// A single property definition within a JSON Schema.
/// 
/// This type represents a complete field definition including its type,
/// validation constraints, metadata, and nested structure for complex types.
/// It serves as the blueprint for generating form fields.
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


/// Root JSON Schema definition.
/// 
/// This represents a complete JSON Schema document that defines the structure
/// and validation rules for a form. It contains the top-level properties,
/// required fields, and global constraints.
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

/// Metadata for form field rendering.
/// 
/// This type contains presentation and behavior information for form fields
/// that affects how they're displayed and interacted with in the UI.
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

/// A validation error for a specific field.
/// 
/// This type represents a single validation failure with the field name,
/// human-readable message, and the validation rule that failed.
pub type ValidationError {
  ValidationError(
    field: String,
    message: String,
    rule: String,
  )
}

/// A form field value with type information.
/// 
/// This type represents the actual data entered in form fields, maintaining
/// type information to enable proper validation and serialization.
pub type FieldValue {
  StringValue(String)
  NumberValue(Float)
  IntegerValue(Int)
  BooleanValue(Bool)
  ArrayValue(List(JsonValue))
  ObjectValue(List(#(String, JsonValue)))
  NullValue
}

/// Create an empty StringConstraints with no validation rules.
/// 
/// This is useful as a default value when no string constraints are specified
/// in the JSON Schema.
/// 
/// ## Returns
/// A StringConstraints with all fields set to None
pub fn empty_string_constraints() -> StringConstraints {
  StringConstraints(
    min_length: None,
    max_length: None,
    pattern: None,
    format: None,
  )
}

/// Create an empty NumberConstraints with no validation rules.
/// 
/// This is useful as a default value when no numeric constraints are specified
/// in the JSON Schema.
/// 
/// ## Returns
/// A NumberConstraints with all fields set to None
pub fn empty_number_constraints() -> NumberConstraints {
  NumberConstraints(
    minimum: None,
    maximum: None,
    exclusive_minimum: None,
    exclusive_maximum: None,
    multiple_of: None,
  )
}

/// Create an empty SchemaProperty with default values.
/// 
/// This is useful as a starting point when building schema properties
/// programmatically or as a fallback for invalid property definitions.
/// 
/// ## Returns
/// A SchemaProperty with all optional fields set to None and empty lists
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