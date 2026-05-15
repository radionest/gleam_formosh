// Validation error type.
//
// Lives in its own module so the field is typed as `FieldPath` without
// creating a cycle with `formosh/schema/types` (which is imported by
// `formosh/form/path`).

import formosh/form/path.{type FieldPath}
import formosh/validation/messages.{type ValidationFailure}

/// A validation error for a specific field.
///
/// `field` is the canonical path to the failing field, including array
/// indices for items inside arrays. Use `path.to_string(error.field)` when
/// a path-string is needed for keying or display.
pub type ValidationError {
  ValidationError(field: FieldPath, message: String, rule: String)
}

/// Build a `ValidationError` from a `ValidationFailure`.
///
/// Derives both `message` and `rule` from the failure variant, keeping the
/// rendered text and JSON Schema keyword in sync by construction.
pub fn from_failure(
  field_path: FieldPath,
  failure: ValidationFailure,
) -> ValidationError {
  ValidationError(
    field: field_path,
    message: messages.format(failure),
    rule: messages.rule_of(failure),
  )
}
