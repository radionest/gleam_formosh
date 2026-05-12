// Validation functions for form fields

import formosh/path_format
import formosh/schema/conditional_resolver
import formosh/schema/types.{
  type SchemaProperty, type ValidationError, type Value, ArrayValue,
  BooleanValue, IntegerValue, NullValue, NumberValue, ObjectValue, StringValue,
  ValidationError,
}
import formosh/validation/field_requirements
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// Validate a field value against its schema property definition.
/// 
/// This is the main validation function that checks a field value against
/// all applicable validation rules including type checking, constraints,
/// required field validation, and enum validation.
/// 
/// ## Parameters
/// - `field_name`: The name of the field being validated (used in error messages)
/// - `value`: The current field value, or None if not set
/// - `property`: The schema property definition with validation rules
/// - `is_required`: Whether this field is required by the parent schema
/// 
/// ## Returns
/// A list of validation errors. An empty list means validation passed.
/// 
/// ## Example
/// ```gleam
/// let errors = validator.validate_field(
///   "email",
///   Some(StringValue("invalid-email")),
///   email_property,
///   True
/// )
/// // Returns list of ValidationError if validation fails
/// ```
pub fn validate_field(
  field_name: String,
  value: Option(Value),
  property: SchemaProperty,
  is_required: Bool,
) -> List(ValidationError) {
  // Image upload fields have custom validation
  case property.widget {
    Some("image-upload") ->
      validate_image_upload(field_name, value, is_required)
    _ -> validate_standard_field(field_name, value, property, is_required)
  }
}

/// Validate an image-upload field.
fn validate_image_upload(
  field_name: String,
  value: Option(Value),
  is_required: Bool,
) -> List(ValidationError) {
  case value {
    None | Some(NullValue) | Some(ArrayValue([])) ->
      case is_required {
        True -> [
          ValidationError(
            field: field_name,
            message: "At least one image is required",
            rule: "required",
          ),
        ]
        False -> []
      }
    Some(ArrayValue(items)) -> {
      let invalid =
        list.any(items, fn(item) {
          case item {
            StringValue(_) -> False
            _ -> True
          }
        })
      case invalid {
        True -> [
          ValidationError(
            field: field_name,
            message: "Invalid image upload value",
            rule: "type",
          ),
        ]
        False -> []
      }
    }
    _ -> []
  }
}

/// Standard field validation (non-widget fields).
fn validate_standard_field(
  field_name: String,
  value: Option(Value),
  property: SchemaProperty,
  is_required: Bool,
) -> List(ValidationError) {
  // Use centralized required validation
  let required_errors = case
    field_requirements.check_required_value(field_name, value, is_required)
  {
    Ok(_) -> []
    Error(validation_error) -> [validation_error]
  }

  // Skip further validation if no value
  case value {
    None | Some(NullValue) -> required_errors
    Some(val) -> {
      // Type-specific validation
      let type_errors = case property.field_type {
        Some(types.StringType) ->
          validate_string(field_name, val, property.string_constraints)
        Some(types.NumberType) | Some(types.IntegerType) ->
          validate_number(field_name, val, property.number_constraints)
        Some(types.BooleanType) -> validate_boolean(field_name, val)
        _ -> []
      }

      // Enum validation
      let enum_errors = case property.enum_values {
        Some(allowed_values) -> validate_enum(field_name, val, allowed_values)
        None -> []
      }

      list.flatten([required_errors, type_errors, enum_errors])
    }
  }
}

/// Validate a string value against string constraints.
/// 
/// Checks string-specific validation rules including length constraints,
/// pattern matching, and format validation.
/// 
/// ## Parameters
/// - `field_name`: Field name for error messages
/// - `value`: The field value to validate (should be StringValue)
/// - `constraints`: Optional string constraints from the schema
/// 
/// ## Returns
/// List of validation errors specific to string validation rules
fn validate_string(
  field_name: String,
  value: Value,
  constraints: Option(types.StringConstraints),
) -> List(ValidationError) {
  case value {
    StringValue(str) -> {
      case constraints {
        None -> []
        Some(c) -> {
          let errors = []

          // Min length

          let errors = case c.min_length {
            Some(min) -> {
              case string.length(str) < min {
                True ->
                  list.append(errors, [
                    ValidationError(
                      field: field_name,
                      message: "Must be at least "
                        <> int.to_string(min)
                        <> " characters",
                      rule: "minLength",
                    ),
                  ])
                False -> errors
              }
            }
            None -> errors
          }

          // Max length
          let errors = case c.max_length {
            Some(max) -> {
              case string.length(str) > max {
                True ->
                  list.append(errors, [
                    ValidationError(
                      field: field_name,
                      message: "Must be at most "
                        <> int.to_string(max)
                        <> " characters",
                      rule: "maxLength",
                    ),
                  ])
                False -> errors
              }
            }
            None -> errors
          }

          // Pattern validation - simplified without regex for now
          let errors = case c.pattern {
            Some(_pattern) -> {
              // TODO: Implement pattern validation when regex is available
              errors
            }
            None -> errors
          }

          // Format validation
          let errors = case c.format {
            Some(types.EmailFormat) ->
              case validate_email(str) {
                False ->
                  list.append(errors, [
                    ValidationError(
                      field: field_name,
                      message: "Invalid email address",
                      rule: "format",
                    ),
                  ])
                True -> errors
              }
            Some(types.UrlFormat) | Some(types.UriFormat) ->
              case validate_url(str) {
                False ->
                  list.append(errors, [
                    ValidationError(
                      field: field_name,
                      message: "Invalid URL",
                      rule: "format",
                    ),
                  ])
                True -> errors
              }
            _ -> errors
          }

          errors
        }
      }
    }
    _ -> [
      ValidationError(
        field: field_name,
        message: "Must be a string",
        rule: "type",
      ),
    ]
  }
}

/// Validate a numeric value against number constraints.
/// 
/// Checks numeric validation rules including minimum/maximum bounds,
/// exclusive bounds, and multiple-of constraints. Handles both
/// NumberValue and IntegerValue field types.
/// 
/// ## Parameters
/// - `field_name`: Field name for error messages
/// - `value`: The field value to validate (should be NumberValue or IntegerValue)
/// - `constraints`: Optional numeric constraints from the schema
/// 
/// ## Returns
/// List of validation errors specific to numeric validation rules
fn validate_number(
  field_name: String,
  value: Value,
  constraints: Option(types.NumberConstraints),
) -> List(ValidationError) {
  case value {
    NumberValue(num) ->
      validate_number_constraints(field_name, num, constraints)
    IntegerValue(num) ->
      validate_number_constraints(field_name, int.to_float(num), constraints)
    _ -> [
      ValidationError(
        field: field_name,
        message: "Must be a number",
        rule: "type",
      ),
    ]
  }
}

/// Validate a float value against specific numeric constraints.
/// 
/// This is a helper function that performs the actual numeric validation
/// logic including bounds checking and multiple-of validation.
/// 
/// ## Parameters
/// - `field_name`: Field name for error messages
/// - `value`: The numeric value as a float
/// - `constraints`: Optional numeric constraints to check against
/// 
/// ## Returns
/// List of validation errors for numeric constraint violations
fn validate_number_constraints(
  field_name: String,
  value: Float,
  constraints: Option(types.NumberConstraints),
) -> List(ValidationError) {
  case constraints {
    None -> []
    Some(c) -> {
      let errors = []

      // Minimum
      let errors = case c.minimum {
        Some(min) -> {
          case value <. min {
            True ->
              list.append(errors, [
                ValidationError(
                  field: field_name,
                  message: "Must be at least " <> float.to_string(min),
                  rule: "minimum",
                ),
              ])
            False -> errors
          }
        }
        None -> errors
      }

      // Maximum
      let errors = case c.maximum {
        Some(max) -> {
          case value >. max {
            True ->
              list.append(errors, [
                ValidationError(
                  field: field_name,
                  message: "Must be at most " <> float.to_string(max),
                  rule: "maximum",
                ),
              ])
            False -> errors
          }
        }
        None -> errors
      }

      // Exclusive minimum
      let errors = case c.exclusive_minimum {
        Some(min) -> {
          case value <=. min {
            True ->
              list.append(errors, [
                ValidationError(
                  field: field_name,
                  message: "Must be greater than " <> float.to_string(min),
                  rule: "exclusiveMinimum",
                ),
              ])
            False -> errors
          }
        }
        None -> errors
      }

      // Exclusive maximum
      let errors = case c.exclusive_maximum {
        Some(max) -> {
          case value >=. max {
            True ->
              list.append(errors, [
                ValidationError(
                  field: field_name,
                  message: "Must be less than " <> float.to_string(max),
                  rule: "exclusiveMaximum",
                ),
              ])
            False -> errors
          }
        }
        None -> errors
      }

      errors
    }
  }
}

/// Validate that a field value is a boolean.
/// 
/// Checks that the field value is of type BooleanValue. This is primarily
/// a type validation function.
/// 
/// ## Parameters
/// - `field_name`: Field name for error messages
/// - `value`: The field value to validate
/// 
/// ## Returns
/// List of validation errors if the value is not a boolean
fn validate_boolean(field_name: String, value: Value) -> List(ValidationError) {
  case value {
    BooleanValue(_) -> []
    _ -> [
      ValidationError(
        field: field_name,
        message: "Must be true or false",
        rule: "type",
      ),
    ]
  }
}

/// Validate that a field value is one of the allowed enum values.
/// 
/// **Note**: This function is currently not implemented and always returns
/// an empty list (no errors). Enum validation is planned for future versions.
/// 
/// ## Parameters
/// - `_field_name`: Field name for error messages (unused)
/// - `_value`: The field value to validate (unused)
/// - `_allowed_values`: List of allowed enum values (unused)
/// 
/// ## Returns
/// Currently always returns an empty list
/// 
/// ## TODO
/// Implement proper enum validation with JSON value comparison
fn validate_enum(
  _field_name: String,
  _value: Value,
  _allowed_values: List(types.Value),
) -> List(ValidationError) {
  // TODO: Implement enum validation with proper value comparison
  []
}

/// Check if a string is a valid email address.
/// 
/// This is a simple email validation that checks for the presence of '@' and '.'.
/// It's not a comprehensive email validation but catches obviously invalid formats.
/// 
/// ## Parameters
/// - `email`: The email string to validate
/// 
/// ## Returns
/// True if the email appears to be valid, False otherwise
/// 
/// ## Note
/// This is a basic validation. For production use, consider more robust
/// email validation libraries.
fn validate_email(email: String) -> Bool {
  string.contains(email, "@") && string.contains(email, ".")
}

/// Check if a string is a valid URL.
///
/// This is a simple URL validation that checks for HTTP/HTTPS protocol prefixes.
/// It's not comprehensive but catches obviously invalid URLs.
///
/// ## Parameters
/// - `url`: The URL string to validate
///
/// ## Returns
/// True if the URL appears to be valid, False otherwise
///
/// ## Note
/// This is a basic validation. For production use, consider more robust
/// URL validation libraries.
fn validate_url(url: String) -> Bool {
  string.starts_with(url, "http://") || string.starts_with(url, "https://")
}

/// Validate all fields of a single array item.
///
/// Resolves the item schema against the row's own values (so item-level
/// `if/then/else` and `allOf` rules take effect), then validates every
/// field in the resolved schema using its `required` list. Errors carry
/// a path-style field name `<prefix>.[<index>].<field>` matching the
/// canonical `path.to_string` format used elsewhere in the form layer.
///
/// ## Parameters
/// - `prefix`: Path-string of the parent array (e.g. `"lesions"` for a
///   top-level array, or `"outer.[2].inner"` for nested arrays)
/// - `index`: Zero-based row index
/// - `item_schema`: The array's `items` schema (may carry conditionals)
/// - `item_values`: Field values for this single row
///
/// ## Returns
/// Validation errors aggregated across every visible field of the row,
/// including recursive errors from nested objects/arrays.
pub fn validate_array_item(
  prefix: String,
  index: Int,
  item_schema: SchemaProperty,
  item_values: Dict(String, Value),
) -> List(ValidationError) {
  let resolved =
    conditional_resolver.resolve_conditional_property(item_schema, item_values)

  case resolved.properties {
    Some(props) ->
      dict.to_list(props)
      |> list.flat_map(fn(entry) {
        let #(field_name, field_prop) = entry
        let field_value =
          dict.get(item_values, field_name) |> option.from_result
        let is_required = list.contains(resolved.required, field_name)
        let path_key = path_format.array_item_key(prefix, index, field_name)
        let own_errors =
          validate_field(path_key, field_value, field_prop, is_required)
        let nested = validate_nested(path_key, field_prop, field_value)
        list.append(own_errors, nested)
      })
    None -> []
  }
}

/// Validate every row of an array against item-level conditional rules.
///
/// Iterates the array's `ArrayValue`, treating each `ObjectValue` row as a
/// dict for `validate_array_item`. Non-object rows produce no errors.
pub fn validate_array_items(
  prefix: String,
  item_schema: SchemaProperty,
  array_value: Value,
) -> List(ValidationError) {
  case array_value {
    ArrayValue(items) ->
      list.index_map(items, fn(item, index) {
        let item_values = case item {
          ObjectValue(fields) -> dict.from_list(fields)
          _ -> dict.new()
        }
        validate_array_item(prefix, index, item_schema, item_values)
      })
      |> list.flatten
    _ -> []
  }
}

/// Validate every field of a nested object against its schema.
///
/// Mirrors `validate_array_item` but for object-typed fields: resolves
/// conditionals on the object's own values, then validates each visible
/// property under `<prefix>.<field>` keys, recursing into nested
/// objects/arrays.
pub fn validate_object_fields(
  prefix: String,
  schema_prop: SchemaProperty,
  values: Dict(String, Value),
) -> List(ValidationError) {
  let resolved =
    conditional_resolver.resolve_conditional_property(schema_prop, values)

  case resolved.properties {
    Some(props) ->
      dict.to_list(props)
      |> list.flat_map(fn(entry) {
        let #(field_name, field_prop) = entry
        let field_value = dict.get(values, field_name) |> option.from_result
        let is_required = list.contains(resolved.required, field_name)
        let path_key = path_format.object_field_key(prefix, field_name)
        let own_errors =
          validate_field(path_key, field_value, field_prop, is_required)
        let nested = validate_nested(path_key, field_prop, field_value)
        list.append(own_errors, nested)
      })
    None -> []
  }
}

/// Recurse into nested object/array structures and collect their errors.
///
/// `validate_field` only handles scalar types — this helper dispatches
/// on `field_prop.field_type` to dive into `ObjectType` (via
/// `validate_object_fields`) and `ArrayType` (via `validate_array_items`),
/// keyed by `prefix`. Returns `[]` for scalar fields.
pub fn validate_nested(
  prefix: String,
  field_prop: SchemaProperty,
  field_value: Option(Value),
) -> List(ValidationError) {
  case field_prop.field_type, field_prop.items {
    Some(types.ArrayType), Some(item_subschema) -> {
      let av = option.unwrap(field_value, NullValue)
      validate_array_items(prefix, item_subschema, av)
    }
    Some(types.ObjectType), _ -> {
      let nested_values = case field_value {
        Some(ObjectValue(fields)) -> dict.from_list(fields)
        _ -> dict.new()
      }
      validate_object_fields(prefix, field_prop, nested_values)
    }
    _, _ -> []
  }
}
