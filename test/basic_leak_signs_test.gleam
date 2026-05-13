/// Test for parsing basic_leak_signs.json schema
import formosh/schema/conditional_resolver
import formosh/schema/parser
import formosh/schema/types.{BooleanValue, ObjectValue, has_property_key}
import gleam/list
import gleam/option.{Some}
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

/// Test that basic_leak_signs.json parses correctly
pub fn parse_basic_leak_signs_schema_test() {
  let assert Ok(schema_json) =
    simplifile.read("examples/file_schema_loader/schemas/basic_leak_signs.json")

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
  |> has_property_key("air_bubble")
  |> should.be_true()

  // Should have 4 conditional rules from allOf
  schema.conditionals
  |> list.length()
  |> should.equal(4)
}

/// Test that conditional fields appear when checkboxes are checked
pub fn conditional_fields_appear_test() {
  let assert Ok(schema_json) =
    simplifile.read("examples/file_schema_loader/schemas/basic_leak_signs.json")

  let assert Ok(schema) = parser.parse_schema(schema_json)

  // Initially, no conditional fields should be present
  schema.properties
  |> has_property_key("air_bubble_size")
  |> should.be_false()

  // When air_bubble is true, conditional fields should appear
  let form_values = ObjectValue([#("air_bubble", BooleanValue(True))])

  let resolved_schema =
    conditional_resolver.resolve_conditional_schema(schema, form_values)

  // Now air_bubble_size should be present
  resolved_schema.properties
  |> has_property_key("air_bubble_size")
  |> should.be_true()

  resolved_schema.properties
  |> has_property_key("air_bubble_number")
  |> should.be_true()

  resolved_schema.properties
  |> has_property_key("air_bubble_distance")
  |> should.be_true()

  resolved_schema.properties
  |> has_property_key("air_bubble_location")
  |> should.be_true()
}

/// Test that multiple conditionals work independently
pub fn multiple_conditionals_independent_test() {
  let assert Ok(schema_json) =
    simplifile.read("examples/file_schema_loader/schemas/basic_leak_signs.json")

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
  |> has_property_key("air_bubble_size")
  |> should.be_true()

  resolved_schema.properties
  |> has_property_key("pneumoperitoneum_thickness")
  |> should.be_true()

  // Should NOT have fields from other conditionals
  resolved_schema.properties
  |> has_property_key("ascites_type")
  |> should.be_false()

  resolved_schema.properties
  |> has_property_key("ileus_diametr")
  |> should.be_false()
}
