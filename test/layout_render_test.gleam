// End-to-end render tests: a ui:layout on a real model must place real
// fields. The date-triple case is the one that motivated the feature —
// {year, month, day} renders as six stacked inputs per row without it.

import formosh/form/model
import formosh/form/view
import formosh/schema/types
import formosh/schema/ui_parser
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import lustre/element

fn int_property(title: String) -> types.SchemaProperty {
  types.SchemaProperty(
    ..types.empty_property(),
    field_type: Some(types.IntegerType),
    title: Some(title),
  )
}

fn date_schema() -> types.JsonSchema {
  types.JsonSchema(
    title: None,
    description: None,
    field_type: types.ObjectType,
    properties: [
      #("year", int_property("Год")),
      #("month", int_property("Месяц")),
      #("day", int_property("День")),
    ],
    required: [],
    defs: None,
    conditionals: [],
    all_of: None,
    string_constraints: None,
    number_constraints: None,
  )
}

fn render_with(ui_json: String) -> String {
  let assert Ok(ui) = ui_parser.parse(ui_json)
  let m = model.init(date_schema())
  view.view(model.FormModel(..m, ui_schema: ui)) |> element.to_string
}

pub fn root_row_places_three_fields_test() {
  let html =
    render_with(
      "{\"ui:layout\":[{\"type\":\"Row\",\"elements\":[\"year\",\"month\",\"day\"]}]}",
    )
  let assert Ok(#(_, after_row)) = string.split_once(html, "part=\"row\"")
  after_row |> string.contains("data-name=\"year\"") |> should.be_true
  after_row |> string.contains("data-name=\"month\"") |> should.be_true
  after_row |> string.contains("data-name=\"day\"") |> should.be_true
}

pub fn root_group_wraps_fields_test() {
  let html =
    render_with(
      "{\"ui:layout\":[{\"type\":\"Group\",\"label\":\"Дата\",\"elements\":[\"year\"]}]}",
    )
  html |> string.contains("Дата") |> should.be_true
  let assert Ok(#(_, after_group_body)) =
    string.split_once(html, "part=\"group-body\"")
  after_group_body |> string.contains("data-name=\"year\"") |> should.be_true
}

pub fn root_leftovers_still_render_test() {
  let html = render_with("{\"ui:layout\":[\"day\"]}")
  html |> string.contains("data-name=\"day\"") |> should.be_true
  html |> string.contains("data-name=\"year\"") |> should.be_true
  html |> string.contains("data-name=\"month\"") |> should.be_true
}

pub fn root_without_layout_is_unchanged_test() {
  let html = render_with("{}")
  html |> string.contains("part=\"row\"") |> should.be_false
  html |> string.contains("part=\"group\"") |> should.be_false
  html |> string.contains("data-name=\"year\"") |> should.be_true
  html |> string.contains("data-name=\"month\"") |> should.be_true
  html |> string.contains("data-name=\"day\"") |> should.be_true
}

pub fn ui_order_without_layout_still_orders_test() {
  let html = render_with("{\"ui:order\":[\"day\",\"year\",\"month\"]}")
  let assert Ok(#(before_year, after_year)) =
    string.split_once(html, "data-name=\"year\"")
  before_year |> string.contains("data-name=\"day\"") |> should.be_true
  after_year |> string.contains("data-name=\"month\"") |> should.be_true
  html |> string.contains("part=\"row\"") |> should.be_false
}

pub fn read_only_root_ignores_layout_test() {
  let assert Ok(ui_with_layout) =
    ui_parser.parse(
      "{\"ui:layout\":[{\"type\":\"Row\",\"elements\":[\"year\",\"month\",\"day\"]}]}",
    )
  let assert Ok(ui_without_layout) = ui_parser.parse("{}")
  let m = model.init(date_schema())
  let with_layout =
    view.view(model.FormModel(..m, ui_schema: ui_with_layout, read_only: True))
    |> element.to_string
  let without_layout =
    view.view(
      model.FormModel(..m, ui_schema: ui_without_layout, read_only: True),
    )
    |> element.to_string
  with_layout |> string.contains("part=\"row\"") |> should.be_false
  with_layout |> should.equal(without_layout)
}

fn nested_object_schema() -> types.JsonSchema {
  types.JsonSchema(..date_schema(), properties: [
    #(
      "start",
      types.SchemaProperty(
        ..types.empty_property(),
        field_type: Some(types.ObjectType),
        title: Some("Начало"),
        properties: Some([
          #("year", int_property("Год")),
          #("month", int_property("Месяц")),
          #("day", int_property("День")),
        ]),
      ),
    ),
  ])
}

fn render_nested_with(ui_json: String) -> String {
  let assert Ok(ui) = ui_parser.parse(ui_json)
  let m = model.init(nested_object_schema())
  view.view(model.FormModel(..m, ui_schema: ui)) |> element.to_string
}

pub fn nested_object_row_test() {
  let html =
    render_nested_with(
      "{\"start\":{\"ui:layout\":[{\"type\":\"Row\",\"elements\":[\"year\",\"month\",\"day\"]}]}}",
    )
  let assert Ok(#(_, after_row)) = string.split_once(html, "part=\"row\"")
  after_row |> string.contains("data-path=\"start.year\"") |> should.be_true
  after_row |> string.contains("data-path=\"start.month\"") |> should.be_true
  after_row |> string.contains("data-path=\"start.day\"") |> should.be_true
}

pub fn nested_object_leftovers_render_test() {
  let html =
    render_nested_with(
      "{\"start\":{\"ui:layout\":[{\"type\":\"Row\",\"elements\":[\"year\"]}]}}",
    )
  html |> string.contains("data-path=\"start.month\"") |> should.be_true
  html |> string.contains("data-path=\"start.day\"") |> should.be_true
}

fn array_schema() -> types.JsonSchema {
  types.JsonSchema(..date_schema(), properties: [
    #(
      "events",
      types.SchemaProperty(
        ..types.empty_property(),
        field_type: Some(types.ArrayType),
        title: Some("События"),
        items: Some(
          types.SchemaProperty(
            ..types.empty_property(),
            field_type: Some(types.ObjectType),
            properties: Some([
              #("year", int_property("Год")),
              #("month", int_property("Месяц")),
            ]),
          ),
        ),
      ),
    ),
  ])
}

pub fn array_row_layout_applies_to_every_row_test() {
  let assert Ok(ui) =
    ui_parser.parse(
      "{\"events\":{\"items\":{\"ui:layout\":[{\"type\":\"Row\",\"elements\":[\"year\",\"month\"]}]}}}",
    )
  let m = model.init(array_schema())
  let with_rows =
    model.FormModel(
      ..m,
      ui_schema: ui,
      values: types.ObjectValue([
        #(
          "events",
          types.ArrayValue([
            types.ObjectValue([]),
            types.ObjectValue([]),
          ]),
        ),
      ]),
    )
  let html = view.view(with_rows) |> element.to_string
  // Row 0's own row must contain row 0's own year — and row 1 must have
  // produced a SECOND `part="row"` marker of its own (not merely have its
  // fields fall after row 0's), otherwise a layout that only fires for
  // index 0 would pass unnoticed.
  let assert Ok(#(_, after_first_row)) = string.split_once(html, "part=\"row\"")
  after_first_row
  |> string.contains("data-path=\"events.[0].year\"")
  |> should.be_true
  let assert Ok(#(_, after_second_row)) =
    string.split_once(after_first_row, "part=\"row\"")
  after_second_row
  |> string.contains("data-path=\"events.[1].year\"")
  |> should.be_true
}

/// An array whose row schema injects a `note` field via an item-level
/// if/then conditional (`kind == "special"`) — `note` is not a base
/// property, only a then-branch addition (design D4, `union_resolver`).
fn conditional_array_schema() -> types.JsonSchema {
  let note_rule =
    types.ConditionalRule(
      if_schema: types.SchemaProperty(
        ..types.empty_property(),
        properties: Some([
          #(
            "kind",
            types.SchemaProperty(
              ..types.empty_property(),
              enum_values: Some([types.StringValue("special")]),
            ),
          ),
        ]),
      ),
      then_schema: Some(
        types.SchemaProperty(
          ..types.empty_property(),
          properties: Some([#("note", int_property("Заметка"))]),
        ),
      ),
      else_schema: None,
    )
  types.JsonSchema(..date_schema(), properties: [
    #(
      "events",
      types.SchemaProperty(
        ..types.empty_property(),
        field_type: Some(types.ArrayType),
        title: Some("События"),
        items: Some(
          types.SchemaProperty(
            ..types.empty_property(),
            field_type: Some(types.ObjectType),
            properties: Some([
              #(
                "kind",
                types.SchemaProperty(
                  ..types.empty_property(),
                  field_type: Some(types.StringType),
                ),
              ),
              #("year", int_property("Год")),
            ]),
            conditionals: [note_rule],
          ),
        ),
      ),
    ),
  ])
}

pub fn array_row_layout_places_conditionally_injected_field_test() {
  let assert Ok(ui) =
    ui_parser.parse(
      "{\"events\":{\"items\":{\"ui:layout\":[{\"type\":\"Row\",\"elements\":[\"year\",\"note\"]}]}}}",
    )
  let m = model.init(conditional_array_schema())
  let with_rows =
    model.FormModel(
      ..m,
      ui_schema: ui,
      values: types.ObjectValue([
        #(
          "events",
          types.ArrayValue([
            types.ObjectValue([#("kind", types.StringValue("special"))]),
            types.ObjectValue([#("kind", types.StringValue("plain"))]),
          ]),
        ),
      ]),
    )
  let html = view.view(with_rows) |> element.to_string

  // Row 0: the conditional is active (kind = "special"), so `note` is
  // merged into `resolved.properties` and lands at its layout position,
  // inside row 0's own row.
  let assert Ok(#(_, after_first_row)) = string.split_once(html, "part=\"row\"")
  let assert Ok(#(row_0, after_second_row)) =
    string.split_once(after_first_row, "part=\"row\"")
  row_0 |> string.contains("data-path=\"events.[0].note\"") |> should.be_true

  // Row 1: the conditional is inactive (kind = "plain") — `note` never
  // enters that row's resolved properties, so it renders nowhere, while
  // the row's own `year` still renders normally.
  after_second_row
  |> string.contains("data-path=\"events.[1].year\"")
  |> should.be_true
  html |> string.contains("data-path=\"events.[1].note\"") |> should.be_false
}
