import formosh
import formosh/form/path.{PropertySegment, get_at_path}
import formosh/schema/parser
import formosh/schema/types.{StringValue}
import gleam/dict
import gleam/option.{Some}
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
