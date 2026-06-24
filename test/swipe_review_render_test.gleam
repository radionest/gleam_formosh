import formosh/fields/field_common
import formosh/fields/swipe_review_field
import formosh/form/model.{UpdateFieldPath}
import formosh/form/path.{PropertySegment}
import formosh/form/update
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

const ui_json = "{\"zones\":{\"ui:widget\":\"swipe-review\",\"ui:options\":{\"swipeRight\":{\"value\":\"positive\",\"label\":\"Карциноматоз\"},\"swipeLeft\":{\"value\":\"negative\",\"label\":\"Чисто\"},\"button\":{\"value\":\"inaccessible\",\"label\":\"Недоступна\"}}}}"

// Two zones (a, b) in one region — for the shrinking-sheet behaviour.
const schema2_json = "{\"type\":\"object\",\"properties\":{\"zones\":{\"type\":\"object\",\"properties\":{\"r\":{\"type\":\"object\",\"title\":\"Region\",\"properties\":{\"a\":{\"type\":\"string\",\"title\":\"Zone A\",\"enum\":[\"positive\",\"negative\",\"inaccessible\"]},\"b\":{\"type\":\"string\",\"title\":\"Zone B\",\"enum\":[\"positive\",\"negative\",\"inaccessible\"]}}}}}}}"

fn render_model(schema: types.JsonSchema, m: model.FormModel) -> String {
  let zones_path = [PropertySegment("zones")]
  let assert option.Some(prop) = properties.get(schema.properties, "zones")
  let ctx =
    field_common.make_field_ctx(
      model: m,
      path: zones_path,
      property: prop,
      is_required: False,
      is_disabled: False,
      is_readonly: False,
    )
  swipe_review_field.render(ctx, m) |> element.to_string
}

fn render() -> String {
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(ui) = ui_parser.parse(ui_json)
  let m = model.init_with_full_config(schema, None, False, dict.new(), ui)
  let zones_path = [PropertySegment("zones")]
  let assert option.Some(prop) = properties.get(schema.properties, "zones")
  let ctx =
    field_common.make_field_ctx(
      model: m,
      path: zones_path,
      property: prop,
      is_required: False,
      is_disabled: False,
      is_readonly: False,
    )
  swipe_review_field.render(ctx, m) |> element.to_string
}

pub fn shows_zone_title_test() {
  render() |> string.contains("Zone A") |> should.be_true
}

pub fn shows_choice_labels_test() {
  let html = render()
  html |> string.contains("Карциноматоз") |> should.be_true
  html |> string.contains("Чисто") |> should.be_true
  html |> string.contains("Недоступна") |> should.be_true
}

pub fn shows_progress_test() {
  render() |> string.contains("0 / 1") |> should.be_true
}

pub fn exposes_part_test() {
  render() |> string.contains("swipe-review") |> should.be_true
}

pub fn shows_review_summary_when_all_answered_test() {
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(ui) = ui_parser.parse(ui_json)
  let m = model.init_with_full_config(schema, None, False, dict.new(), ui)
  let zone_path = [
    PropertySegment("zones"),
    PropertySegment("r"),
    PropertySegment("a"),
  ]
  let #(updated_model, _) =
    update.update(m, UpdateFieldPath(zone_path, types.StringValue("positive")))
  let zones_path = [PropertySegment("zones")]
  let assert option.Some(prop) = properties.get(schema.properties, "zones")
  let ctx =
    field_common.make_field_ctx(
      model: updated_model,
      path: zones_path,
      property: prop,
      is_required: False,
      is_disabled: False,
      is_readonly: False,
    )
  let html = swipe_review_field.render(ctx, updated_model) |> element.to_string
  html |> string.contains("Все зоны просмотрены") |> should.be_true
  html |> string.contains("Карциноматоз") |> should.be_true
  html |> string.contains("0 / 1") |> should.be_false
}

pub fn sheet_shows_all_unanswered_zones_test() {
  let assert Ok(schema) = parser.parse_schema(schema2_json)
  let assert Ok(ui) = ui_parser.parse(ui_json)
  let m = model.init_with_full_config(schema, None, False, dict.new(), ui)
  let html = render_model(schema, m)
  html |> string.contains("Zone A") |> should.be_true
  html |> string.contains("Zone B") |> should.be_true
  html |> string.contains("0 / 2") |> should.be_true
}

pub fn sheet_shrinks_when_zone_answered_test() {
  let assert Ok(schema) = parser.parse_schema(schema2_json)
  let assert Ok(ui) = ui_parser.parse(ui_json)
  let m = model.init_with_full_config(schema, None, False, dict.new(), ui)
  let path_a = [
    PropertySegment("zones"),
    PropertySegment("r"),
    PropertySegment("a"),
  ]
  let #(m2, _) =
    update.update(m, UpdateFieldPath(path_a, types.StringValue("positive")))
  let html = render_model(schema, m2)
  html |> string.contains("Zone B") |> should.be_true
  html |> string.contains("Zone A") |> should.be_false
  html |> string.contains("1 / 2") |> should.be_true
}
