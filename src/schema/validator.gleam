// Validation functions for form fields

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import schema/types.{
  type FieldValue, type SchemaProperty, type ValidationError,
  BooleanValue, IntegerValue, NullValue, NumberValue,
  StringValue, ValidationError,
}

// Validate a field value against its schema
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

// Validate string value
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
                      message: "Must be at least " <> int.to_string(min) <> " characters",
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
                      message: "Must be at most " <> int.to_string(max) <> " characters",
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

// Validate number value
fn validate_number(
  field_name: String,
  value: FieldValue,
  constraints: Option(types.NumberConstraints),
) -> List(ValidationError) {
  case value {
    NumberValue(num) -> validate_number_constraints(field_name, num, constraints)
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

// Validate number constraints
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

// Validate boolean value
fn validate_boolean(field_name: String, value: FieldValue) -> List(ValidationError) {
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


// Validate enum value
fn validate_enum(
  _field_name: String,
  _value: FieldValue,
  _allowed_values: List(types.JsonValue),
) -> List(ValidationError) {
  // TODO: Implement enum validation with proper JSON comparison
  []
}

// Check if email format is valid
fn validate_email(email: String) -> Bool {
  string.contains(email, "@") && string.contains(email, ".")
}

// Check if URL format is valid
fn validate_url(url: String) -> Bool {
  string.starts_with(url, "http://") || string.starts_with(url, "https://")
}

