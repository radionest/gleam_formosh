// Numeric fields with const `oneOf` / `enum` render as the enum widget and
// store the option's typed const (#126) — not a raw number input, and not
// the const stringified.

import formosh
import formosh/form/model
import formosh/form/path.{PropertySegment, get_at_path}
import formosh/form/update
import formosh/form/view
import formosh/schema/parser
import formosh/schema/types.{IntegerValue}
import gleam/dict
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import lustre/dev/query
import lustre/dev/simulate
import lustre/effect
import lustre/element

fn config_for(prop_json: String) {
  let assert Ok(schema) =
    parser.parse_schema(
      "{\"type\":\"object\",\"properties\":{\"n\":" <> prop_json <> "}}",
    )
  formosh.config(schema)
}

fn with_widget(config, widget: String) {
  let assert Ok(config) =
    formosh.with_ui_schema_json(
      config,
      "{\"n\":{\"ui:widget\":\"" <> widget <> "\"}}",
    )
  config
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

fn start_config(config) {
  simulate.application(
    init: fn(_) { #(formosh.init_model(config), effect.none()) },
    update: update.update,
    view: view.view,
  )
  |> simulate.start(Nil)
}

fn start(prop_json: String) {
  start_config(config_for(prop_json))
}

fn html_of(sim) -> String {
  sim |> simulate.view |> element.to_string
}

fn html(prop_json: String) -> String {
  start(prop_json) |> html_of
}

// Markup of the first element matching `selector` in the current view.
fn find(sim, selector) -> String {
  let assert Ok(el) =
    query.find(in: simulate.view(sim), matching: query.element(selector))
  element.to_string(el)
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

pub fn integer_initial_value_checks_its_radio_test() {
  let sim =
    config_for(one_of(2))
    |> formosh.with_initial_values(dict.from_list([#("n", IntegerValue(2))]))
    |> start_config
  find(sim, query.id("n_2")) |> string.contains("checked") |> should.be_true
  find(sim, query.id("n_1")) |> string.contains("checked") |> should.be_false
}

pub fn integer_select_marks_chosen_option_selected_test() {
  start(one_of(6))
  |> change("3")
  |> find(query.attribute("value", "3"))
  |> string.contains("selected")
  |> should.be_true
}

// The placeholder drops the key — `""` would fail the number type check and
// `null` a strict `type`, blocking submit on an optional field either way.
pub fn select_placeholder_removes_numeric_value_test() {
  let sim = start(one_of(6)) |> change("3") |> change("")
  value_of(sim) |> should.equal(None)
  model.can_submit(simulate.model(sim)) |> should.be_true
}

// Previously `""`, which failed `enum` on an optional field.
pub fn select_placeholder_removes_string_value_test() {
  let sim =
    start(
      "{\"type\":\"string\",\"enum\":[\"a\",\"b\",\"c\",\"d\",\"e\",\"f\"]}",
    )
    |> change("b")
    |> change("")
  value_of(sim) |> should.equal(None)
  model.can_submit(simulate.model(sim)) |> should.be_true
}

pub fn integer_enum_radio_stores_integer_test() {
  start("{\"type\":\"integer\",\"enum\":[10,20]}")
  |> simulate.click(on: query.element(query.id("n_20")))
  |> value_of
  |> should.equal(Some(IntegerValue(20)))
}

// Previously stored `"1"`, which failed its own `enum`.
pub fn typeless_numeric_enum_stores_integer_test() {
  let sim =
    start("{\"enum\":[1,2]}")
    |> simulate.click(on: query.element(query.id("n_1")))
  value_of(sim) |> should.equal(Some(IntegerValue(1)))
  model.can_submit(simulate.model(sim)) |> should.be_true
}

pub fn ui_widget_select_forces_select_on_integer_one_of_test() {
  let out =
    config_for(one_of(2)) |> with_widget("select") |> start_config |> html_of
  out |> string.contains("<select") |> should.be_true
  out |> string.contains("Lesion 2") |> should.be_true
}

pub fn ui_widget_radio_forces_radios_on_integer_one_of_test() {
  config_for(one_of(6))
  |> with_widget("radio")
  |> start_config
  |> html_of
  |> string.contains("<select")
  |> should.be_false
}

pub fn ui_widget_select_forces_select_on_string_one_of_test() {
  config_for(
    "{\"type\":\"string\",\"oneOf\":[{\"const\":\"a\",\"title\":\"A\"},{\"const\":\"b\",\"title\":\"B\"}]}",
  )
  |> with_widget("select")
  |> start_config
  |> html_of
  |> string.contains("<select")
  |> should.be_true
}

// A bare `const` parses to a one-value `enum` — nothing to choose between.
pub fn integer_bare_const_keeps_number_input_test() {
  html("{\"type\":\"integer\",\"const\":0}")
  |> string.contains("type=\"number\"")
  |> should.be_true
}

// A oneOf without const options is not an option list — keep the number input.
pub fn integer_non_const_one_of_keeps_number_input_test() {
  html("{\"type\":\"integer\",\"oneOf\":[{\"minimum\":0},{\"maximum\":-10}]}")
  |> string.contains("type=\"number\"")
  |> should.be_true
}
