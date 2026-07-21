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
import gleam/option.{None, Some}
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

// --- Task 11: SelectUnionBranchPath + subtree clearing ---
//
// Spec: openspec/changes/add-anyof-union-support/specs/union-branch-selector/
// spec.md, requirement "Switching branches clears the subtree and
// re-establishes invariants" (3 scenarios) plus requirement "Branch
// selection is model state"'s first scenario.

/// Scenario: Selecting a branch switches the subform. The model records
/// the index for that exact path and the effective property flips to the
/// new branch's type.
pub fn select_union_branch_records_index_and_flips_property_test() {
  let assert Ok(schema) = parser.parse_schema(union_schema)
  let m = model.init(schema)
  let value_path = [path.PropertySegment("value")]

  let #(updated, _effect) =
    update.update(m, model.SelectUnionBranchPath(value_path, 1))

  updated.selected_branches |> should.equal([#(value_path, 1)])
  let assert Ok(prop) = model.find_property_at_path(updated, value_path)
  prop.field_type |> should.equal(Some(types.StringType))
}

/// Scenario: Entered value does not survive a switch. Branch 0 (integer)
/// holds `42`; switching to branch 1 (string) must clear it so it is
/// absent from the model (and, by construction, from a subsequent
/// submission — `path.remove_at_path` drops the key entirely rather than
/// nulling it).
pub fn select_union_branch_clears_entered_value_test() {
  let assert Ok(schema) = parser.parse_schema(union_schema)
  let m = model.init(schema)
  let value_path = [path.PropertySegment("value")]
  let #(with_int, _) =
    update.update(m, model.UpdateFieldPath(value_path, types.IntegerValue(42)))
  path.get_at_path(with_int.values, value_path)
  |> should.equal(Some(types.IntegerValue(42)))

  let #(switched, _) =
    update.update(with_int, model.SelectUnionBranchPath(value_path, 1))

  path.get_at_path(switched.values, value_path) |> should.equal(None)
  let assert types.ObjectValue(fields) = switched.values
  list.key_find(fields, "value") |> should.be_error()
}

const object_or_scalar_union_schema = "{\"type\":\"object\",\"properties\":{\"value\":{\"anyOf\":[{\"type\":\"object\",\"properties\":{\"city\":{\"type\":\"string\",\"minLength\":3}}},{\"type\":\"integer\"}]}}}"

/// Scenario: Object branch leaves no stale keys. Branch 0 is an object with
/// a "city" field; fill it with a value that violates `minLength` (so both
/// an error and a touched entry exist under the nested dot-notation path),
/// then switch to branch 1 (scalar) — none of it should survive.
pub fn select_union_branch_clears_nested_object_state_test() {
  let assert Ok(schema) = parser.parse_schema(object_or_scalar_union_schema)
  let m = model.init(schema)
  let value_path = [path.PropertySegment("value")]
  let city_path = [
    path.PropertySegment("value"),
    path.PropertySegment("city"),
  ]
  let #(filled, _) =
    update.update(m, model.UpdateFieldPath(city_path, types.StringValue("Os")))

  // Sanity: prove the pre-switch state actually has something to clear —
  // otherwise the post-switch assertions below would pass vacuously.
  model.has_errors_at_path(filled, city_path) |> should.be_true()
  model.is_field_touched(filled, city_path) |> should.be_true()

  let #(switched, _) =
    update.update(filled, model.SelectUnionBranchPath(value_path, 1))

  model.has_errors_at_path(switched, city_path) |> should.be_false()
  model.is_field_touched(switched, city_path) |> should.be_false()
  path.get_at_path(switched.values, city_path) |> should.equal(None)
}

const array_or_scalar_union_schema = "{\"type\":\"object\",\"properties\":{\"value\":{\"anyOf\":[{\"type\":\"string\"},{\"type\":\"array\",\"minItems\":2,\"items\":{\"type\":\"string\"}}]}}}"

/// Scenario: Array branch is topped up to minItems. Switching to branch 1
/// (array, `minItems: 2`) must reconcile the array to two rows immediately
/// — not just materialize an empty array.
pub fn select_union_branch_tops_up_array_branch_test() {
  let assert Ok(schema) = parser.parse_schema(array_or_scalar_union_schema)
  let m = model.init(schema)
  let value_path = [path.PropertySegment("value")]

  let #(switched, _effect) =
    update.update(m, model.SelectUnionBranchPath(value_path, 1))

  let assert Some(types.ArrayValue(items)) =
    path.get_at_path(switched.values, value_path)
  list.length(items) |> should.equal(2)
}

/// Scenario (implicit in "clears the subtree and re-establishes
/// invariants"): the union path itself is marked touched immediately after
/// a switch, independent of any prior touched state.
pub fn select_union_branch_marks_union_path_touched_test() {
  let assert Ok(schema) = parser.parse_schema(union_schema)
  let m = model.init(schema)
  let value_path = [path.PropertySegment("value")]

  let #(switched, _effect) =
    update.update(m, model.SelectUnionBranchPath(value_path, 1))

  model.is_field_touched(switched, value_path) |> should.be_true()
}

/// `clear_subtree`'s error-key matching must treat `"."` as the sole
/// descendant boundary (the one join character `path_format.gleam` ever
/// emits between segments — see `path_test.gleam`'s
/// `"lesions.[0].measurements.[1].value"`): a prefix "lesions" must match
/// the nested array-index key "lesions.[0].side" but must NOT match a
/// sibling key that merely shares a string prefix, like "lesionsExtra".
pub fn clear_subtree_error_key_boundary_test() {
  let assert Ok(schema) = parser.parse_schema(union_schema)
  let prefix = [path.PropertySegment("lesions")]
  let base = model.init(schema)
  let seeded =
    model.FormModel(
      ..base,
      errors: dict.from_list([
        #("lesions.[0].side", []),
        #("lesions", []),
        #("lesionsExtra", []),
      ]),
      touched_fields: [
        [path.PropertySegment("lesions"), path.ArraySegment(0)],
        [path.PropertySegment("lesionsExtra")],
      ],
    )

  let cleared = model.clear_subtree(seeded, prefix)

  dict.has_key(cleared.errors, "lesions.[0].side") |> should.be_false()
  dict.has_key(cleared.errors, "lesions") |> should.be_false()
  dict.has_key(cleared.errors, "lesionsExtra") |> should.be_true()
  list.contains(cleared.touched_fields, [
    path.PropertySegment("lesions"),
    path.ArraySegment(0),
  ])
  |> should.be_false()
  list.contains(cleared.touched_fields, [path.PropertySegment("lesionsExtra")])
  |> should.be_true()
}

// --- Task 12: array remove/move reindexes selected_branches ---
//
// Spec: openspec/changes/add-anyof-union-support/specs/union-branch-selector/
// spec.md, requirement "Array operations reindex branch state".

fn row_value_path(index: Int) -> path.FieldPath {
  [
    path.PropertySegment("items"),
    path.ArraySegment(index),
    path.PropertySegment("value"),
  ]
}

// Rows carry a distinct IntegerValue marker (not `ObjectValue([])`
// placeholders) so a reordered array is never structurally equal to the
// original — `MoveArrayItemPath` no-ops (values, touched, and now selected
// branches all left alone) when `new_values == model.values`, exactly like
// `update_test.init_array_model`'s distinct "a"/"b"/"c" tags avoid the same
// guard for `touched_fields`.
fn init_row_union_model(row_count: Int) -> model.FormModel {
  let assert Ok(schema) = parser.parse_schema(row_union_schema)
  let rows =
    list.range(0, row_count - 1)
    |> list.map(fn(i) { types.ObjectValue([#("value", types.IntegerValue(i))]) })
  model.FormModel(
    ..model.init(schema),
    values: types.ObjectValue([#("items", types.ArrayValue(rows))]),
  )
}

/// Scenario: Removing a row shifts later selections. Rows 0 and 1 both hold
/// unions; row 1 has branch 1 (string) selected. Removing row 0 must move
/// the selection to the row-0 path (and drop the stale row-1 entry), while a
/// selection outside the array is untouched — mirrors
/// `form_storage_test.remove_array_item_reindexes_touched_fields_test`.
pub fn remove_array_item_reindexes_selected_branches_test() {
  let unrelated_path = [path.PropertySegment("name")]
  let m =
    model.FormModel(..init_row_union_model(2), selected_branches: [
      #(row_value_path(1), 1),
      #(unrelated_path, 1),
    ])

  let #(after, _effect) =
    update.update(
      m,
      model.RemoveArrayItemPath([path.PropertySegment("items")], 0),
    )

  // Former row 1's selection now lives at row 0, still branch 1.
  list.key_find(after.selected_branches, row_value_path(0))
  |> should.equal(Ok(1))
  // The stale row-1 entry is gone (only one row remains after removal).
  list.key_find(after.selected_branches, row_value_path(1))
  |> should.be_error()
  // A selection outside the affected array is untouched.
  list.key_find(after.selected_branches, unrelated_path)
  |> should.equal(Ok(1))

  // The reindexed selection actually renders branch 1 (string) at row 0.
  let assert Ok(prop) =
    model.find_resolved_property_at_path(after, row_value_path(0))
  prop.field_type |> should.equal(Some(types.StringType))
}

/// Mirror test for move: reordering array rows reindexes branch selections
/// the same way `touched_fields` already does
/// (`update_test.move_array_item_reindexes_touched_test`). Row 0's
/// selection follows the row to its new index 2; a selection outside the
/// array is untouched.
pub fn move_array_item_reindexes_selected_branches_test() {
  let unrelated_path = [path.PropertySegment("name")]
  let m =
    model.FormModel(..init_row_union_model(3), selected_branches: [
      #(row_value_path(0), 1),
      #(unrelated_path, 1),
    ])

  let #(after, _effect) =
    update.update(
      m,
      model.MoveArrayItemPath([path.PropertySegment("items")], 0, 2),
    )

  list.key_find(after.selected_branches, row_value_path(2))
  |> should.equal(Ok(1))
  list.key_find(after.selected_branches, row_value_path(0))
  |> should.be_error()
  list.key_find(after.selected_branches, unrelated_path)
  |> should.equal(Ok(1))

  let assert Ok(prop) =
    model.find_resolved_property_at_path(after, row_value_path(2))
  prop.field_type |> should.equal(Some(types.StringType))
}
