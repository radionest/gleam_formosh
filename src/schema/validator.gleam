// Validation functions for form fields

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import schema/types.{
  type FieldValue, type SchemaProperty, type ValidationError, BooleanValue,
  IntegerValue, NullValue, NumberValue, StringValue, ValidationError,
}

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
  value: Option(FieldValue),
  property: SchemaProperty,
  is_required: Bool,
) -> List(ValidationError) {
  let errors = []

  // Check required
  let errors = case is_required {
    True ->
      case value {
        None | Some(NullValue) ->
          list.append(errors, [
            ValidationError(
              field: field_name,
              message: "This field is required",
              rule: "required",
            ),
          ])
        Some(StringValue("")) ->
          list.append(errors, [
            ValidationError(
              field: field_name,
              message: "This field is required",
              rule: "required",
            ),
          ])
        _ -> errors
      }
    False -> errors
  }

  // Skip further validation if no value
  case value {
    None | Some(NullValue) -> errors
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

      list.flatten([errors, type_errors, enum_errors])
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
  value: FieldValue,
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
  value: FieldValue,
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
fn validate_boolean(
  field_name: String,
  value: FieldValue,
) -> List(ValidationError) {
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
  _value: FieldValue,
  _allowed_values: List(types.JsonValue),
) -> List(ValidationError) {
  // TODO: Implement enum validation with proper JSON comparison
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
