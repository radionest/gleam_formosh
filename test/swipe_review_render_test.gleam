import formosh/fields/field_common
import formosh/fields/swipe_review_field
import formosh/form/model
import formosh/form/path.{PropertySegment}
import formosh/schema/parser
import formosh/schema/properties
import formosh/schema/ui_parser
import gleam/dict
import gleam/option.{None}
import gleam/string
import gleeunit/should
import lustre/element

const schema_json = "{\"type\":\"object\",\"properties\":{\"zones\":{\"type\":\"object\",\"properties\":{\"r\":{\"type\":\"object\",\"title\":\"Region\",\"properties\":{\"a\":{\"type\":\"string\",\"title\":\"Zone A\",\"enum\":[\"positive\",\"negative\",\"inaccessible\"]}}}}}}}"

const ui_json = "{\"zones\":{\"ui:widget\":\"swipe-review\",\"ui:options\":{\"swipeRight\":{\"value\":\"positive\",\"label\":\"Карциноматоз\"},\"swipeLeft\":{\"value\":\"negative\",\"label\":\"Чисто\"},\"button\":{\"value\":\"inaccessible\",\"label\":\"Недоступна\"}}}}"

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

pub fn shows_current_zone_title_test() {
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
