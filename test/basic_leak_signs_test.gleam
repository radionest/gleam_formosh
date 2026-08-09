/// Test for parsing basic_leak_signs.json schema
import dom_containment
import formosh/form/model
import formosh/form/view
import formosh/schema/conditional_resolver
import formosh/schema/parser
import formosh/schema/properties
import formosh/schema/types.{BooleanValue, ObjectValue}
import formosh/schema/ui_parser
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit
import gleeunit/should
import lustre/element
import simplifile

pub fn main() {
  gleeunit.main()
}

/// Test that basic_leak_signs.json parses correctly
pub fn parse_basic_leak_signs_schema_test() {
  let assert Ok(schema_json) =
    simplifile.read("demo/schemas/basic_leak_signs.json")

  let parse_result = parser.parse_schema(schema_json)

  // Should parse successfully
  parse_result
  |> should.be_ok()

  let assert Ok(schema) = parse_result

  // Should have a title
  schema.title
  |> should.equal(Some("Оценка базовых признаков несостоятельности"))

  // Should have base properties
  schema.properties
  |> properties.has_key("air_bubble")
  |> should.be_true()

  // Should have 4 conditional rules from allOf
  schema.conditionals
  |> list.length()
  |> should.equal(4)
}

/// Test that conditional fields appear when checkboxes are checked
pub fn conditional_fields_appear_test() {
  let assert Ok(schema_json) =
    simplifile.read("demo/schemas/basic_leak_signs.json")

  let assert Ok(schema) = parser.parse_schema(schema_json)

  // Initially, no conditional fields should be present
  schema.properties
  |> properties.has_key("air_bubble_size")
  |> should.be_false()

  // When air_bubble is true, conditional fields should appear
  let form_values = ObjectValue([#("air_bubble", BooleanValue(True))])

  let resolved_schema =
    conditional_resolver.resolve_conditional_schema(schema, form_values)

  // Now air_bubble_size should be present
  resolved_schema.properties
  |> properties.has_key("air_bubble_size")
  |> should.be_true()

  resolved_schema.properties
  |> properties.has_key("air_bubble_number")
  |> should.be_true()

  resolved_schema.properties
  |> properties.has_key("air_bubble_distance")
  |> should.be_true()

  resolved_schema.properties
  |> properties.has_key("air_bubble_location")
  |> should.be_true()
}

/// Test that multiple conditionals work independently
pub fn multiple_conditionals_independent_test() {
  let assert Ok(schema_json) =
    simplifile.read("demo/schemas/basic_leak_signs.json")

  let assert Ok(schema) = parser.parse_schema(schema_json)

  // Enable air_bubble and pneumoperitoneum
  let form_values =
    ObjectValue([
      #("air_bubble", BooleanValue(True)),
      #("pneumoperitoneum", BooleanValue(True)),
    ])

  let resolved_schema =
    conditional_resolver.resolve_conditional_schema(schema, form_values)

  // Should have fields from both conditionals
  resolved_schema.properties
  |> properties.has_key("air_bubble_size")
  |> should.be_true()

  resolved_schema.properties
  |> properties.has_key("pneumoperitoneum_thickness")
  |> should.be_true()

  // Should NOT have fields from other conditionals
  resolved_schema.properties
  |> properties.has_key("ascites_type")
  |> should.be_false()

  resolved_schema.properties
  |> properties.has_key("ileus_diametr")
  |> should.be_false()
}

/// `ui:layout` groups the ascites detail fields under the "Асцит" checkbox
/// instead of leaving them to trail after `ileus` in raw conditional-inject
/// order. This is the automated substitute for eyeballing `make demo`: same
/// schema/ui-schema pair, same trigger, checked against the rendered HTML
/// instead of a browser.
pub fn ui_layout_relocates_ascites_thickness_test() {
  let assert Ok(schema_json) =
    simplifile.read("demo/schemas/basic_leak_signs.json")
  let assert Ok(ui_json) =
    simplifile.read("demo/schemas/basic_leak_signs.ui.json")

  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(ui) = ui_parser.parse(ui_json)

  let values = ObjectValue([#("ascites", BooleanValue(True))])
  let m =
    model.FormModel(
      ..model.init(schema),
      ui_schema: ui,
      values: values,
      resolved_schema: model.recompute_resolved_schema(schema, values, []),
    )
  let html = view.view(m) |> element.to_string

  // The layout nests four groups in document order: "Пузырьки газа",
  // "Свободный газ", "Асцит" (third), "Кишечная непроходимость" (fourth,
  // containing `ileus`). Skip past the first two `part="group"` markers,
  // then bound the third group's own subtree — proving `ascites_thickness`
  // is actually nested inside the "Асцит" group, not merely textually
  // ahead of `ileus`.
  let assert Ok(#(_, after_first_group)) =
    string.split_once(html, "part=\"group\"")
  let assert Ok(#(_, after_second_group)) =
    string.split_once(after_first_group, "part=\"group\"")
  let assert Ok(ascites_group) =
    dom_containment.slice_element(after_second_group, "part=\"group\"")

  ascites_group |> string.contains("Асцит") |> should.be_true()
  ascites_group
  |> string.contains("data-name=\"ascites_thickness\"")
  |> should.be_true()
}
