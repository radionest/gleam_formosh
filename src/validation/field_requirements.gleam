// Centralized module for field requirement validation
// This module provides a single source of truth for checking if fields are required
// and validating required field values, eliminating code duplication across the codebase.

import gleam/list
import gleam/option.{type Option, None, Some}
import schema/types.{
  type JsonSchema, type ValidationError, type Value, NullValue, StringValue,
  ValidationError,
}

/// Check if a field is required according to the schema.
///
/// This is the single source of truth for determining if a field is required.
/// It checks whether the field name exists in the schema's required fields list.
///
/// ## Parameters
/// - `schema`: The JSON Schema containing the required fields list
/// - `field_name`: The name of the field to check
///
/// ## Returns
/// True if the field is required, False otherwise
///
/// ## Example
/// ```gleam
/// let is_required = field_requirements.is_required(schema, "email")
/// ```
pub fn is_required(schema: JsonSchema, field_name: String) -> Bool {
  list.contains(schema.required, field_name)
}

/// Validate that a required field has a value.
///
/// This function checks if a field that is marked as required has a valid value.
/// It considers None, NullValue, and empty strings as missing values for required fields.
///
/// ## Parameters
/// - `field_name`: The name of the field being validated (used in error messages)
/// - `value`: The current field value, or None if not set
/// - `is_field_required`: Whether this field is required
///
/// ## Returns
/// - `Ok(Nil)` if validation passes
/// - `Error(ValidationError)` if a required field is missing
///
/// ## Example
/// ```gleam
/// case check_required_value("email", Some(StringValue("")), True) {
///   Ok(_) -> // Field is valid
///   Error(validation_error) -> // Field is required but empty
/// }
/// ```
pub fn check_required_value(
  field_name: String,
  value: Option(Value),
  is_field_required: Bool,
) -> Result(Nil, ValidationError) {
  case is_field_required {
    False -> Ok(Nil)
    True ->
      case value {
        None | Some(NullValue) ->
          Error(ValidationError(
            field: field_name,
            message: "This field is required",
            rule: "required",
          ))
        Some(StringValue("")) ->
          Error(ValidationError(
            field: field_name,
            message: "This field is required",
            rule: "required",
          ))
        _ -> Ok(Nil)
      }
  }
}

/// Check if a value is considered empty for required field validation.
///
/// Helper function to determine if a value should be considered empty
/// when validating required fields.
///
/// ## Parameters
/// - `value`: The value to check
///
/// ## Returns
/// True if the value is considered empty (None, NullValue, or empty string)
///
/// ## Example
/// ```gleam
/// let is_empty = is_empty_value(Some(StringValue(""))) // Returns True
/// ```
pub fn is_empty_value(value: Option(Value)) -> Bool {
  case value {
    None | Some(NullValue) -> True
    Some(StringValue("")) -> True
    _ -> False
  }
}