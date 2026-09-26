// Arrays with `uniqueItems: true` whose items carry options render as a
// checkbox group storing the typed consts (openspec change
// add-multi-select-checkboxes).

import formosh/schema/parser
import formosh/schema/serializer
import formosh/schema/types.{ArrayConstraints}
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

const unique_enum = "{\"type\":\"array\",\"uniqueItems\":true,\"items\":{\"type\":\"string\",\"enum\":[\"a\",\"b\",\"c\"]}}"

fn obj(prop_json: String) -> String {
  "{\"type\":\"object\",\"properties\":{\"n\":" <> prop_json <> "}}"
}

fn array_prop(prop_json: String) -> types.SchemaProperty {
  let assert Ok(schema) = parser.parse_schema(obj(prop_json))
  let assert Ok(prop) = list.key_find(schema.properties, "n")
  prop
}

pub fn parses_unique_items_test() {
  array_prop(unique_enum).array_constraints
  |> should.equal(
    Some(ArrayConstraints(min_items: None, max_items: None, unique_items: True)),
  )
}

pub fn all_of_ors_unique_items_in_either_order_test() {
  let unique = "{\"uniqueItems\":true}"
  let max = "{\"maxItems\":3}"
  let with_members = fn(a, b) {
    "{\"type\":\"array\",\"items\":{\"type\":\"string\"},\"allOf\":["
    <> a
    <> ","
    <> b
    <> "]}"
  }
  let expected =
    Some(ArrayConstraints(
      min_items: None,
      max_items: Some(3),
      unique_items: True,
    ))
  array_prop(with_members(unique, max)).array_constraints
  |> should.equal(expected)
  array_prop(with_members(max, unique)).array_constraints
  |> should.equal(expected)
}

pub fn serializer_emits_unique_items_test() {
  let assert Ok(schema) = parser.parse_schema(obj(unique_enum))
  serializer.schema_to_json(schema)
  |> json.to_string
  |> string.contains("\"uniqueItems\":true")
  |> should.be_true
}

pub fn serializer_omits_unset_unique_items_test() {
  let assert Ok(schema) =
    parser.parse_schema(obj(
      "{\"type\":\"array\",\"maxItems\":3,\"items\":{\"type\":\"string\"}}",
    ))
  serializer.schema_to_json(schema)
  |> json.to_string
  |> string.contains("uniqueItems")
  |> should.be_false
}
