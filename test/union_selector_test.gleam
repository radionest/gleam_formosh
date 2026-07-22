// Tests for FormModel.selected_branches state and the union-aware
// resolved_schema wiring (model.recompute_resolved_schema).
//
// Spec: openspec/changes/add-anyof-union-support/plan.md Task 7.

import formosh/fields/field_common
import formosh/fields/field_dispatcher
import formosh/form/defaults
import formosh/form/json_utils
import formosh/form/model
import formosh/form/path
import formosh/form/update
import formosh/form/view
import formosh/form/visibility
import formosh/schema/parser
import formosh/schema/properties
import formosh/schema/types
import formosh/schema/ui_parser
import formosh/schema/validator
import formosh/validation/error
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import gleam/string
import gleeunit/should
import lustre/element.{type Element}
import lustre/vdom/vattr
import lustre/vdom/vnode

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

/// F1 (PR-gate blocker): `reset` must materialize `resolved_schema`, not
/// just clear `selected_branches`. With a stored branch-1 selection wiped
/// by reset, the union path's resolved property must fall back to branch 0
/// (design D8 default) with `field_type` set and `any_of` still carrying
/// both members — mirrors `union_defaults_to_branch_zero_test`'s
/// assertions, but reached through `model.reset` instead of a bare
/// `recompute_resolved_schema` call.
pub fn reset_materializes_union_in_resolved_schema_test() {
  let assert Ok(schema) = parser.parse_schema(union_schema)
  let m = model.init(schema)
  let dirtied =
    model.FormModel(..m, selected_branches: [
      #([path.PropertySegment("value")], 1),
    ])

  let reset_model = model.reset(dirtied)

  let assert Ok(prop) =
    model.find_property_at_path(reset_model, [path.PropertySegment("value")])
  prop.field_type |> should.equal(Some(types.IntegerType))
  let assert Some(members) = prop.any_of
  list.length(members) |> should.equal(2)
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

// --- Task 13 ADDENDUM: array-row value clearing on branch switch ---
//
// T13-MUST (binding, from Task 11's review gate — see
// .superpowers/sdd/progress.md OPEN ITEMS): `clear_subtree`'s values side
// (`path.remove_at_path`) no-ops when the target path ends in an
// `ArraySegment` — a union that IS an array's item schema directly (no
// object wrapper in between), so the row's own path has no trailing
// `PropertySegment` to drop a key under. Since a row can't be removed
// without reindexing every later sibling (that would corrupt sibling
// selections/errors — the exact thing D9/Task 12 protects), the fix is
// reset-in-place: the row's value is overwritten with the same "empty"
// representation `defaults.new_array_item` gives a freshly added row, not
// deleted.
//
// This test also exercises the spec's "Array rows select independently"
// scenario (row 0 and row 1 resolve to different branches without
// cross-talk) with the same array-of-unions fixture, per the task brief.

const array_of_unions_schema = "{\"type\":\"object\",\"properties\":{\"items\":{\"type\":\"array\",\"items\":{\"anyOf\":[{\"type\":\"integer\"},{\"type\":\"string\"}]}}}}"

fn union_row_path(index: Int) -> path.FieldPath {
  [path.PropertySegment("items"), path.ArraySegment(index)]
}

pub fn select_union_branch_resets_array_row_in_place_test() {
  let assert Ok(schema) = parser.parse_schema(array_of_unions_schema)
  let values =
    types.ObjectValue([
      #(
        "items",
        types.ArrayValue([
          types.IntegerValue(42),
          types.StringValue("row one"),
        ]),
      ),
    ])
  let m =
    model.FormModel(..model.init(schema), values: values, selected_branches: [
      #(union_row_path(1), 1),
    ])

  let #(switched, _effect) =
    update.update(m, model.SelectUnionBranchPath(union_row_path(0), 1))

  // Row 0: the old integer is gone — reset in place to the same "empty"
  // representation a freshly added row gets, not removed (removal would
  // shift row 1 down to index 0 and corrupt its selection/value).
  path.get_at_path(switched.values, union_row_path(0))
  |> should.equal(Some(types.NullValue))
  let assert Some(types.ArrayValue(items)) =
    path.get_at_path(switched.values, [path.PropertySegment("items")])
  list.length(items) |> should.equal(2)

  // Row 1 (sibling): value AND selection untouched — independence, not just
  // absence of a crash (spec: "Array rows select independently").
  path.get_at_path(switched.values, union_row_path(1))
  |> should.equal(Some(types.StringValue("row one")))
  list.key_find(switched.selected_branches, union_row_path(1))
  |> should.equal(Ok(1))
  list.key_find(switched.selected_branches, union_row_path(0))
  |> should.equal(Ok(1))

  // Gone from the submission payload too, not just the raw model tree —
  // same composition the real submit path uses (update.gleam:781,
  // `get_resolved_values |> inject_nullable_nulls |> value_to_json`, per
  // nullable_test.gleam's `submit_payload` helper).
  let payload =
    model.get_resolved_values(switched)
    |> defaults.inject_nullable_nulls(
      switched.resolved_schema.properties,
      _,
      switched.selected_branches,
    )
    |> json_utils.value_to_json
    |> json.to_string
  string.contains(payload, "42") |> should.be_false
  string.contains(payload, "\"row one\"") |> should.be_true
}

// --- Task 13: union_field renderer + dispatcher ---
//
// Spec: openspec/changes/add-anyof-union-support/specs/union-branch-selector/
// spec.md, requirement "Multi-branch unions render a chooser plus the active
// branch" (3 scenarios) and requirement "Branch selection is model state
// addressed by field path"'s first scenario (the second, "Array rows select
// independently," is covered above together with the ADDENDUM, since both
// need the same array-of-unions fixture).

const two_branch_union_schema = "{\"type\":\"object\",\"properties\":{\"value\":{\"anyOf\":[{\"type\":\"integer\"},{\"type\":\"string\"}]}}}"

const six_branch_union_schema = "{\"type\":\"object\",\"properties\":{\"value\":{\"anyOf\":[{\"type\":\"integer\"},{\"type\":\"string\"},{\"type\":\"boolean\"},{\"type\":\"number\"},{\"type\":\"object\",\"properties\":{\"a\":{\"type\":\"string\"}}},{\"type\":\"array\",\"items\":{\"type\":\"string\"}}]}}}"

const labeled_union_schema = "{\"type\":\"object\",\"properties\":{\"value\":{\"anyOf\":[{\"type\":\"object\",\"title\":\"Address\",\"properties\":{\"city\":{\"type\":\"string\"}}},{\"type\":\"integer\"},{}]}}}"

const value_path = [path.PropertySegment("value")]

/// A model whose `resolved_schema` is materialized (bare `model.init` does
/// not resolve — task-7-report.md's noted quirk), so the "value" property
/// carries the active branch's own type/properties WITH `any_of` still
/// present, matching what the real dispatcher hands `union_field.render`
/// (Task 6).
fn init_resolved_union_model(
  schema_json: String,
  ui_json: String,
) -> model.FormModel {
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(ui) = ui_parser.parse(ui_json)
  let m = model.init_with_full_config(schema, None, False, dict.new(), ui)
  let resolved =
    model.recompute_resolved_schema(schema, m.values, m.selected_branches)
  model.FormModel(..m, resolved_schema: resolved)
}

fn value_field_ctx(m: model.FormModel) -> field_common.FieldRenderCtx {
  let assert Ok(prop) = model.find_property_at_path(m, value_path)
  field_common.make_field_ctx(
    model: m,
    path: value_path,
    property: prop,
    is_required: False,
    is_disabled: False,
    is_readonly: False,
  )
}

fn render_value_field(m: model.FormModel) -> String {
  field_dispatcher.render_field_at_path(value_field_ctx(m), m)
  |> element.to_string
}

/// Scenario: Default branch renders first member. No stored selection, no
/// value -> branch 0 (integer) is active: a radio chooser (2 branches, both
/// falling back to their capitalised type name since neither has a title)
/// plus an integer input beneath.
pub fn union_default_branch_renders_radio_and_integer_input_test() {
  let html =
    render_value_field(init_resolved_union_model(two_branch_union_schema, "{}"))

  // The `union` wrapper part (distinct from `union-radio`/`union-select`
  // on the nested chooser control — the trailing quote makes the substring
  // check exact, not a prefix match against those).
  string.contains(html, "part=\"union\"") |> should.be_true
  string.contains(html, "part=\"union-radio\"") |> should.be_true
  string.contains(html, "Integer") |> should.be_true
  string.contains(html, "String") |> should.be_true
  string.split(html, "type=\"radio\"") |> list.length |> should.equal(3)
  // Branch 0 (integer) is active by default -> its input renders beneath.
  string.contains(html, "type=\"number\"") |> should.be_true
}

/// Scenario: Widget heuristic. >5 branches -> select, not radio.
pub fn union_six_branches_renders_select_test() {
  let html =
    render_value_field(init_resolved_union_model(six_branch_union_schema, "{}"))

  string.contains(html, "part=\"union-select\"") |> should.be_true
  string.contains(html, "part=\"union-radio\"") |> should.be_false
}

/// Scenario: Widget heuristic override. `ui:widget: "select"` forces a
/// select even though the 2-branch count would default to radio.
pub fn union_widget_select_override_forces_select_test() {
  let html =
    render_value_field(init_resolved_union_model(
      two_branch_union_schema,
      "{\"value\": {\"ui:widget\": \"select\"}}",
    ))

  string.contains(html, "part=\"union-select\"") |> should.be_true
  string.contains(html, "part=\"union-radio\"") |> should.be_false
}

/// Scenario: Branch labels fall back in order — member `title` ("Address")
/// wins; a bare `{"type":"integer"}` falls back to the capitalised type
/// name ("Integer"); a member with neither gets "Option N" (1-based, so the
/// third/last member here is "Option 3").
pub fn union_branch_labels_fall_back_in_order_test() {
  let html =
    render_value_field(init_resolved_union_model(labeled_union_schema, "{}"))

  string.contains(html, "Address") |> should.be_true
  string.contains(html, "Integer") |> should.be_true
  string.contains(html, "Option 3") |> should.be_true
}

// --- Dispatch-message assertion ------------------------------------------
//
// `element.to_string` renders to a plain HTML string, which cannot carry a
// Gleam closure — so "the chooser dispatches the right message" can't be
// read off the string. Lustre's `Attribute`/`Element` are plain
// (non-opaque) records (`lustre/vdom/vattr.Event.handler` is a
// `Decoder(Handler(msg))`, runnable directly against a hand-built
// `Dynamic`), so the technique is: walk the rendered tree, find the
// control's named event listener, decode a synthetic DOM event with it, and
// assert on the resulting message. No existing test in this suite does
// this yet (`dispatcher_render_test.gleam` only asserts suppression via
// plain string checks) — verified by search before writing this.

/// Depth-first `#(tag, attributes)` for every tag node in a rendered tree.
/// `Fragment` children are inlined (not a tag itself); `Text` /
/// `UnsafeInnerHtml` carry no children worth descending into.
fn tag_attrs(
  el: Element(model.FormMsg),
) -> List(#(String, List(vattr.Attribute(model.FormMsg)))) {
  case el {
    vnode.Element(tag: t, attributes: attrs, children: kids, ..) -> [
      #(t, attrs),
      ..list.flatten(list.map(kids, tag_attrs))
    ]
    vnode.Fragment(children: kids, ..) ->
      list.flatten(list.map(kids, tag_attrs))
    vnode.Text(..) | vnode.UnsafeInnerHtml(..) -> []
  }
}

fn has_value_attr(
  attrs: List(vattr.Attribute(model.FormMsg)),
  value: String,
) -> Bool {
  list.any(attrs, fn(a) {
    case a {
      vattr.Attribute(name: "value", value: v, ..) -> v == value
      _ -> False
    }
  })
}

fn event_handler(
  attrs: List(vattr.Attribute(model.FormMsg)),
  event_name: String,
) -> Result(decode.Decoder(vattr.Handler(model.FormMsg)), Nil) {
  attrs
  |> list.filter_map(fn(a) {
    case a {
      vattr.Event(name: n, handler: h, ..) ->
        case n == event_name {
          True -> Ok(h)
          False -> Error(Nil)
        }
      _ -> Error(Nil)
    }
  })
  |> list.first
}

/// Find the `event_name` listener on the first `tag` node in the rendered
/// tree — matched additionally by a `value="..."` attribute when `value` is
/// `Some` (disambiguates between several same-tag nodes, e.g. two radio
/// inputs; a `<select>` has only one node so `None` skips the filter).
fn find_event_handler(
  el: Element(model.FormMsg),
  tag: String,
  value: option.Option(String),
  event_name: String,
) -> Result(decode.Decoder(vattr.Handler(model.FormMsg)), Nil) {
  tag_attrs(el)
  |> list.filter_map(fn(pair) {
    let #(t, attrs) = pair
    let value_matches = case value {
      Some(v) -> has_value_attr(attrs, v)
      None -> True
    }
    case t == tag && value_matches {
      True -> event_handler(attrs, event_name)
      False -> Error(Nil)
    }
  })
  |> list.first
}

/// A `Dynamic` shaped like `{target: {value: <value>}}`, matching what
/// `lustre/event.on_change`'s decoder (`subfield(["target", "value"], ...)`)
/// expects from a real DOM change event.
fn change_event_dynamic(value: String) -> dynamic.Dynamic {
  dynamic.properties([
    #(
      dynamic.string("target"),
      dynamic.properties([#(dynamic.string("value"), dynamic.string(value))]),
    ),
  ])
}

/// Scenario: Selecting a branch switches the subform — chooser side. A
/// click on the branch-1 radio dispatches `SelectUnionBranchPath` for the
/// union's own path with index 1 (`on_click` ignores the event payload
/// entirely, so any `Dynamic` decodes the same fixed message — mirrors
/// `string_field.render_radio_group`'s per-option `event.on_click`).
pub fn union_radio_click_dispatches_select_branch_test() {
  let m = init_resolved_union_model(two_branch_union_schema, "{}")
  let rendered = field_dispatcher.render_field_at_path(value_field_ctx(m), m)

  let assert Ok(handler) =
    find_event_handler(rendered, "input", Some("1"), "click")
  let assert Ok(vattr.Handler(message:, ..)) =
    decode.run(dynamic.properties([]), handler)

  message |> should.equal(model.SelectUnionBranchPath(value_path, 1))
}

/// Scenario: Selecting a branch switches the subform — select variant. A
/// `change` event carrying `target.value = "1"` dispatches
/// `SelectUnionBranchPath` with the parsed index (mirrors
/// `string_field.render_select`'s `event.on_change`, but parses the value
/// back to an `Int` since the option's value is the branch index).
pub fn union_select_change_dispatches_select_branch_test() {
  let m =
    init_resolved_union_model(
      two_branch_union_schema,
      "{\"value\": {\"ui:widget\": \"select\"}}",
    )
  let rendered = field_dispatcher.render_field_at_path(value_field_ctx(m), m)

  let assert Ok(handler) =
    find_event_handler(rendered, "select", None, "change")
  let assert Ok(vattr.Handler(message:, ..)) =
    decode.run(change_event_dynamic("1"), handler)

  message |> should.equal(model.SelectUnionBranchPath(value_path, 1))
}

/// Regression guard: the standard error/touched wrapper
/// (`wrap_with_errors`, applied by `render_visible` around whatever
/// `render_widget` returns) must apply to a union field EXACTLY ONCE, like
/// every other widget type — not once from the dispatcher's outer call at
/// the union's path and a second time from the subform re-entering the
/// same wrapping layer at the same path. `render_child`'s callback
/// identity is what makes this hold: `union_field.render` must be handed a
/// widget-dispatch function that does NOT itself apply `render_visible`'s
/// wrapping, since the subform renders at the SAME `ctx.path` as the union
/// (see `union_field.gleam`'s `child_ctx`) — a wrapping callback there
/// would re-wrap with the identical touched/error state the outer call
/// already wraps with. Presence-only assertions (`string.contains`) cannot
/// catch a duplicate; both checks below assert an EXACT count via
/// `string.split` (N occurrences -> N+1 pieces).
pub fn union_field_still_wrapped_with_errors_when_touched_test() {
  let m = init_resolved_union_model(two_branch_union_schema, "{}")
  let seeded =
    model.add_error_at_path(
      m,
      value_path,
      error.ValidationError(value_path, "bad union value", "custom"),
    )
    |> model.mark_field_touched(value_path)

  let html = render_value_field(seeded)

  string.contains(html, "data-error=\"true\"") |> should.be_true
  // Exactly one occurrence of the error message — not two nested error
  // blocks each repeating it.
  string.split(html, "bad union value") |> list.length |> should.equal(2)
  // Exactly one `part="field"` wrapper for this union (the trailing quote
  // keeps this from also matching `part="field-wrapper"`, a different,
  // legitimately-repeatable part emitted by the branch's own widget).
  string.split(html, "part=\"field\"") |> list.length |> should.equal(2)
}

/// Defensive fallback: a genuine 0- or 1-member `any_of` "cannot exist
/// post-parse" (`composer.normalize_any_of` collapses both shapes into
/// `any_of: None` before a real schema ever reaches the dispatcher — see
/// `any_of_test.gleam`'s `anyof_empty_list_is_none_test` /
/// `anyof_lenient_skips_malformed_member_test`), but the dispatcher's own
/// `Some([_, _, ..])` guard is written to fall through rather than lean on
/// that invariant. Pin it directly against hand-built properties the
/// parser itself would never produce, bypassing `parser.parse_schema`
/// entirely (mirrors `dispatcher_render_test.gleam`'s hand-built-property
/// style).
pub fn dispatcher_falls_through_for_non_union_any_of_shapes_test() {
  let empty_schema =
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
  let m = model.init(empty_schema)
  let single_member =
    types.SchemaProperty(
      ..types.empty_property(),
      field_type: Some(types.IntegerType),
    )

  let render_with = fn(any_of) {
    let prop =
      types.SchemaProperty(
        ..types.empty_property(),
        field_type: Some(types.StringType),
        any_of: any_of,
      )
    let ctx =
      field_common.make_field_ctx(
        model: m,
        path: [path.PropertySegment("name")],
        property: prop,
        is_required: False,
        is_disabled: False,
        is_readonly: False,
      )
    field_dispatcher.render_field_at_path(ctx, m) |> element.to_string
  }

  // `Some([])`: falls through to the string widget, not the union chooser.
  let empty_html = render_with(Some([]))
  string.contains(empty_html, "part=\"union\"") |> should.be_false
  string.contains(empty_html, "part=\"input\"") |> should.be_true

  // `Some([single_member])`: same fallback.
  let one_html = render_with(Some([single_member]))
  string.contains(one_html, "part=\"union\"") |> should.be_false
  string.contains(one_html, "part=\"input\"") |> should.be_true
}

// --- Task 14: readonly summary + visibility descent for union branches ---
//
// Spec: openspec/changes/add-anyof-union-support/specs/union-branch-selector/
// spec.md, requirement "All schema walkers follow the active branch" —
// scenarios "Readonly summary shows the active branch" and "Hidden-field
// suppression descends the active branch". Both `readonly_field.gleam`'s
// top-level property walk and `visibility.gleam`'s `invisible_paths` consume
// `model.resolved_schema`, not the raw `model.schema` — and
// `union_resolver.resolve_form_schema` (wired into every
// `recompute_resolved_schema` call) already materializes every non-array
// union node recursively before either walker ever sees it. All three tests
// below passed on the first run with zero production changes (see
// task-14-report.md for the RED/GREEN account) — they are regression pins,
// not bug fixes.

/// Scenario: Readonly summary shows the active branch (scalar case). No
/// stored selection; the string value infers branch 1 (string) active per
/// "Branch inference from incoming values" — the summary must show branch
/// 1's value.
pub fn readonly_summary_shows_active_scalar_branch_test() {
  let assert Ok(schema) = parser.parse_schema(two_branch_union_schema)
  let values = types.ObjectValue([#("value", types.StringValue("hello"))])
  let m =
    model.FormModel(
      ..model.init(schema),
      values: values,
      resolved_schema: model.recompute_resolved_schema(schema, values, []),
      read_only: True,
    )

  let html = view.view(m) |> element.to_string

  string.contains(html, "hello") |> should.be_true
  string.contains(html, "part=\"readonly-value\"") |> should.be_true
  // Exactly one occurrence — regression guard against the summary
  // double-rendering the active branch's content.
  string.split(html, "hello") |> list.length |> should.equal(2)
}

/// Scenario: Readonly summary shows the active branch (object case). The
/// branch chooser has no readonly analogue, so an object-typed active
/// branch must render as ONE group carrying the branch's own fields, not a
/// duplicated or chooser-shaped wrapper. Branch 0 (object, declares "city")
/// is inferred active by key overlap — reuses `object_or_scalar_union_schema`
/// from the Task 11 section above.
pub fn readonly_summary_shows_active_object_branch_test() {
  let assert Ok(schema) = parser.parse_schema(object_or_scalar_union_schema)
  let values =
    types.ObjectValue([
      #("value", types.ObjectValue([#("city", types.StringValue("Berlin"))])),
    ])
  let m =
    model.FormModel(
      ..model.init(schema),
      values: values,
      resolved_schema: model.recompute_resolved_schema(schema, values, []),
      read_only: True,
    )

  let html = view.view(m) |> element.to_string

  string.contains(html, "Berlin") |> should.be_true
  string.contains(html, "part=\"readonly-group\"") |> should.be_true
  // Exactly one occurrence — a mis-walk that rendered both branches (or the
  // same branch twice) would repeat the city value.
  string.split(html, "Berlin") |> list.length |> should.equal(2)
}

const hidden_in_branch_schema = "{\"type\":\"object\",\"properties\":{\"value\":{\"anyOf\":[{\"type\":\"object\",\"properties\":{\"secret\":{\"type\":\"string\"}}},{\"type\":\"object\",\"properties\":{\"other\":{\"type\":\"string\"}}}]}}}"

/// Scenario: Hidden-field suppression descends the active branch. Branch 0
/// (declares "secret") is inferred active by key overlap; its "secret"
/// field is marked `ui:widget: "hidden"` and must land in `invisible_paths`
/// exactly like a non-union hidden field. Branch 1's "other" field exists
/// only in the inactive branch — it is absent from the materialized
/// `resolved_schema` entirely (not merely unsuppressed), so it must NOT
/// appear in the result either.
pub fn hidden_field_inside_active_union_branch_is_suppressed_test() {
  let assert Ok(schema) = parser.parse_schema(hidden_in_branch_schema)
  let assert Ok(ui) =
    ui_parser.parse("{\"value\":{\"secret\":{\"ui:widget\":\"hidden\"}}}")
  let values =
    types.ObjectValue([
      #("value", types.ObjectValue([#("secret", types.StringValue("x"))])),
    ])
  let resolved = model.recompute_resolved_schema(schema, values, [])

  let result = visibility.invisible_paths(resolved, ui, values, False)

  set.contains(result, "value.secret") |> should.be_true
  // Negative assertion: a field that exists only in the inactive branch
  // must not appear, hidden-marked or not.
  set.contains(result, "value.other") |> should.be_false
  result |> should.equal(set.from_list(["value.secret"]))
}
