//// Row-editor arrays whose `items` are bare scalars render one editable
//// field per row, wired to the row's own path (issue #129) — previously
//// such rows rendered only move/remove controls.

import formosh/fields/field_common
import formosh/fields/field_dispatcher
import formosh/form/model
import formosh/form/path.{ArraySegment, PropertySegment}
import formosh/form/update
import formosh/schema/parser
import formosh/schema/properties
import formosh/schema/types
import gleam/option.{Some}
import gleam/string
import gleeunit/should
import lustre/element

const string_items = "{\"type\":\"object\",\"properties\":{\"tags\":{\"type\":\"array\",\"items\":{\"type\":\"string\",\"title\":\"Тег\"}}}}"

const number_items = "{\"type\":\"object\",\"properties\":{\"scores\":{\"type\":\"array\",\"items\":{\"type\":\"number\"}}}}"

fn model_with(schema_json: String, values: types.Value) -> model.FormModel {
  let assert Ok(schema) = parser.parse_schema(schema_json)
  model.FormModel(..model.init(schema), values: values)
}

fn render(m: model.FormModel, name: String) -> String {
  let assert Some(prop) = properties.get(m.schema.properties, name)
  let ctx =
    field_common.make_field_ctx(
      model: m,
      path: [PropertySegment(name)],
      property: prop,
      is_required: False,
      is_disabled: False,
      is_readonly: False,
    )
  field_dispatcher.render_field_at_path(ctx, m) |> element.to_string
}

pub fn string_items_render_input_per_row_test() {
  let m =
    model_with(
      string_items,
      types.ObjectValue([
        #("tags", types.ArrayValue([types.StringValue("a")])),
      ]),
    )
  let html = render(m, "tags")
  // The row's field wrapper addresses the row itself…
  html |> string.contains("data-path=\"tags.[0]\"") |> should.be_true
  // …and carries an editable input seeded with the row value.
  html |> string.contains("value=\"a\"") |> should.be_true
}

pub fn number_items_render_input_per_row_test() {
  let m =
    model_with(
      number_items,
      types.ObjectValue([
        #("scores", types.ArrayValue([types.NumberValue(1.5)])),
      ]),
    )
  render(m, "scores")
  |> string.contains("data-path=\"scores.[0]\"")
  |> should.be_true
}

pub fn typed_value_lands_on_the_row_path_test() {
  let m0 =
    model_with(
      string_items,
      types.ObjectValue([
        #("tags", types.ArrayValue([types.StringValue("")])),
      ]),
    )
  let #(m1, _) =
    update.update(
      m0,
      model.UpdateFieldPath(
        [PropertySegment("tags"), ArraySegment(0)],
        types.StringValue("hello"),
      ),
    )
  model.get_value_at_path(m1, [
    PropertySegment("tags"),
    ArraySegment(0),
  ])
  |> should.equal(Some(types.StringValue("hello")))
}
