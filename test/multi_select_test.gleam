// Arrays with `uniqueItems: true` whose items carry options render as a
// checkbox group storing the typed consts (openspec change
// add-multi-select-checkboxes).

import formosh
import formosh/form/model
import formosh/form/path.{PropertySegment, get_at_path}
import formosh/form/update
import formosh/form/view
import formosh/schema/parser
import formosh/schema/serializer
import formosh/schema/types.{
  ArrayConstraints, ArrayValue, IntegerValue, StringValue,
}
import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import lustre/dev/query
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

const unique_int_one_of = "{\"type\":\"array\",\"uniqueItems\":true,\"items\":{\"type\":\"integer\",\"oneOf\":[{\"const\":1,\"title\":\"One\"},{\"const\":2,\"title\":\"Two\"},{\"const\":3,\"title\":\"Three\"}]}}"

fn start(prop_json: String) {
  start_config(config_for(prop_json))
}

fn value_of(sim) {
  formosh.get_values(simulate.model(sim))
  |> get_at_path([PropertySegment("n")])
}

pub fn is_multi_select_accepts_option_items_test() {
  array_prop(unique_enum) |> types.is_multi_select |> should.be_true
  array_prop(unique_int_one_of) |> types.is_multi_select |> should.be_true
}

pub fn is_multi_select_rejects_non_option_arrays_test() {
  // Duplicates allowed — keep the row editor.
  array_prop(
    "{\"type\":\"array\",\"items\":{\"type\":\"string\",\"enum\":[\"a\",\"b\"]}}",
  )
  |> types.is_multi_select
  |> should.be_false
  // No options at all.
  array_prop(unique_strings) |> types.is_multi_select |> should.be_false
  // Bare `const` is a one-value enum — nothing to choose.
  array_prop(
    "{\"type\":\"array\",\"uniqueItems\":true,\"items\":{\"type\":\"string\",\"const\":\"a\"}}",
  )
  |> types.is_multi_select
  |> should.be_false
  // oneOf without const members is not an option list.
  array_prop(
    "{\"type\":\"array\",\"uniqueItems\":true,\"items\":{\"type\":\"integer\",\"oneOf\":[{\"minimum\":0},{\"maximum\":-10}]}}",
  )
  |> types.is_multi_select
  |> should.be_false
  // Object items are not scalar.
  array_prop(
    "{\"type\":\"array\",\"uniqueItems\":true,\"items\":{\"type\":\"object\",\"enum\":[{\"a\":1},{\"a\":2}]}}",
  )
  |> types.is_multi_select
  |> should.be_false
}

pub fn min_items_does_not_top_up_checkbox_group_test() {
  let sim =
    start(
      "{\"type\":\"array\",\"uniqueItems\":true,\"minItems\":1,\"items\":{\"type\":\"string\",\"enum\":[\"a\",\"b\"]}}",
    )
  value_of(sim) |> should.equal(None)
  model.can_submit(simulate.model(sim)) |> should.be_true
}

fn config_required(prop_json: String) {
  let assert Ok(schema) =
    parser.parse_schema(
      "{\"type\":\"object\",\"required\":[\"n\"],\"properties\":{\"n\":"
      <> prop_json
      <> "}}",
    )
  formosh.config(schema)
}

// Markup of the element with the given id in the current view.
fn find(sim, id: String) -> String {
  let assert Ok(el) =
    query.find(in: simulate.view(sim), matching: query.element(query.id(id)))
  element.to_string(el)
}

fn click(sim, id: String) {
  simulate.click(sim, on: query.element(query.id(id)))
}

fn occurrences(haystack: String, needle: String) -> Int {
  list.length(string.split(haystack, needle)) - 1
}

pub fn string_enum_renders_checkboxes_not_row_editor_test() {
  let out = start(unique_enum) |> html_of
  occurrences(out, "type=\"checkbox\"") |> should.equal(3)
  out |> string.contains("add-array-item") |> should.be_false
}

pub fn without_unique_items_keeps_row_editor_test() {
  start(
    "{\"type\":\"array\",\"items\":{\"type\":\"string\",\"enum\":[\"a\",\"b\"]}}",
  )
  |> html_of
  |> string.contains("add-array-item")
  |> should.be_true
}

pub fn integer_one_of_renders_titles_test() {
  let out = start(unique_int_one_of) |> html_of
  out |> string.contains("One") |> should.be_true
  out |> string.contains("Three") |> should.be_true
}

pub fn selection_follows_schema_order_with_typed_consts_test() {
  start(unique_int_one_of)
  |> click("n_3")
  |> click("n_1")
  |> value_of
  |> should.equal(Some(ArrayValue([IntegerValue(1), IntegerValue(3)])))
}

pub fn unchecking_last_box_removes_value_test() {
  start(unique_enum)
  |> click("n_a")
  |> click("n_a")
  |> value_of
  |> should.equal(None)
}

pub fn required_group_needs_at_least_one_test() {
  let sim =
    config_required(unique_enum)
    |> start_config
    |> click("n_a")
    |> click("n_a")
  rules_at_n(sim) |> should.equal(["required"])
  model.can_submit(simulate.model(sim)) |> should.be_false
  html_of(sim) |> string.contains("This field is required") |> should.be_true
}

pub fn initial_values_pre_check_boxes_test() {
  let sim =
    config_for(unique_enum)
    |> with_n(ArrayValue([StringValue("b")]))
    |> start_config
  find(sim, "n_b") |> string.contains("checked") |> should.be_true
  find(sim, "n_a") |> string.contains("checked") |> should.be_false
}

pub fn max_items_disables_only_unchecked_boxes_test() {
  let sim =
    start(
      "{\"type\":\"array\",\"uniqueItems\":true,\"maxItems\":2,\"items\":{\"type\":\"string\",\"enum\":[\"a\",\"b\",\"c\"]}}",
    )
    |> click("n_a")
    |> click("n_b")
  find(sim, "n_c") |> string.contains("disabled") |> should.be_true
  find(sim, "n_a") |> string.contains("disabled") |> should.be_false
}

pub fn ui_disabled_disables_every_box_test() {
  let assert Ok(config) =
    config_for(unique_enum)
    |> formosh.with_ui_schema_json("{\"n\":{\"ui:disabled\":true}}")
  let sim = start_config(config)
  find(sim, "n_a") |> string.contains("disabled") |> should.be_true
  find(sim, "n_c") |> string.contains("disabled") |> should.be_true
}

// On a checkbox `required` means "this box must be checked" — the marker
// belongs on the label only.
pub fn boxes_carry_no_required_attribute_test() {
  let sim = config_required(unique_enum) |> start_config
  find(sim, "n_a") |> string.contains("required") |> should.be_false
  html_of(sim)
  |> string.contains("class=\"formosh-required\"")
  |> should.be_true
}

pub fn exposes_checkbox_parts_test() {
  let out = start(unique_enum) |> html_of
  occurrences(out, "part=\"checkbox-list\"") |> should.equal(1)
  occurrences(out, "part=\"checkbox-item\"") |> should.equal(3)
}

pub fn under_min_selection_reports_min_items_test() {
  let sim =
    start(
      "{\"type\":\"array\",\"uniqueItems\":true,\"minItems\":2,\"items\":{\"type\":\"string\",\"enum\":[\"a\",\"b\",\"c\"]}}",
    )
    |> click("n_a")
  rules_at_n(sim) |> should.equal(["minItems"])
  html_of(sim)
  |> string.contains("At least 2 item(s) required")
  |> should.be_true
}

// Review Focus 1 — Pydantic `Optional[set[Literal[...]]]`.
pub fn nullable_any_of_array_renders_checkboxes_test() {
  start("{\"anyOf\":[" <> unique_enum <> ",{\"type\":\"null\"}]}")
  |> html_of
  |> occurrences("type=\"checkbox\"")
  |> should.equal(3)
}

// Review Focus 2 — Pydantic `set[SomeEnum]` puts the enum behind `$ref`.
pub fn ref_items_render_checkboxes_test() {
  let assert Ok(schema) =
    parser.parse_schema(
      "{\"type\":\"object\",\"$defs\":{\"C\":{\"type\":\"string\",\"enum\":[\"a\",\"b\"]}},\"properties\":{\"n\":{\"type\":\"array\",\"uniqueItems\":true,\"items\":{\"$ref\":\"#/$defs/C\"}}}}",
    )
  formosh.config(schema)
  |> start_config
  |> html_of
  |> occurrences("type=\"checkbox\"")
  |> should.equal(2)
}

// Review Focus 3 — ids and writes follow the nested path.
pub fn nested_group_writes_its_own_path_test() {
  let sim =
    start(
      "{\"type\":\"object\",\"properties\":{\"tags\":" <> unique_enum <> "}}",
    )
    |> click("n.tags_b")
  formosh.get_values(simulate.model(sim))
  |> get_at_path([PropertySegment("n"), PropertySegment("tags")])
  |> should.equal(Some(ArrayValue([StringValue("b")])))
}

// Review Focus 4 — options define the domain; a stored non-option drops out.
pub fn stale_non_option_value_drops_on_first_click_test() {
  config_for(unique_enum)
  |> with_n(ArrayValue([StringValue("zzz")]))
  |> start_config
  |> click("n_a")
  |> value_of
  |> should.equal(Some(ArrayValue([StringValue("a")])))
}

// Review Focus 5 — review mode shows titles for the selected consts only.
pub fn review_mode_lists_selected_titles_test() {
  let m =
    config_for(unique_int_one_of)
    |> with_n(ArrayValue([IntegerValue(2)]))
    |> formosh.init_model
  let out =
    view.view(model.FormModel(..m, read_only: True)) |> element.to_string
  out |> string.contains("Two") |> should.be_true
  out |> string.contains("One") |> should.be_false
  out |> string.contains("Three") |> should.be_false
}
