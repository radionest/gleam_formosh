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

pub fn type_array_with_null_sets_nullable_test() {
  // #42 nullable-union coverage: test/union_type_render_test.gleam already
  // pins that a ["integer","null"] type array renders without crashing;
  // this asserts the structural side of the same fix — `nullable` must
  // also flip, alongside the pre-existing first-known-type collapse.
  let schema_json =
    "{\"type\":\"object\",\"properties\":{\"age\":{\"type\":[\"integer\",\"null\"]}}}"
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(#(_, age)) = list.first(schema.properties)
  age.field_type |> should.equal(option.Some(types.IntegerType))
  age.nullable |> should.be_true()
}

pub fn anyof_two_members_parses_test() {
  let schema_json =
    "{\"type\":\"object\",\"properties\":{\"value\":{\"anyOf\":[{\"type\":\"integer\"},{\"type\":\"string\"}]}}}"
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(#(_, value)) = list.first(schema.properties)
  let assert option.Some(members) = value.any_of
  list.length(members) |> should.equal(2)
  let assert [first, second] = members
  first.field_type |> should.equal(option.Some(types.IntegerType))
  second.field_type |> should.equal(option.Some(types.StringType))
}

pub fn anyof_lenient_skips_malformed_member_test() {
  // 42 is not a schema (nor the allOf-style boolean no-op) — it fails
  // property_decoder and is dropped, leaving the one valid member.
  let schema_json =
    "{\"type\":\"object\",\"properties\":{\"value\":{\"anyOf\":[{\"type\":\"integer\"}, 42]}}}"
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(#(_, value)) = list.first(schema.properties)
  let assert option.Some(members) = value.any_of
  list.length(members) |> should.equal(1)
  let assert [first] = members
  first.field_type |> should.equal(option.Some(types.IntegerType))
}

pub fn anyof_empty_list_is_none_test() {
  let schema_json =
    "{\"type\":\"object\",\"properties\":{\"value\":{\"anyOf\":[]}}}"
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(#(_, value)) = list.first(schema.properties)
  value.any_of |> should.equal(option.None)
}
