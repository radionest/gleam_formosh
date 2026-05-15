// Validation message catalog. Single source of truth for the human-readable
// text and the JSON Schema rule key of every validation failure.

import gleam/float
import gleam/int

pub type ValidationFailure {
  Required
  ImageRequired
  InvalidImageUpload
  MinLength(min: Int)
  MaxLength(max: Int)
  InvalidEmail
  InvalidUrl
  InvalidType(expected: String)
  InvalidBoolean
  Minimum(min: Float)
  Maximum(max: Float)
  ExclusiveMinimum(min: Float)
  ExclusiveMaximum(max: Float)
  InvalidEnum
}

/// Render the message text for a validation failure.
pub fn format(failure: ValidationFailure) -> String {
  case failure {
    Required -> "This field is required"
    ImageRequired -> "At least one image is required"
    InvalidImageUpload -> "Invalid image upload value"
    MinLength(min) -> "Must be at least " <> int.to_string(min) <> " characters"
    MaxLength(max) -> "Must be at most " <> int.to_string(max) <> " characters"
    InvalidEmail -> "Invalid email address"
    InvalidUrl -> "Invalid URL"
    InvalidType(expected) -> "Must be a " <> expected
    InvalidBoolean -> "Must be true or false"
    Minimum(min) -> "Must be at least " <> float.to_string(min)
    Maximum(max) -> "Must be at most " <> float.to_string(max)
    ExclusiveMinimum(min) -> "Must be greater than " <> float.to_string(min)
    ExclusiveMaximum(max) -> "Must be less than " <> float.to_string(max)
    InvalidEnum -> "Value is not one of the allowed options"
  }
}

/// JSON Schema keyword (rule name) for the given failure variant.
pub fn rule_of(failure: ValidationFailure) -> String {
  case failure {
    Required -> "required"
    ImageRequired -> "required"
    InvalidImageUpload -> "type"
    MinLength(_) -> "minLength"
    MaxLength(_) -> "maxLength"
    InvalidEmail -> "format"
    InvalidUrl -> "format"
    InvalidType(_) -> "type"
    InvalidBoolean -> "type"
    Minimum(_) -> "minimum"
    Maximum(_) -> "maximum"
    ExclusiveMinimum(_) -> "exclusiveMinimum"
    ExclusiveMaximum(_) -> "exclusiveMaximum"
    InvalidEnum -> "enum"
  }
}
