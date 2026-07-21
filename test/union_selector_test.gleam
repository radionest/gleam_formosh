// Tests for FormModel.selected_branches state and the union-aware
// resolved_schema wiring (model.recompute_resolved_schema).
//
// Spec: openspec/changes/add-anyof-union-support/plan.md Task 7.

import formosh/form/model
import formosh/form/path
import formosh/form/update
import formosh/schema/parser
import formosh/schema/types
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
