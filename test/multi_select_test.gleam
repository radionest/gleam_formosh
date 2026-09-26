// Arrays with `uniqueItems: true` whose items carry options render as a
// checkbox group storing the typed consts (openspec change
// add-multi-select-checkboxes).

import formosh
import formosh/form/model
import formosh/form/path.{PropertySegment}
import formosh/form/update
import formosh/form/view
import formosh/schema/parser
import formosh/schema/serializer
import formosh/schema/types.{ArrayConstraints, ArrayValue, StringValue}
import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import lustre/dev/simulate
import lustre/effect
import lustre/element

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

const unique_strings = "{\"type\":\"array\",\"uniqueItems\":true,\"items\":{\"type\":\"string\"}}"

fn config_for(prop_json: String) {
  let assert Ok(schema) = parser.parse_schema(obj(prop_json))
  formosh.config(schema)
}

fn with_n(config, value: types.Value) {
  formosh.with_initial_values(config, dict.from_list([#("n", value)]))
}

fn start_config(config) {
  simulate.application(
    init: fn(_) { #(formosh.init_model(config), effect.none()) },
    update: update.update,
    view: view.view,
  )
  |> simulate.start(Nil)
  // `simulate.start` never runs effects and `init_model` never validates on
  // its own — mirrors `array_constraints_test.model_with_values`, which
  // dispatches the same message before asserting on array-level errors.
  |> simulate.message(model.ValidateForm)
}

fn html_of(sim) -> String {
  sim |> simulate.view |> element.to_string
}

fn rules_at_n(sim) -> List(String) {
  model.get_errors_at_path(simulate.model(sim), [PropertySegment("n")])
  |> list.map(fn(e) { e.rule })
}

// A row-editor array: duplicates arrive through row edits, which touch
// `n.[i]` and never `n` — so the error must show with the array untouched.
pub fn duplicate_items_fail_unique_items_test() {
  let sim =
    config_for(unique_strings)
    |> with_n(ArrayValue([StringValue("a"), StringValue("a")]))
    |> start_config
  rules_at_n(sim) |> should.equal(["uniqueItems"])
  model.can_submit(simulate.model(sim)) |> should.be_false
  html_of(sim) |> string.contains("Items must be unique") |> should.be_true
}

pub fn distinct_items_pass_unique_items_test() {
  let sim =
    config_for(unique_strings)
    |> with_n(ArrayValue([StringValue("a"), StringValue("b")]))
    |> start_config
  rules_at_n(sim) |> should.equal([])
  model.can_submit(simulate.model(sim)) |> should.be_true
}
