// Tests for formosh/form/update — focused on the validate_field path
// that runs through properties.get on the resolved schema.

import formosh/form/model
import formosh/form/path
import formosh/form/update
import formosh/schema/parser
import formosh/schema/types.{ObjectValue, StringValue}
import gleeunit/should

const simple_schema = "{
  \"type\": \"object\",
  \"required\": [\"name\"],
  \"properties\": {
    \"name\": {\"type\": \"string\", \"minLength\": 2},
    \"nickname\": {\"type\": \"string\"}
  }
}"

fn init_model(values: List(#(String, types.Value))) -> model.FormModel {
  let assert Ok(schema) = parser.parse_schema(simple_schema)
  let m = model.init(schema)
  model.FormModel(..m, values: ObjectValue(values), resolved_schema: schema)
}

/// validate_field (via validate_all_fields) reaches the Some branch of
/// properties.get when the field is in resolved_schema.properties and
/// the value is missing — the required error must surface.
pub fn validate_all_fields_required_missing_test() {
  let m = init_model([])
  let validated = update.validate_all_fields(m)
  model.has_errors_at_path(validated, path.from_field_name("name"))
  |> should.be_true
}

/// validate_field clears errors when the value satisfies the schema —
/// exercises the happy path through properties.get + validator.
pub fn validate_all_fields_valid_value_clears_errors_test() {
  let m = init_model([#("name", StringValue("Alice"))])
  let validated = update.validate_all_fields(m)
  model.has_errors_at_path(validated, path.from_field_name("name"))
  |> should.be_false
}

/// Non-required field without a value is not flagged — confirms
/// validate_field reaches properties.get and skips when value is absent
/// and the field is optional.
pub fn validate_all_fields_optional_missing_test() {
  let m = init_model([])
  let validated = update.validate_all_fields(m)
  model.has_errors_at_path(validated, path.from_field_name("nickname"))
  |> should.be_false
}
