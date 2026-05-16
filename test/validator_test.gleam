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
