/// Canonical path-string formatting helpers.
///
/// Single source of truth for the string representation of field paths used
/// as keys in `FormModel.errors`, `upload_states`, etc. Both
/// `formosh/form/path.to_string` and `formosh/schema/validator` build their
/// path keys through these helpers, so a change in format only happens here.
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

/// Append an array-item field onto an existing path-string prefix.
///
/// `array_item_key("lesions", 0, "visible") == "lesions.[0].visible"`.
pub fn array_item_key(prefix: String, index: Int, field: String) -> String {
  prefix <> "." <> array_index_segment(index) <> "." <> field
}

/// Append a property field onto an existing path-string prefix.
///
/// `object_field_key("address", "street") == "address.street"`.
pub fn object_field_key(prefix: String, field: String) -> String {
  prefix <> "." <> field
}
