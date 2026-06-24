import formosh/fields/field_common
import formosh/fields/swipe_review_field
import formosh/form/model.{UpdateFieldPath}
import formosh/form/path.{PropertySegment}
import formosh/form/update
import formosh/form/widget_msg.{ToggleHideAnswered}
import formosh/schema/parser
import formosh/schema/properties
import formosh/schema/types
import formosh/schema/ui_parser
import gleam/dict
import gleam/option.{None}
import gleam/string
import gleeunit/should
import lustre/element

const schema_json = "{\"type\":\"object\",\"properties\":{\"zones\":{\"type\":\"object\",\"properties\":{\"r\":{\"type\":\"object\",\"title\":\"Region\",\"properties\":{\"a\":{\"type\":\"string\",\"title\":\"Zone A\",\"enum\":[\"positive\",\"negative\",\"inaccessible\"]}}}}}}}"

const ui_json = "{\"zones\":{\"ui:widget\":\"swipe-review\",\"ui:options\":{\"swipeRight\":{\"value\":\"positive\",\"label\":\"Карциноматоз\"},\"swipeLeft\":{\"value\":\"negative\",\"label\":\"Чисто\"},\"button\":{\"value\":\"inaccessible\",\"label\":\"Недоступна\"},\"hideAnsweredLabel\":\"Скрывать отвеченные\"}}}"

const path_a = [
  PropertySegment("zones"),
  PropertySegment("r"),
  PropertySegment("a"),
]

fn init() -> model.FormModel {
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(ui) = ui_parser.parse(ui_json)
  model.init_with_full_config(schema, None, False, dict.new(), ui)
}

fn render_model(schema: types.JsonSchema, m: model.FormModel) -> String {
  let assert option.Some(prop) = properties.get(schema.properties, "zones")
  let ctx =
    field_common.make_field_ctx(
      model: m,
      path: [PropertySegment("zones")],
      property: prop,
      is_required: False,
      is_disabled: False,
      is_readonly: False,
    )
  swipe_review_field.render(ctx, m) |> element.to_string
}

pub fn toggle_flips_hide_answered_test() {
  let m0 = init()
  m0.swipe_hide_answered |> should.be_true
  let #(m1, _) = update.update(m0, model.swipe_msg(ToggleHideAnswered))
  m1.swipe_hide_answered |> should.be_false
  let #(m2, _) = update.update(m1, model.swipe_msg(ToggleHideAnswered))
  m2.swipe_hide_answered |> should.be_true
}

pub fn show_all_keeps_answered_zone_editable_test() {
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let #(m1, _) =
    update.update(
      init(),
      UpdateFieldPath(path_a, types.StringValue("positive")),
    )
  let #(m2, _) = update.update(m1, model.swipe_msg(ToggleHideAnswered))
  let html = render_model(schema, m2)
  // Answered zone stays visible (not filtered out)…
  html |> string.contains("Zone A") |> should.be_true
  // …with its chosen answer marked, and the toggle present.
  html |> string.contains("data-selected=\"true\"") |> should.be_true
  html |> string.contains("Скрывать отвеченные") |> should.be_true
}

pub fn toggle_visible_in_review_summary_test() {
  let assert Ok(schema) = parser.parse_schema(schema_json)
  // Default hide=True: answering the only zone yields the review summary…
  let #(m1, _) =
    update.update(
      init(),
      UpdateFieldPath(path_a, types.StringValue("positive")),
    )
  let html = render_model(schema, m1)
  html |> string.contains("Все зоны просмотрены") |> should.be_true
  // …and the toggle is still reachable to switch back to show-all.
  html |> string.contains("Скрывать отвеченные") |> should.be_true
}
