/// Canonical path-string formatting helpers.
///
/// Used by `formosh/form/path.to_string` for rendering individual segments.
/// Field/array path keys are built directly from `FieldPath` lists elsewhere
/// in the codebase — there is no more string-based path assembly.
///
/// Format:
/// - property segment: bare name (`"user"`).
/// - array index segment: bracketed (`"[0]"`).
/// - segments joined with `"."`.
///
/// Example: `"lesions.[0].visible"`.
import gleam/int

/// Render an array-index segment (`"[0]"`).
pub fn array_index_segment(index: Int) -> String {
  "[" <> int.to_string(index) <> "]"
}
