// Tests for the read-only ("review") rendering path.
//
// Exercises the whole-form switch in `view.view` when `FormModel.read_only`
// is True: scalar label→value rows, boolean Yes/No, oneOf human labels,
// nested object groups, and arrays of flat objects rendered as tables — plus
// the regression guard that edit mode still renders inputs.

import formosh/form/model.{FormModel}
import formosh/form/view
import formosh/schema/parser
import formosh/schema/types
import formosh/schema/ui_parser
import gleam/string
import gleeunit/should
import lustre/element

fn sample_schema() -> types.JsonSchema {
  let json =
    "{
      \"type\": \"object\",
      \"title\": \"Patient\",
      \"properties\": {
        \"name\": { \"type\": \"string\", \"title\": \"Full name\" },
        \"active\": { \"type\": \"boolean\", \"title\": \"Active\" },
        \"severity\": {
          \"type\": \"string\",
          \"title\": \"Severity\",
          \"oneOf\": [
            { \"const\": \"lo\", \"title\": \"Low\" },
            { \"const\": \"hi\", \"title\": \"High\" }
          ]
        },
        \"address\": {
          \"type\": \"object\",
          \"title\": \"Address\",
          \"properties\": {
            \"city\": { \"type\": \"string\", \"title\": \"City\" }
          }
        },
        \"lesions\": {
          \"type\": \"array\",
          \"title\": \"Lesions\",
          \"items\": {
            \"type\": \"object\",
            \"properties\": {
              \"side\": { \"type\": \"string\", \"title\": \"Side\" },
              \"size\": { \"type\": \"integer\", \"title\": \"Size\" }
            }
          }
        }
      }
    }"
  let assert Ok(schema) = parser.parse_schema(json)
  schema
}

fn sample_values() -> types.Value {
  types.ObjectValue([
    #("name", types.StringValue("Jane Doe")),
    #("active", types.BooleanValue(True)),
    #("severity", types.StringValue("hi")),
    #("address", types.ObjectValue([#("city", types.StringValue("Berlin"))])),
    #(
      "lesions",
      types.ArrayValue([
        types.ObjectValue([
          #("side", types.StringValue("left")),
          #("size", types.IntegerValue(3)),
        ]),
        types.ObjectValue([
          #("side", types.StringValue("right")),
          #("size", types.IntegerValue(5)),
        ]),
      ]),
    ),
  ])
}

fn render(read_only: Bool) -> String {
  FormModel(
    ..model.init(sample_schema()),
    values: sample_values(),
    read_only: read_only,
  )
  |> view.view
  |> element.to_string
}

pub fn readonly_view_renders_scalar_rows_test() {
  let html = render(True)
  html |> string.contains("part=\"readonly-value\"") |> should.be_true
  html |> string.contains("Jane Doe") |> should.be_true
}

pub fn readonly_view_renders_boolean_as_yes_test() {
  render(True) |> string.contains("Yes") |> should.be_true
}

pub fn readonly_view_renders_oneof_label_not_code_test() {
  // Stored value is the code "hi"; the summary must show the oneOf title.
  render(True) |> string.contains("High") |> should.be_true
}

pub fn readonly_view_renders_object_group_test() {
  let html = render(True)
  html |> string.contains("part=\"readonly-group\"") |> should.be_true
  html |> string.contains("Berlin") |> should.be_true
}

pub fn readonly_view_renders_array_of_objects_as_table_test() {
  let html = render(True)
  html |> string.contains("part=\"readonly-table\"") |> should.be_true
  html |> string.contains("part=\"readonly-th\"") |> should.be_true
  html |> string.contains("left") |> should.be_true
  html |> string.contains("right") |> should.be_true
}

pub fn readonly_table_hides_uischema_hidden_columns_test() {
  // A column hidden via the parallel UiSchema (`ui:widget: "hidden"`, not the
  // deprecated x-widget) must be dropped from the read-only table — header
  // and every cell — just like every other field honours hidden widgets.
  let ui_json =
    "{ \"lesions\": { \"items\": { \"size\": { \"ui:widget\": \"hidden\" } } } }"
  let assert Ok(ui) = ui_parser.parse(ui_json)
  let html =
    FormModel(
      ..model.init(sample_schema()),
      ui_schema: ui,
      values: sample_values(),
      read_only: True,
    )
    |> view.view
    |> element.to_string
  html |> string.contains("part=\"readonly-table\"") |> should.be_true
  html |> string.contains("Side") |> should.be_true
  html |> string.contains("Size") |> should.be_false
}

pub fn readonly_view_hides_submit_and_inputs_test() {
  let html = render(True)
  // No footer (Submit/Reset) and no editable inputs in review mode.
  html |> string.contains("formosh-submit") |> should.be_false
  html |> string.contains("part=\"input\"") |> should.be_false
}

pub fn readonly_view_renders_integer_oneof_label_test() {
  // Non-string oneOf consts must resolve to their title too (int key parity).
  let json =
    "{ \"type\": \"object\", \"properties\": { \"grade\": { \"type\": \"integer\", \"title\": \"Grade\", \"oneOf\": [ { \"const\": 1, \"title\": \"First\" }, { \"const\": 2, \"title\": \"Second\" } ] } } }"
  let assert Ok(schema) = parser.parse_schema(json)
  let html =
    FormModel(
      ..model.init(schema),
      values: types.ObjectValue([#("grade", types.IntegerValue(2))]),
      read_only: True,
    )
    |> view.view
    |> element.to_string
  html |> string.contains("Second") |> should.be_true
}

pub fn readonly_table_falls_back_to_groups_for_conditional_items_test() {
  // Item-level conditionals can't be a fixed-column table; the array falls back
  // to per-row groups, which resolve the then-branch field for each row.
  let json =
    "{ \"type\": \"object\", \"properties\": { \"rows\": { \"type\": \"array\", \"items\": { \"type\": \"object\", \"properties\": { \"kind\": { \"type\": \"string\" } }, \"allOf\": [ { \"if\": { \"properties\": { \"kind\": { \"const\": \"x\" } } }, \"then\": { \"properties\": { \"extra\": { \"type\": \"string\", \"title\": \"Extra\" } } } } ] } } } }"
  let assert Ok(schema) = parser.parse_schema(json)
  let html =
    FormModel(
      ..model.init(schema),
      values: types.ObjectValue([
        #(
          "rows",
          types.ArrayValue([
            types.ObjectValue([
              #("kind", types.StringValue("x")),
              #("extra", types.StringValue("shown")),
            ]),
          ]),
        ),
      ]),
      read_only: True,
    )
    |> view.view
    |> element.to_string
  html |> string.contains("part=\"readonly-table\"") |> should.be_false
  html |> string.contains("shown") |> should.be_true
}

pub fn edit_view_still_renders_inputs_test() {
  // Regression guard: the read_only switch must not affect edit mode.
  let html = render(False)
  html |> string.contains("part=\"readonly-value\"") |> should.be_false
  html |> string.contains("formosh-submit") |> should.be_true
}
