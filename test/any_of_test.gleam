import formosh/schema/parser
import formosh/schema/types
import gleam/list
import gleam/option
import gleeunit/should

pub fn anyof_optional_scalar_collapses_test() {
  let schema_json =
    "{\"type\":\"object\",\"properties\":{\"age\":{\"anyOf\":[{\"type\":\"integer\"},{\"type\":\"null\"}]}}}"
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(#(_, age)) = list.first(schema.properties)
  age.field_type |> should.equal(option.Some(types.IntegerType))
  age.nullable |> should.be_true()
  age.any_of |> should.equal(option.None)
}
