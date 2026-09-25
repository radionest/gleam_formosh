// Numeric fields with const `oneOf` / `enum` render as the enum widget and
// store the option's typed const (#126) — not a raw number input, and not
// the const stringified.

import formosh
import formosh/form/model
import formosh/form/path.{PropertySegment, get_at_path}
import formosh/form/update
import formosh/form/view
import formosh/schema/parser
import formosh/schema/types.{IntegerValue, NullValue}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should
import lustre/dev/query
import lustre/dev/simulate
import lustre/effect
import lustre/element

fn schema_for(prop_json: String) {
  let assert Ok(schema) =
    parser.parse_schema(
      "{\"type\":\"object\",\"properties\":{\"n\":" <> prop_json <> "}}",
    )
  schema
}

fn one_of(count: Int) -> String {
  let members =
    list.range(1, count)
    |> list.map(fn(i) {
      let s = int.to_string(i)
      "{\"const\":" <> s <> ",\"title\":\"Lesion " <> s <> "\"}"
    })
  "{\"type\":\"integer\",\"oneOf\":[" <> string.join(members, ",") <> "]}"
}

fn start(prop_json: String) {
  let config = formosh.config(schema_for(prop_json))
  simulate.application(
    init: fn(_) { #(formosh.init_model(config), effect.none()) },
    update: update.update,
    view: view.view,
  )
  |> simulate.start(Nil)
}

fn html(prop_json: String) -> String {
  start(prop_json) |> simulate.view |> element.to_string
}

fn value_of(sim) {
  formosh.get_values(simulate.model(sim)) |> get_at_path([PropertySegment("n")])
}

fn change(sim, value: String) {
  simulate.event(
    sim,
    on: query.element(query.tag("select")),
    name: "change",
    data: [
      #("target", json.object([#("value", json.string(value))])),
    ],
  )
}

pub fn integer_one_of_renders_titles_not_number_input_test() {
  let out = html(one_of(2))
  out |> string.contains("Lesion 2") |> should.be_true
  out |> string.contains("type=\"number\"") |> should.be_false
}

pub fn integer_one_of_radio_stores_integer_test() {
  start(one_of(2))
  |> simulate.click(on: query.element(query.id("n_2")))
  |> value_of
  |> should.equal(Some(IntegerValue(2)))
}

pub fn integer_one_of_select_stores_integer_test() {
  start(one_of(6))
  |> change("3")
  |> value_of
  |> should.equal(Some(IntegerValue(3)))
}

// The placeholder must clear a numeric field, not store `""` — that would
// fail the number type check and block submit on an optional field.
pub fn select_placeholder_clears_numeric_field_test() {
  let sim = start(one_of(6)) |> change("3") |> change("")
  value_of(sim) |> should.equal(Some(NullValue))
  model.can_submit(simulate.model(sim)) |> should.be_true
}

pub fn integer_enum_radio_stores_integer_test() {
  start("{\"type\":\"integer\",\"enum\":[10,20]}")
  |> simulate.click(on: query.element(query.id("n_20")))
  |> value_of
  |> should.equal(Some(IntegerValue(20)))
}

// A oneOf without const options is not an option list — keep the number input.
pub fn integer_non_const_one_of_keeps_number_input_test() {
  html("{\"type\":\"integer\",\"oneOf\":[{\"minimum\":0},{\"maximum\":-10}]}")
  |> string.contains("type=\"number\"")
  |> should.be_true
}
