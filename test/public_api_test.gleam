import formosh
import formosh/form/model.{HttpSubmit, NoSubmit}
import formosh/form/path.{PropertySegment, get_at_path}
import formosh/schema/parser
import formosh/schema/types.{StringValue}
import formosh/schema/ui_schema
import gleam/dict
import gleam/option.{None, Some}
import gleeunit/should

fn name_schema() {
  let assert Ok(schema) =
    parser.parse_schema(
      "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}},\"required\":[\"name\"]}",
    )
  schema
}

pub fn init_model_applies_initial_values_test() {
  let model =
    formosh.config(name_schema())
    |> formosh.with_initial_values(
      dict.from_list([#("name", StringValue("Ada"))]),
    )
    |> formosh.init_model
  formosh.get_values(model)
  |> get_at_path([PropertySegment("name")])
  |> should.equal(Some(StringValue("Ada")))
}

pub fn config_defaults_test() {
  let config = formosh.config(name_schema())
  config.submit_config |> should.equal(NoSubmit)
  config.show_errors_on_change |> should.be_false()
  config.show_readonly_fields |> should.be_false()
  config.initial_values |> should.equal(dict.new())
  config.ui_schema |> should.equal(ui_schema.empty_ui_schema())
  config.validator |> should.equal(None)
}

pub fn with_submit_url_pins_post_test() {
  let config =
    formosh.config(name_schema())
    |> formosh.with_submit_url("https://x/submit")
  config.submit_config
  |> should.equal(
    HttpSubmit("https://x/submit", "POST", [
      #("Content-Type", "application/json"),
    ]),
  )
}

pub fn builder_chain_composes_test() {
  let config =
    formosh.config(name_schema())
    |> formosh.with_show_readonly_fields(True)
    |> formosh.with_submit_url("https://x/submit")
  config.show_readonly_fields |> should.be_true()
  config.show_errors_on_change |> should.be_false()
}

pub fn from_json_string_invalid_test() {
  formosh.from_json_string("not json") |> should.be_error()
}

pub fn from_json_string_valid_test() {
  formosh.from_json_string(
    "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}}}",
  )
  |> should.be_ok()
}

pub fn with_ui_schema_json_invalid_test() {
  formosh.config(name_schema())
  |> formosh.with_ui_schema_json("{")
  |> should.be_error()
}

pub fn parse_ui_schema_roundtrip_test() {
  formosh.parse_ui_schema("{\"ui:placeholder\":\"hi\"}") |> should.be_ok()
  formosh.parse_ui_schema("{") |> should.be_error()
}
