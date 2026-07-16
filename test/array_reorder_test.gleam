import formosh/fields/field_common
import formosh/fields/field_dispatcher
import formosh/form/model.{FormModel}
import formosh/form/path
import formosh/schema/types
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import lustre/element

fn empty_schema() -> types.JsonSchema {
  types.JsonSchema(
    title: None,
    description: None,
    field_type: types.ObjectType,
    properties: [],
    required: [],
    defs: None,
    conditionals: [],
    all_of: None,
    string_constraints: None,
    number_constraints: None,
  )
}

fn array_property() -> types.SchemaProperty {
  types.SchemaProperty(
    ..types.empty_property(),
    field_type: Some(types.ArrayType),
    items: Some(
      types.SchemaProperty(
        ..types.empty_property(),
        field_type: Some(types.StringType),
      ),
    ),
  )
}

fn render_tags(items: List(types.Value)) -> String {
  let m =
    FormModel(
      ..model.init(empty_schema()),
      values: types.ObjectValue([#("tags", types.ArrayValue(items))]),
    )
  let ctx =
    field_common.make_field_ctx(
      model: m,
      path: path.from_field_name("tags"),
      property: array_property(),
      is_required: False,
      is_disabled: False,
      is_readonly: False,
    )
  field_dispatcher.render_field_at_path(ctx, m)
  |> element.to_string
}

pub fn array_shows_move_buttons_test() {
  let html =
    render_tags([
      types.StringValue("a"),
      types.StringValue("b"),
      types.StringValue("c"),
    ])
  string.contains(html, "move-array-item-up") |> should.be_true
  string.contains(html, "move-array-item-down") |> should.be_true
}

pub fn array_boundary_button_disabled_test() {
  // 3 rows: only row 0's ▲ and row 2's ▼ are disabled; interior buttons stay
  // enabled, so exactly two `disabled` attributes render regardless of length.
  let html =
    render_tags([
      types.StringValue("a"),
      types.StringValue("b"),
      types.StringValue("c"),
    ])
  count_occurrences(html, "disabled") |> should.equal(2)
}

fn count_occurrences(haystack: String, needle: String) -> Int {
  list.length(string.split(haystack, needle)) - 1
}

pub fn single_item_array_hides_move_buttons_test() {
  let html = render_tags([types.StringValue("only")])
  string.contains(html, "move-array-item-up") |> should.be_false
  string.contains(html, "move-array-item-down") |> should.be_false
}
