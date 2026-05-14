import formosh/fields/field_common
import gleam/string
import gleeunit/should
import lustre/element

pub fn render_required_marker_true_test() {
  let html = element.to_string(field_common.render_required_marker(True))
  html |> string.contains("formosh-required") |> should.be_true
  html |> string.contains("*") |> should.be_true
}

pub fn render_required_marker_false_is_empty_test() {
  field_common.render_required_marker(False)
  |> element.to_string
  |> should.equal("")
}
