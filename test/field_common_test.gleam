import formosh/fields/field_common
import formosh/schema/types
import formosh/validation/error
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import lustre/element

pub fn render_required_marker_true_test() {
  let html = element.to_string(field_common.render_required_marker(True))
  html |> string.contains("formosh-required") |> should.be_true
  html |> string.contains("part=\"required\"") |> should.be_true
  html |> string.contains("*") |> should.be_true
}

pub fn render_help_text_has_part_attribute_test() {
  let property =
    types.SchemaProperty(
      ..types.empty_property(),
      description: Some("Enter your name"),
    )
  let html =
    field_common.render_help_text(property)
    |> element.to_string

  html |> string.contains("part=\"help\"") |> should.be_true
  html |> string.contains("Enter your name") |> should.be_true
}

pub fn render_field_errors_has_part_attributes_test() {
  let errors = [
    error.ValidationError(field: [], message: "required", rule: "required"),
  ]
  let html =
    field_common.render_field_errors(errors)
    |> element.to_string

  html |> string.contains("part=\"errors\"") |> should.be_true
  html |> string.contains("part=\"error\"") |> should.be_true
  html |> string.contains("required") |> should.be_true
}

pub fn render_required_marker_false_is_empty_test() {
  field_common.render_required_marker(False)
  |> element.to_string
  |> should.equal("")
}

pub fn render_container_label_uses_title_test() {
  let property =
    types.SchemaProperty(..types.empty_property(), title: Some("Lesions"))
  let html =
    field_common.render_container_label(
      field_name: "lesions",
      property: property,
      is_required: False,
      css_class: "array-label",
    )
    |> element.to_string

  html
  |> string.contains("<label class=\"array-label\">Lesions")
  |> should.be_true
  html |> string.contains("for=") |> should.be_false
}

pub fn render_container_label_formats_fallback_test() {
  let property = types.SchemaProperty(..types.empty_property(), title: None)
  let html =
    field_common.render_container_label(
      field_name: "user_data",
      property: property,
      is_required: False,
      css_class: "object-label",
    )
    |> element.to_string

  html
  |> string.contains("<label class=\"object-label\">User data")
  |> should.be_true
}

pub fn render_container_label_shows_required_marker_test() {
  let property =
    types.SchemaProperty(..types.empty_property(), title: Some("Lesions"))
  let html =
    field_common.render_container_label(
      field_name: "lesions",
      property: property,
      is_required: True,
      css_class: "array-label",
    )
    |> element.to_string

  html |> string.contains("formosh-required") |> should.be_true
}
