// Two guarantees the design makes that the structural tests do not reach:
//
// 1. properties.merge appends if/then-injected properties at the end of the
//    container, so without a layout a detail field lands far from the
//    checkbox that revealed it. Naming it in a Group must relocate it.
// 2. Review mode (readonly_field) deliberately still uses apply_order, so
//    ui:layout must have no effect there in this version.

import dom_containment
import formosh/form/model
import formosh/form/view
import formosh/schema/types
import formosh/schema/ui_parser
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import lustre/element

fn bool_property(title: String) -> types.SchemaProperty {
  types.SchemaProperty(
    ..types.empty_property(),
    field_type: Some(types.BooleanType),
    title: Some(title),
  )
}

fn number_property(title: String) -> types.SchemaProperty {
  types.SchemaProperty(
    ..types.empty_property(),
    field_type: Some(types.NumberType),
    title: Some(title),
  )
}

/// `ascites` reveals `ascites_thickness`; `ileus` is declared after both, so
/// the injected field would otherwise render below it.
fn leak_schema() -> types.JsonSchema {
  let if_condition =
    types.SchemaProperty(
      ..types.empty_property(),
      properties: Some([
        #(
          "ascites",
          types.SchemaProperty(
            ..types.empty_property(),
            enum_values: Some([types.BooleanValue(True)]),
          ),
        ),
      ]),
    )

  let then_schema =
    types.SchemaProperty(
      ..types.empty_property(),
      properties: Some([#("ascites_thickness", number_property("Толщина, мм"))]),
    )

  types.JsonSchema(
    title: None,
    description: None,
    field_type: types.ObjectType,
    properties: [
      #("ascites", bool_property("Асцит")),
      #("ileus", bool_property("Непроходимость")),
    ],
    required: [],
    defs: None,
    conditionals: [
      types.ConditionalRule(
        if_schema: if_condition,
        then_schema: Some(then_schema),
        else_schema: None,
      ),
    ],
    all_of: None,
    string_constraints: None,
    number_constraints: None,
  )
}

/// Builds the model with `ascites` = true (so the conditional fires) and
/// renders it. `resolved_schema` must go through `model.recompute_resolved_schema`
/// explicitly — `model.init` alone leaves `resolved_schema` equal to the raw
/// (unresolved) schema, so `ascites_thickness` would never reach
/// `render_form_body`'s `ordered_properties`.
fn model_with(ui_json ui_json: String, read_only read_only: Bool) -> String {
  let assert Ok(ui) = ui_parser.parse(ui_json)
  let schema = leak_schema()
  let values = types.ObjectValue([#("ascites", types.BooleanValue(True))])
  let m =
    model.FormModel(
      ..model.init(schema),
      ui_schema: ui,
      read_only: read_only,
      values: values,
      resolved_schema: model.recompute_resolved_schema(schema, values, []),
    )
  view.view(m) |> element.to_string
}

pub fn injected_field_renders_inside_its_group_test() {
  let html =
    model_with(
      ui_json: "{\"ui:layout\":[{\"type\":\"Group\",\"label\":\"Асцит\",\"elements\":[\"ascites\",\"ascites_thickness\"]},\"ileus\"]}",
      read_only: False,
    )
  let assert Ok(group) = dom_containment.slice_element(html, "part=\"group\"")
  group
  |> string.contains("data-name=\"ascites_thickness\"")
  |> should.be_true
  // Presence guard: without this, `ileus` disappearing entirely would also
  // leave it out of `group`, and the exclusion check below would stay
  // green while proving nothing.
  html |> string.contains("data-name=\"ileus\"") |> should.be_true
  group |> string.contains("data-name=\"ileus\"") |> should.be_false
}

pub fn without_layout_injected_field_trails_test() {
  let html = model_with(ui_json: "{}", read_only: False)
  // Presence guard: without this, a conditional that stopped injecting the
  // field entirely would also leave it absent before `ileus` — the negative
  // assertion below would stay green while proving nothing.
  html |> string.contains("data-name=\"ascites_thickness\"") |> should.be_true
  let assert Ok(#(before_ileus, _)) =
    string.split_once(html, "data-name=\"ileus\"")
  before_ileus
  |> string.contains("data-name=\"ascites_thickness\"")
  |> should.be_false
}

pub fn review_mode_ignores_layout_test() {
  let with_layout =
    model_with(
      ui_json: "{\"ui:layout\":[{\"type\":\"Row\",\"elements\":[\"ascites\",\"ileus\"]}]}",
      read_only: True,
    )
  let without_layout = model_with(ui_json: "{}", read_only: True)
  with_layout |> should.equal(without_layout)
  with_layout |> string.contains("part=\"row\"") |> should.be_false
  // Positive pin: the conditional actually fired and the readonly rendering
  // of the injected field is actually present. Without this, a conditional
  // that never fires in review mode (or read-only rendering emitting
  // nothing at all) would leave both HTML strings equal and row-marker-free
  // too — the two assertions above would stay green while proving nothing
  // about the conditional-schema delta this test exists to cover.
  with_layout |> string.contains("Толщина, мм") |> should.be_true
}
