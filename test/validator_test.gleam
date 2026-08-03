import formosh/form/path
import formosh/schema/parser
import formosh/schema/types.{
  type SchemaProperty, ArrayValue, IntegerValue, NumberValue, SchemaProperty,
  StringValue, empty_property,
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

fn birth_date_path() -> path.FieldPath {
  path.from_field_name("birth_date")
}

// Newly recognized formats are not validated: promoting "date" from
// CustomFormat to DateFormat must not switch on format validation.
// validator.validate_field's format case only special-cases email/url —
// every other variant, DateFormat included, falls through the catch-all
// untouched. A non-conforming value must not produce a format error.
pub fn date_format_value_is_not_validated_test() {
  let assert Ok(schema) =
    parser.parse_schema(
      "{\"type\": \"object\", \"properties\": {\"birth_date\": {\"type\": \"string\", \"format\": \"date\"}}}",
    )
  let assert Ok(prop) = list.key_find(schema.properties, "birth_date")
  let errors =
    validator.validate_field(
      birth_date_path(),
      Some(StringValue("not-a-date")),
      prop,
      False,
      prop.render_hints.widget,
    )

  errors |> should.equal([])
}

fn n_path() -> path.FieldPath {
  path.from_field_name("n")
}

fn integer_multiple_of(multiple: Float) -> SchemaProperty {
  SchemaProperty(
    ..empty_property(),
    field_type: Some(types.IntegerType),
    number_constraints: Some(
      types.NumberConstraints(
        ..types.empty_number_constraints(),
        multiple_of: Some(multiple),
      ),
    ),
  )
}

fn number_multiple_of(multiple: Float) -> SchemaProperty {
  SchemaProperty(
    ..empty_property(),
    field_type: Some(types.NumberType),
    number_constraints: Some(
      types.NumberConstraints(
        ..types.empty_number_constraints(),
        multiple_of: Some(multiple),
      ),
    ),
  )
}

// #52: multipleOf was parsed (and advertised via the input's step attribute)
// but never enforced. A violating value must produce a "multipleOf" error.
pub fn multiple_of_violation_test() {
  let property = integer_multiple_of(5.0)
  let errors =
    validator.validate_field(
      n_path(),
      Some(IntegerValue(7)),
      property,
      False,
      property.render_hints.widget,
    )

  list.map(errors, fn(e) { e.rule })
  |> should.equal(["multipleOf"])
  let assert [err] = errors
  err.message |> should.equal("Must be a multiple of 5.0")
  err.field |> should.equal(n_path())
}

pub fn multiple_of_satisfied_test() {
  let property = integer_multiple_of(5.0)
  validator.validate_field(
    n_path(),
    Some(IntegerValue(10)),
    property,
    False,
    property.render_hints.widget,
  )
  |> should.equal([])
}

pub fn multiple_of_zero_is_multiple_of_anything_test() {
  let property = integer_multiple_of(5.0)
  validator.validate_field(
    n_path(),
    Some(IntegerValue(0)),
    property,
    False,
    property.render_hints.widget,
  )
  |> should.equal([])
}

pub fn multiple_of_negative_value_satisfied_test() {
  let property = integer_multiple_of(5.0)
  validator.validate_field(
    n_path(),
    Some(IntegerValue(-15)),
    property,
    False,
    property.render_hints.widget,
  )
  |> should.equal([])
}

pub fn multiple_of_negative_value_violation_test() {
  let property = integer_multiple_of(5.0)
  let errors =
    validator.validate_field(
      n_path(),
      Some(IntegerValue(-7)),
      property,
      False,
      property.render_hints.widget,
    )

  list.map(errors, fn(e) { e.rule })
  |> should.equal(["multipleOf"])
}

pub fn multiple_of_float_satisfied_test() {
  let property = number_multiple_of(0.5)
  validator.validate_field(
    n_path(),
    Some(NumberValue(2.5)),
    property,
    False,
    property.render_hints.widget,
  )
  |> should.equal([])
}

pub fn multiple_of_float_violation_test() {
  let property = number_multiple_of(0.5)
  let errors =
    validator.validate_field(
      n_path(),
      Some(NumberValue(1.7)),
      property,
      False,
      property.render_hints.widget,
    )

  list.map(errors, fn(e) { e.rule })
  |> should.equal(["multipleOf"])
}

// 0.3 /. 0.1 computes as 2.9999999999999996 — exact float division would
// reject a value the schema author plainly intended to allow. Tolerance pin:
// keep accepting it (Ajv `multipleOfPrecision: 8` / rjsf-default parity).
pub fn multiple_of_tolerates_decimal_noise_test() {
  let property = number_multiple_of(0.1)
  validator.validate_field(
    n_path(),
    Some(NumberValue(0.3)),
    property,
    False,
    property.render_hints.widget,
  )
  |> should.equal([])
}

// The browser's native stepper on step=0.01 produces values like 19.99
// (decimal arithmetic). The form must not reject values its own step
// buttons generate.
pub fn multiple_of_tolerates_currency_steps_test() {
  let property = number_multiple_of(0.01)
  validator.validate_field(
    n_path(),
    Some(NumberValue(19.99)),
    property,
    False,
    property.render_hints.widget,
  )
  |> should.equal([])
}

// Tolerance must not mask genuine violations: 0.35 is not a multiple of 0.1.
pub fn multiple_of_genuine_float_violation_test() {
  let property = number_multiple_of(0.1)
  let errors =
    validator.validate_field(
      n_path(),
      Some(NumberValue(0.35)),
      property,
      False,
      property.render_hints.widget,
    )

  list.map(errors, fn(e) { e.rule })
  |> should.equal(["multipleOf"])
}

pub fn multiple_of_integer_value_fractional_divisor_test() {
  let property = number_multiple_of(2.5)
  validator.validate_field(
    n_path(),
    Some(IntegerValue(5)),
    property,
    False,
    property.render_hints.widget,
  )
  |> should.equal([])
}

// multipleOf accumulates with the other number constraints instead of
// replacing them.
pub fn multiple_of_combines_with_minimum_test() {
  let property =
    SchemaProperty(
      ..empty_property(),
      field_type: Some(types.IntegerType),
      number_constraints: Some(
        types.NumberConstraints(
          ..types.empty_number_constraints(),
          minimum: Some(10.0),
          multiple_of: Some(5.0),
        ),
      ),
    )
  let errors =
    validator.validate_field(
      n_path(),
      Some(IntegerValue(7)),
      property,
      False,
      property.render_hints.widget,
    )

  list.map(errors, fn(e) { e.rule })
  |> should.equal(["minimum", "multipleOf"])
}

// JSON Schema requires multipleOf > 0; a non-positive divisor is a
// schema-author bug. The constraint is skipped instead of dividing by zero
// or rejecting every value.
pub fn multiple_of_non_positive_divisor_ignored_test() {
  let zero = integer_multiple_of(0.0)
  validator.validate_field(
    n_path(),
    Some(IntegerValue(7)),
    zero,
    False,
    zero.render_hints.widget,
  )
  |> should.equal([])

  let negative = integer_multiple_of(-5.0)
  validator.validate_field(
    n_path(),
    Some(IntegerValue(7)),
    negative,
    False,
    negative.render_hints.widget,
  )
  |> should.equal([])
}

// End-to-end #52 repro: the issue's exact schema, parsed then validated.
pub fn multiple_of_enforced_after_parse_test() {
  let assert Ok(schema) =
    parser.parse_schema(
      "{\"type\": \"object\", \"properties\": {\"n\": {\"type\": \"integer\", \"multipleOf\": 5}}, \"required\": [\"n\"]}",
    )
  let assert Ok(prop) = list.key_find(schema.properties, "n")
  let errors =
    validator.validate_field(
      n_path(),
      Some(IntegerValue(7)),
      prop,
      True,
      prop.render_hints.widget,
    )

  list.map(errors, fn(e) { e.rule })
  |> should.equal(["multipleOf"])
}
