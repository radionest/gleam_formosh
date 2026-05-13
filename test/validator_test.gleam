import formosh/form/path
import formosh/schema/types.{
  ArrayValue, SchemaProperty, StringValue, empty_property,
}
import formosh/schema/validator
import gleam/option.{None, Some}
import gleeunit/should

fn photos_path() -> path.FieldPath {
  path.from_field_name("photos")
}

pub fn image_upload_required_empty_test() {
  let property =
    SchemaProperty(..empty_property(), widget: Some("image-upload"))

  let errors =
    validator.validate_field(
      photos_path(),
      Some(ArrayValue([])),
      property,
      True,
    )

  should.equal(errors != [], True)
}

pub fn image_upload_required_with_values_test() {
  let property =
    SchemaProperty(..empty_property(), widget: Some("image-upload"))

  let value =
    Some(
      ArrayValue([StringValue("/uploads/a.jpg"), StringValue("/uploads/b.jpg")]),
    )

  let errors = validator.validate_field(photos_path(), value, property, True)

  should.equal(errors, [])
}

pub fn image_upload_not_required_empty_test() {
  let property =
    SchemaProperty(..empty_property(), widget: Some("image-upload"))

  let errors =
    validator.validate_field(
      photos_path(),
      Some(ArrayValue([])),
      property,
      False,
    )

  should.equal(errors, [])
}

pub fn image_upload_required_none_value_test() {
  let property =
    SchemaProperty(..empty_property(), widget: Some("image-upload"))

  let errors = validator.validate_field(photos_path(), None, property, True)

  should.equal(errors != [], True)
}

pub fn image_upload_not_required_none_value_test() {
  let property =
    SchemaProperty(..empty_property(), widget: Some("image-upload"))

  let errors = validator.validate_field(photos_path(), None, property, False)

  should.equal(errors, [])
}
