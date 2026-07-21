// Tests for FormModel.selected_branches state and the union-aware
// resolved_schema wiring (model.recompute_resolved_schema).
//
// Spec: openspec/changes/add-anyof-union-support/plan.md Task 7.

import formosh/form/defaults
import formosh/form/model
import formosh/form/path
import formosh/form/update
import formosh/schema/parser
import formosh/schema/properties
import formosh/schema/types
import formosh/schema/validator
import gleam/dict
import gleam/list
import gleam/option.{Some}
import gleeunit/should

const union_schema = "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"value\":{\"anyOf\":[{\"type\":\"integer\"},{\"type\":\"string\"}]}}}"

fn init_union_model() -> model.FormModel {
  let assert Ok(schema) = parser.parse_schema(union_schema)
  let m = model.init(schema)
  let resolved = model.recompute_resolved_schema(schema, m.values, [])
  model.FormModel(..m, resolved_schema: resolved)
}

/// Step 1: with no stored selection, a 2-branch union resolves to branch 0
/// (design D8 default) while `any_of` still carries both members so the
/// chooser can render.
pub fn union_defaults_to_branch_zero_test() {
  let m = init_union_model()
  let assert Ok(prop) =
    model.find_property_at_path(m, [path.PropertySegment("value")])
  prop.field_type |> should.equal(Some(types.IntegerType))
  let assert Some(members) = prop.any_of
  list.length(members) |> should.equal(2)
}

/// `selected_branches` starts empty on `init` and is cleared by `reset`,
/// mirroring `touched_fields`.
pub fn selected_branches_empty_on_init_and_reset_test() {
  let assert Ok(schema) = parser.parse_schema(union_schema)
  let m = model.init(schema)
  m.selected_branches |> should.equal([])
  let dirtied =
    model.FormModel(..m, selected_branches: [
      #([path.PropertySegment("value")], 1),
    ])
  model.reset(dirtied).selected_branches |> should.equal([])
}

/// The `UpdateFieldPath` handler in `update.gleam` recomputes
/// `resolved_schema` through `model.recompute_resolved_schema` (not the
/// bare `conditional_resolver.resolve_recursive`), so a union elsewhere in
/// the schema stays materialized after an unrelated field changes.
pub fn update_field_path_resolves_union_through_wrapper_test() {
  let assert Ok(schema) = parser.parse_schema(union_schema)
  let m = model.init(schema)
  let #(updated, _effect) =
    update.update(
      m,
      model.UpdateFieldPath(
        [path.PropertySegment("name")],
        types.StringValue("Alice"),
      ),
    )
  let assert Ok(prop) =
    model.find_property_at_path(updated, [path.PropertySegment("value")])
  prop.field_type |> should.equal(Some(types.IntegerType))
  let assert Some(members) = prop.any_of
  list.length(members) |> should.equal(2)
}

// --- Task 8: per-row effective-property sites ---

const row_union_schema = "{\"type\":\"object\",\"properties\":{\"items\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"value\":{\"anyOf\":[{\"type\":\"integer\"},{\"type\":\"string\",\"maxLength\":3}]}}}}}}"

/// Step 1(a): the validator must enforce the SELECTED branch's constraints
/// inside a row, not branch 0's. Branch 1 (string, maxLength 3) is stored as
/// selected for the row's "value" field; the row value "abcd" (4 chars)
/// violates it. If branch 0 (integer) had been evaluated instead, the error
/// would be an `InvalidType` ("type" rule), never `maxLength`.
pub fn validator_enforces_selected_branch_constraints_in_row_test() {
  let assert Ok(schema) = parser.parse_schema(row_union_schema)
  let assert Some(items_prop) = properties.get(schema.properties, "items")
  let assert Some(item_schema) = items_prop.items
  let value_path = [
    path.PropertySegment("items"),
    path.ArraySegment(0),
    path.PropertySegment("value"),
  ]
  let selected = [#(value_path, 1)]
  let item_values = dict.from_list([#("value", types.StringValue("abcd"))])

  let errors =
    validator.validate_array_item(
      [path.PropertySegment("items")],
      0,
      item_schema,
      item_values,
      selected,
    )

  let value_errors = list.filter(errors, fn(e) { e.field == value_path })
  list.any(value_errors, fn(e) { e.rule == "maxLength" }) |> should.be_true()
  // Branch 0's constraints (integer) must NOT be evaluated against the
  // string value — no type-mismatch error should surface.
  list.any(value_errors, fn(e) { e.rule == "type" }) |> should.be_false()
}

const array_branch_schema = "{\"type\":\"object\",\"properties\":{\"rows\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"value\":{\"anyOf\":[{\"type\":\"string\"},{\"type\":\"array\",\"minItems\":2,\"items\":{\"type\":\"string\"}}]}}}}}}"

/// Step 1(b): switching context — an array-typed branch (`minItems: 2`)
/// materialized inside a row must get topped up by `ensure_min_items`, same
/// as any statically-declared array. Row 0 has no "value" yet; branch 1
/// (array, minItems 2) is stored as selected for it.
pub fn ensure_min_items_tops_up_array_branch_inside_row_test() {
  let assert Ok(schema) = parser.parse_schema(array_branch_schema)
  let value_path = [
    path.PropertySegment("rows"),
    path.ArraySegment(0),
    path.PropertySegment("value"),
  ]
  let selected = [#(value_path, 1)]
  let values =
    types.ObjectValue([#("rows", types.ArrayValue([types.ObjectValue([])]))])

  let result = defaults.ensure_min_items(schema.properties, values, selected)

  let assert Some(types.ArrayValue(items)) =
    path.get_at_path(result, value_path)
  list.length(items) |> should.equal(2)
}

/// Step 1(c): `find_resolved_property_at_path` must resolve a union nested
/// inside an array row to the SELECTED branch, not the value-inferred one.
/// The row value is an `IntegerValue` (would infer branch 0 by itself), but
/// branch 1 (string) is stored as selected for that exact path — the stored
/// selection must win, proving the row-path resolve reaches the union walk.
pub fn find_resolved_property_at_path_through_union_in_row_test() {
  let assert Ok(schema) = parser.parse_schema(row_union_schema)
  let value_path = [
    path.PropertySegment("items"),
    path.ArraySegment(0),
    path.PropertySegment("value"),
  ]
  let selected = [#(value_path, 1)]
  let values =
    types.ObjectValue([
      #(
        "items",
        types.ArrayValue([
          types.ObjectValue([#("value", types.IntegerValue(42))]),
        ]),
      ),
    ])
  let m =
    model.FormModel(
      ..model.init(schema),
      values: values,
      resolved_schema: model.recompute_resolved_schema(schema, values, selected),
      selected_branches: selected,
    )

  let assert Ok(prop) = model.find_resolved_property_at_path(m, value_path)
  prop.field_type |> should.equal(Some(types.StringType))
}
