// JSON Schema types for form generation

import gleam/dict.{type Dict}
import gleam/option.{type Option, None}

/// Unified value type for both schema definitions and form values.
/// 
/// This type represents any value that can appear in schemas, form data,
/// or validation constraints. It's used throughout the library for handling
/// all dynamic data in a consistent, type-safe manner.
pub type Value {
  StringValue(String)
  NumberValue(Float)
  IntegerValue(Int)
  BooleanValue(Bool)
  NullValue
  ArrayValue(List(Value))
  ObjectValue(List(#(String, Value)))
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
  RegexFormat(String)
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
/// 
/// The `ref` field supports JSON Schema $ref references, allowing properties
/// to reference definitions stored in $defs or other locations.
pub type SchemaProperty {
  SchemaProperty(
    field_type: Option(FieldType),
    title: Option(String),
    description: Option(String),
    default: Option(Value),
    enum_values: Option(List(Value)),
    // Reference to another schema definition
    ref: Option(String),
    // Type-specific constraints
    string_constraints: Option(StringConstraints),
    number_constraints: Option(NumberConstraints),
    // For array types
    items: Option(SchemaProperty),
    // For object types
    properties: Option(Dict(String, SchemaProperty)),
    required: List(String),
    // JSON Schema readOnly annotation
    read_only: Bool,
  )
}

/// Conditional rule for if/then/else schema logic.
///
/// This type represents a conditional rule that modifies the schema based on
/// runtime values. It implements JSON Schema's if/then/else keywords for
/// dynamic form behavior.
pub type ConditionalRule {
  ConditionalRule(
    // Condition to evaluate (JSON Schema format)
    if_schema: SchemaProperty,
    // Properties to add/modify when condition is true
    then_schema: Option(SchemaProperty),
    // Properties to add/modify when condition is false
    else_schema: Option(SchemaProperty),
  )
}

/// Root JSON Schema definition.
/// 
/// This represents a complete JSON Schema document that defines the structure
/// and validation rules for a form. It contains the top-level properties,
/// required fields, global constraints, and schema definitions that can be
/// referenced using $ref.
/// 
/// The `defs` field stores reusable schema definitions that can be referenced
/// throughout the schema using JSON Pointer syntax (e.g., "#/$defs/Address").
/// 
/// The `conditionals` field contains if/then/else rules for dynamic schema
/// behavior based on runtime form values.
pub type JsonSchema {
  JsonSchema(
    title: String,
    description: Option(String),
    field_type: FieldType,
    properties: Dict(String, SchemaProperty),
    required: List(String),
    // Schema definitions for reuse via $ref
    defs: Option(Dict(String, SchemaProperty)),
    // Conditional rules for dynamic schema behavior
    conditionals: List(ConditionalRule),
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
  ValidationError(field: String, message: String, rule: String)
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
    ref: None,
    string_constraints: None,
    number_constraints: None,
    items: None,
    properties: None,
    required: [],
    read_only: False,
  )
}
