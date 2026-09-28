import demo
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

const valid_schema = "{\"type\": \"object\"}"

pub fn broken_schema_draft_keeps_last_valid_form_test() {
  let #(model, _) = demo.init(Nil)
  let #(model, _) = demo.update(model, demo.SchemaEdited(valid_schema))
  let #(model, _) = demo.update(model, demo.SchemaEdited("{\"type\":"))

  model.schema_content |> should.equal(Some(valid_schema))
  model.schema_draft |> should.equal(Some("{\"type\":"))
  model.schema_error |> should.be_some
}

pub fn broken_ui_schema_draft_keeps_last_valid_ui_schema_test() {
  let #(model, _) = demo.init(Nil)
  let #(model, _) = demo.update(model, demo.UiSchemaEdited("{}"))
  let #(model, _) = demo.update(model, demo.UiSchemaEdited("{"))

  model.ui_schema_content |> should.equal(Some("{}"))
  model.ui_schema_error |> should.be_some
}

pub fn blank_ui_schema_draft_drops_ui_schema_test() {
  let #(model, _) = demo.init(Nil)
  let #(model, _) = demo.update(model, demo.UiSchemaEdited("{}"))
  let #(model, _) = demo.update(model, demo.UiSchemaEdited("  "))

  model.ui_schema_content |> should.equal(None)
  model.ui_schema_error |> should.equal(None)
}

pub fn committing_css_recreates_form_test() {
  let #(model, _) = demo.init(Nil)
  let #(committed, _) = demo.update(model, demo.CssCommitted)

  committed.form_key |> should.equal(model.form_key + 1)
}
