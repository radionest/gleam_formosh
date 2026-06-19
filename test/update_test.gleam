// Tests for formosh/form/update — focused on the validate_field path
// that runs through properties.get on the resolved schema.

import formosh/form/model
import formosh/form/path
import formosh/form/update
import formosh/schema/parser
import formosh/schema/types.{ArrayValue, ObjectValue, StringValue}
import gleam/option.{Some}
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

const array_schema = "{
  \"type\": \"object\",
  \"properties\": {
    \"tags\": {\"type\": \"array\", \"items\": {\"type\": \"string\"}}
  }
}"

fn init_array_model() -> model.FormModel {
  let assert Ok(schema) = parser.parse_schema(array_schema)
  let m = model.init(schema)
  model.FormModel(
    ..m,
    values: ObjectValue([
      #(
        "tags",
        ArrayValue([StringValue("a"), StringValue("b"), StringValue("c")]),
      ),
    ]),
    resolved_schema: schema,
  )
}

pub fn move_array_item_reorders_values_test() {
  let m = init_array_model()
  let #(new_model, _effect) =
    update.update(
      m,
      model.MoveArrayItemPath([path.PropertySegment("tags")], 0, 2),
    )
  path.get_at_path(new_model.values, [
    path.PropertySegment("tags"),
    path.ArraySegment(0),
  ])
  |> should.equal(Some(StringValue("b")))
  path.get_at_path(new_model.values, [
    path.PropertySegment("tags"),
    path.ArraySegment(2),
  ])
  |> should.equal(Some(StringValue("a")))
  new_model.is_dirty |> should.be_true
}

pub fn move_array_item_reindexes_touched_test() {
  let m =
    model.mark_field_touched(init_array_model(), [
      path.PropertySegment("tags"),
      path.ArraySegment(0),
    ])
  let #(new_model, _effect) =
    update.update(
      m,
      model.MoveArrayItemPath([path.PropertySegment("tags")], 0, 2),
    )
  // row 0 moved to row 2 — touched state follows the row.
  model.is_field_touched(new_model, [
    path.PropertySegment("tags"),
    path.ArraySegment(2),
  ])
  |> should.be_true
  model.is_field_touched(new_model, [
    path.PropertySegment("tags"),
    path.ArraySegment(0),
  ])
  |> should.be_false
}

// --- No-op / invalid move edge cases (PR #49 review: sourcery + coderabbit) ---
// move_array_item_at_path is a no-op for out-of-range and same-index moves, but
// the update handler still reindexes every touched path and marks the form
// dirty. These regression tests pin the expected behaviour: a no-op move must
// leave values, touched state, and the dirty flag untouched.

/// Out-of-range target index: values do not move, so touched state must stay
/// on the original row instead of desyncing to a phantom index.
pub fn move_array_item_out_of_range_keeps_touched_test() {
  let m =
    model.mark_field_touched(init_array_model(), [
      path.PropertySegment("tags"),
      path.ArraySegment(0),
    ])
  let #(new_model, _effect) =
    update.update(
      m,
      model.MoveArrayItemPath([path.PropertySegment("tags")], 0, 99),
    )
  path.get_at_path(new_model.values, [
    path.PropertySegment("tags"),
    path.ArraySegment(0),
  ])
  |> should.equal(Some(StringValue("a")))
  model.is_field_touched(new_model, [
    path.PropertySegment("tags"),
    path.ArraySegment(0),
  ])
  |> should.be_true
}

/// A negative target index is also a no-op move; touched state stays put.
pub fn move_array_item_negative_index_keeps_touched_test() {
  let m =
    model.mark_field_touched(init_array_model(), [
      path.PropertySegment("tags"),
      path.ArraySegment(2),
    ])
  let #(new_model, _effect) =
    update.update(
      m,
      model.MoveArrayItemPath([path.PropertySegment("tags")], 2, -1),
    )
  model.is_field_touched(new_model, [
    path.PropertySegment("tags"),
    path.ArraySegment(2),
  ])
  |> should.be_true
}

/// from == to is a no-op; values and touched state are unchanged.
pub fn move_array_item_same_index_keeps_touched_test() {
  let m =
    model.mark_field_touched(init_array_model(), [
      path.PropertySegment("tags"),
      path.ArraySegment(1),
    ])
  let #(new_model, _effect) =
    update.update(
      m,
      model.MoveArrayItemPath([path.PropertySegment("tags")], 1, 1),
    )
  path.get_at_path(new_model.values, [
    path.PropertySegment("tags"),
    path.ArraySegment(1),
  ])
  |> should.equal(Some(StringValue("b")))
  model.is_field_touched(new_model, [
    path.PropertySegment("tags"),
    path.ArraySegment(1),
  ])
  |> should.be_true
}

/// A no-op move must not mark the form dirty — nothing actually changed.
pub fn move_array_item_noop_not_dirty_test() {
  let #(new_model, _effect) =
    update.update(
      init_array_model(),
      model.MoveArrayItemPath([path.PropertySegment("tags")], 0, 99),
    )
  new_model.is_dirty |> should.be_false
}
