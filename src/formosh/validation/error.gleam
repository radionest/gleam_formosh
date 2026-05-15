// Validation error type.
//
// Lives in its own module so the field is typed as `FieldPath` without
// creating a cycle with `formosh/schema/types` (which is imported by
// `formosh/form/path`).

import formosh/form/path.{type FieldPath}
import formosh/validation/messages.{type MessageParams}

/// A validation error for a specific field.
///
/// `field` is the canonical path to the failing field, including array
/// indices for items inside arrays. Use `path.to_string(error.field)` when
/// a path-string is needed for keying or display.
pub type ValidationError {
  ValidationError(field: FieldPath, message: String, rule: String)
}

/// Build a `ValidationError` from message params.
///
/// Derives both `message` and `rule` from the params, keeping the rendered
/// text and JSON Schema keyword in sync by construction.
pub fn from_params(
  field_path: FieldPath,
  params: MessageParams,
) -> ValidationError {
  ValidationError(
    field: field_path,
    message: messages.format(params),
    rule: messages.rule_of(params),
  )
}
