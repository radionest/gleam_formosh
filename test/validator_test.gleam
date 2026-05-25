import formosh/form/path
import formosh/schema/types.{
  type SchemaProperty, ArrayValue, SchemaProperty, StringValue, empty_property,
}
import formosh/schema/validator
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

fn photos_path() -> path.FieldPath {
  path.from_field_name("photos")
}

pub fn image_upload_required_empty_test() {
  let property =
    SchemaProperty(
      ..empty_property(),
      render_hints: types.RenderHints(
        ..types.empty_hints(),
        widget: Some(types.ImageUploadWidget),
      ),
    )

  let errors =
    validator.validate_field(
      photos_path(),
      Some(ArrayValue([])),
      property,
      True,
      property.render_hints.widget,
    )

  should.equal(errors != [], True)
}

pub fn image_upload_required_with_values_test() {
  let property =
    SchemaProperty(
      ..empty_property(),
      render_hints: types.RenderHints(
        ..types.empty_hints(),
        widget: Some(types.ImageUploadWidget),
      ),
    )

  let value =
    Some(
      ArrayValue([StringValue("/uploads/a.jpg"), StringValue("/uploads/b.jpg")]),
    )

  let errors =
    validator.validate_field(
      photos_path(),
      value,
      property,
      True,
      property.render_hints.widget,
    )

  should.equal(errors, [])
}

pub fn image_upload_not_required_empty_test() {
  let property =
    SchemaProperty(
      ..empty_property(),
      render_hints: types.RenderHints(
        ..types.empty_hints(),
        widget: Some(types.ImageUploadWidget),
      ),
    )

  let errors =
    validator.validate_field(
      photos_path(),
      Some(ArrayValue([])),
      property,
      False,
      property.render_hints.widget,
    )

  should.equal(errors, [])
}

pub fn image_upload_required_none_value_test() {
  let property =
    SchemaProperty(
      ..empty_property(),
      render_hints: types.RenderHints(
        ..types.empty_hints(),
        widget: Some(types.ImageUploadWidget),
      ),
    )

  let errors =
    validator.validate_field(
      photos_path(),
      None,
      property,
      True,
      property.render_hints.widget,
    )

  should.equal(errors != [], True)
}

pub fn image_upload_not_required_none_value_test() {
  let property =
    SchemaProperty(
      ..empty_property(),
      render_hints: types.RenderHints(
        ..types.empty_hints(),
        widget: Some(types.ImageUploadWidget),
      ),
    )

  let errors =
    validator.validate_field(
      photos_path(),
      None,
      property,
      False,
      property.render_hints.widget,
    )

  should.equal(errors, [])
}

fn enum_status_property() -> SchemaProperty {
  SchemaProperty(
    ..empty_property(),
    field_type: Some(types.StringType),
    enum_values: Some([StringValue("active"), StringValue("inactive")]),
  )
}

fn status_path() -> path.FieldPath {
  path.from_field_name("status")
}

// Regression: validate_enum used to be a no-op stub that accepted everything.
// A value outside the declared set must now produce a "enum" rule error.
pub fn validate_enum_rejects_value_outside_set_test() {
  let property = enum_status_property()
  let errors =
    validator.validate_field(
      status_path(),
      Some(StringValue("banned")),
      property,
      False,
      property.render_hints.widget,
    )

  list.any(errors, fn(e) { e.rule == "enum" })
  |> should.be_true()
}

// Regression: validate_enum must NOT produce an error when the value is one
// of the allowed enum members.
pub fn validate_enum_accepts_value_in_set_test() {
  let property = enum_status_property()
  let errors =
    validator.validate_field(
      status_path(),
      Some(StringValue("active")),
      property,
      False,
      property.render_hints.widget,
    )

  list.any(errors, fn(e) { e.rule == "enum" })
  |> should.be_false()
}

fn tenant_id_path() -> path.FieldPath {
  path.from_field_name("tenant_id")
}

fn hidden_string_property() -> SchemaProperty {
  SchemaProperty(
    ..empty_property(),
    field_type: Some(types.StringType),
    render_hints: types.RenderHints(
      ..types.empty_hints(),
      widget: Some(types.HiddenWidget),
    ),
  )
}

// Hidden fields participate in validation: a required hidden field without a
// value must surface a required-rule error, otherwise schemas relying on
// default-injected hidden values can silently submit empty payloads.
pub fn hidden_widget_required_missing_value_test() {
  let property = hidden_string_property()
  let errors =
    validator.validate_field(
      tenant_id_path(),
      None,
      property,
      True,
      property.render_hints.widget,
    )

  list.any(errors, fn(e) { e.rule == "required" })
  |> should.be_true()
}

pub fn hidden_widget_required_with_value_test() {
  let property = hidden_string_property()
  let errors =
    validator.validate_field(
      tenant_id_path(),
      Some(StringValue("acme")),
      property,
      True,
      property.render_hints.widget,
    )

  should.equal(errors, [])
}

pub fn hidden_widget_not_required_missing_value_test() {
  let property = hidden_string_property()
  let errors =
    validator.validate_field(
      tenant_id_path(),
      None,
      property,
      False,
      property.render_hints.widget,
    )

  should.equal(errors, [])
}

fn username_path() -> path.FieldPath {
  path.from_field_name("username")
}

fn string_with_pattern(pattern: String) -> SchemaProperty {
  SchemaProperty(
    ..empty_property(),
    field_type: Some(types.StringType),
    string_constraints: Some(types.StringConstraints(
      min_length: None,
      max_length: None,
      pattern: Some(pattern),
      format: None,
    )),
  )
}

pub fn pattern_accepts_matching_value_test() {
  let property = string_with_pattern("^[a-zA-Z0-9_]{3,20}$")
  let errors =
    validator.validate_field(
      username_path(),
      Some(StringValue("alice_42")),
      property,
      False,
      property.render_hints.widget,
    )

  errors |> should.equal([])
}

pub fn pattern_rejects_non_matching_value_test() {
  let property = string_with_pattern("^[a-zA-Z0-9_]{3,20}$")
  let errors =
    validator.validate_field(
      username_path(),
      Some(StringValue("ab!")),
      property,
      False,
      property.render_hints.widget,
    )

  list.any(errors, fn(e) { e.rule == "pattern" })
  |> should.be_true()
}

// Central case: a required field with a non-matching value must produce
// exactly one pattern error (not a duplicate required-error too — required
// only fires when the value is missing/null).
pub fn pattern_required_with_non_matching_value_test() {
  let property = string_with_pattern("^[a-z]+$")
  let errors =
    validator.validate_field(
      username_path(),
      Some(StringValue("Alice123")),
      property,
      True,
      property.render_hints.widget,
    )

  let rules = list.map(errors, fn(e) { e.rule })
  rules |> should.equal(["pattern"])
}

// JSON Schema partial-match semantics: a pattern without anchors matches
// anywhere in the string. `regexp.check` already behaves this way.
pub fn pattern_matches_substring_test() {
  let property = string_with_pattern("foo")
  let errors =
    validator.validate_field(
      username_path(),
      Some(StringValue("barfoobaz")),
      property,
      False,
      property.render_hints.widget,
    )

  errors |> should.equal([])
}

// A syntactically invalid pattern is a schema-author bug, not a user-facing
// validation failure — log via io.println_error and skip the check.
pub fn pattern_invalid_regex_is_skipped_test() {
  let property = string_with_pattern("[unclosed")
  let errors =
    validator.validate_field(
      username_path(),
      Some(StringValue("anything")),
      property,
      False,
      property.render_hints.widget,
    )

  errors |> should.equal([])
}

// Pattern validation does not bypass the required check — a missing value
// still produces the required-rule error, never a pattern error.
pub fn pattern_skipped_for_missing_value_test() {
  let property = string_with_pattern("^[a-z]+$")
  let errors =
    validator.validate_field(
      username_path(),
      None,
      property,
      True,
      property.render_hints.widget,
    )

  list.any(errors, fn(e) { e.rule == "pattern" })
  |> should.be_false()
}

// Optional field with empty string: clearing the field must not surface any
// string-constraint error (pattern, min_length, format). Mirrors rjsf and
// keeps the UX consistent across all string constraints.
pub fn pattern_skipped_for_empty_optional_string_test() {
  let property = string_with_pattern("^[a-z]+$")
  let errors =
    validator.validate_field(
      username_path(),
      Some(StringValue("")),
      property,
      False,
      property.render_hints.widget,
    )

  errors |> should.equal([])
}
