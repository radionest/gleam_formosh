import formosh/fields/array_collapse
import formosh/form/model
import formosh/form/path.{ArraySegment, PropertySegment}
import formosh/form/update
import formosh/form/widget_msg.{ToggleCollapseCompleted, ToggleRowExpanded}
import formosh/schema/parser
import formosh/schema/types
import formosh/schema/ui_parser
import formosh/schema/ui_schema
import gleam/dict
import gleam/list
import gleam/option.{None}
import gleeunit/should

const schema_json = "{\"type\":\"object\",\"properties\":{\"zones\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"required\":[\"state\"],\"properties\":{\"label\":{\"type\":\"string\"},\"state\":{\"type\":\"string\"}}}}}}"

const ui_json = "{\"zones\":{\"ui:options\":{\"collapseCompleted\":true,\"summaryFields\":[\"label\",\"state\"]}}}"

const zones = [PropertySegment("zones")]

fn row(index: Int) {
  [PropertySegment("zones"), ArraySegment(index)]
}

// A path scoped under a row, e.g. a nested array's own collapse toggle.
// Handlers are path-agnostic, so this need not exist in the schema — it only
// has to reindex the same way a real nested collapse-off entry would.
fn nested_path(index: Int) {
  list.append(row(index), [PropertySegment("nested")])
}

fn init() -> model.FormModel {
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(ui) = ui_parser.parse(ui_json)
  let m = model.init_with_full_config(schema, None, False, dict.new(), ui)
  model.FormModel(
    ..m,
    values: types.ObjectValue([
      #(
        "zones",
        types.ArrayValue([
          types.ObjectValue([#("label", types.StringValue("a"))]),
          types.ObjectValue([#("label", types.StringValue("b"))]),
          types.ObjectValue([#("label", types.StringValue("c"))]),
        ]),
      ),
    ]),
  )
}

pub fn collapse_state_starts_empty_test() {
  let m = init()
  m.array_collapse_off |> should.equal([])
  m.array_rows_expanded |> should.equal([])
}

pub fn toggle_collapse_off_then_on_test() {
  let m0 = init()
  let #(m1, _) =
    update.update(m0, model.array_msg(ToggleCollapseCompleted(zones)))
  m1.array_collapse_off |> should.equal([zones])
  let #(m2, _) =
    update.update(m1, model.array_msg(ToggleCollapseCompleted(zones)))
  m2.array_collapse_off |> should.equal([])
}

pub fn recollapsing_clears_row_expansions_test() {
  // A row expanded under a DIFFERENT array must survive re-collapsing
  // `zones` — proves the clear is scoped by path prefix, not unconditional.
  let other_row = [PropertySegment("other"), ArraySegment(0)]
  let m0 = init()
  let #(m1, _) = update.update(m0, model.array_msg(ToggleRowExpanded(row(1))))
  let #(m2, _) =
    update.update(m1, model.array_msg(ToggleRowExpanded(other_row)))
  let #(m3, _) =
    update.update(m2, model.array_msg(ToggleCollapseCompleted(zones)))
  let #(m4, _) =
    update.update(m3, model.array_msg(ToggleCollapseCompleted(zones)))
  m4.array_rows_expanded |> should.equal([other_row])
}

pub fn expanding_one_row_leaves_siblings_test() {
  // Expand two DIFFERENT rows and require both survive — an implementation
  // that replaces the list on each expand (`[row_path]` instead of
  // `[row_path, ..model.array_rows_expanded]`) would pass a same-row
  // toggle-on/toggle-off test but fails this one.
  let m0 = init()
  let #(m1, _) = update.update(m0, model.array_msg(ToggleRowExpanded(row(0))))
  let #(m2, _) = update.update(m1, model.array_msg(ToggleRowExpanded(row(2))))
  m2.array_rows_expanded |> list.contains(row(0)) |> should.be_true
  m2.array_rows_expanded |> list.contains(row(2)) |> should.be_true
}

pub fn toggling_row_expanded_twice_collapses_it_test() {
  let m0 = init()
  let #(m1, _) = update.update(m0, model.array_msg(ToggleRowExpanded(row(1))))
  m1.array_rows_expanded |> should.equal([row(1)])
  let #(m2, _) = update.update(m1, model.array_msg(ToggleRowExpanded(row(1))))
  m2.array_rows_expanded |> should.equal([])
}

pub fn two_arrays_toggle_independently_test() {
  // State is keyed by path, so switching one array off must leave any other
  // collapse-enabled array alone.
  let other = [PropertySegment("other")]
  let m0 = init()
  let #(m1, _) =
    update.update(m0, model.array_msg(ToggleCollapseCompleted(zones)))
  m1.array_collapse_off |> list.contains(zones) |> should.be_true
  m1.array_collapse_off |> list.contains(other) |> should.be_false
  let #(m2, _) =
    update.update(m1, model.array_msg(ToggleCollapseCompleted(other)))
  m2.array_collapse_off |> list.contains(zones) |> should.be_true
  m2.array_collapse_off |> list.contains(other) |> should.be_true
}

pub fn toggling_does_not_touch_values_or_dirty_test() {
  let m0 = init()
  let #(m1, _) = update.update(m0, model.array_msg(ToggleRowExpanded(row(0))))
  m1.values |> should.equal(m0.values)
  m1.errors |> should.equal(m0.errors)
  m1.touched_fields |> should.equal(m0.touched_fields)
  m1.is_dirty |> should.equal(m0.is_dirty)
}

pub fn removing_earlier_row_shifts_expansion_test() {
  let m0 = init()
  let #(m1, _) = update.update(m0, model.array_msg(ToggleRowExpanded(row(2))))
  let #(m2, _) =
    update.update(m1, model.array_msg(ToggleCollapseCompleted(zones)))
  let #(m3, _) =
    update.update(m2, model.array_msg(ToggleCollapseCompleted(nested_path(2))))
  let #(m4, _) = update.update(m3, model.RemoveArrayItemPath(zones, 0))
  m4.array_rows_expanded |> should.equal([row(1)])
  // The array's own collapse-off entry (`zones`) is unaffected by which row
  // moved — deliberately pinned because it is correct but non-obvious:
  // `reindex_after_array_removal` falls through to `Some(path)` when
  // nothing remains after stripping the array prefix, so the user's toggle
  // is never silently reset by removing a row.
  m4.array_collapse_off |> list.contains(zones) |> should.be_true
  // A collapse-off entry scoped to a row shifts down with its row, the same
  // way array_rows_expanded entries do.
  m4.array_collapse_off |> list.contains(nested_path(1)) |> should.be_true
  m4.array_collapse_off |> list.contains(nested_path(2)) |> should.be_false
}

pub fn removing_expanded_row_drops_its_state_test() {
  let m0 = init()
  let #(m1, _) = update.update(m0, model.array_msg(ToggleRowExpanded(row(1))))
  let #(m2, _) =
    update.update(m1, model.array_msg(ToggleCollapseCompleted(zones)))
  let #(m3, _) =
    update.update(m2, model.array_msg(ToggleCollapseCompleted(nested_path(1))))
  let #(m4, _) = update.update(m3, model.RemoveArrayItemPath(zones, 1))
  m4.array_rows_expanded |> should.equal([])
  // The array's own entry survives removing one of its rows...
  m4.array_collapse_off |> list.contains(zones) |> should.be_true
  // ...but an entry scoped to the removed row itself is dropped, same as
  // array_rows_expanded.
  m4.array_collapse_off |> list.contains(nested_path(1)) |> should.be_false
}

pub fn moving_row_carries_expansion_test() {
  let m0 = init()
  let #(m1, _) = update.update(m0, model.array_msg(ToggleRowExpanded(row(0))))
  let #(m2, _) =
    update.update(m1, model.array_msg(ToggleCollapseCompleted(zones)))
  let #(m3, _) =
    update.update(m2, model.array_msg(ToggleCollapseCompleted(nested_path(0))))
  let #(m4, _) = update.update(m3, model.MoveArrayItemPath(zones, 0, 2))
  m4.array_rows_expanded |> should.equal([row(2)])
  m4.array_collapse_off |> list.contains(zones) |> should.be_true
  m4.array_collapse_off |> list.contains(nested_path(2)) |> should.be_true
  m4.array_collapse_off |> list.contains(nested_path(0)) |> should.be_false
}

pub fn reset_clears_collapse_state_test() {
  let m0 = init()
  let #(m1, _) = update.update(m0, model.array_msg(ToggleRowExpanded(row(0))))
  let #(m2, _) =
    update.update(m1, model.array_msg(ToggleCollapseCompleted(zones)))
  let m3 = model.reset(m2)
  m3.array_rows_expanded |> should.equal([])
  m3.array_collapse_off |> should.equal([])
  list.length(m3.array_collapse_off) |> should.equal(0)
}

// Fix round 2: AddArrayItemPath must force-expand the row it just created,
// or a row that happens to satisfy `is_completed` the instant it's built
// (see `defaulted_optional_schema_json` below) renders collapsed before the
// user who clicked "Add" ever sees it.

const defaulted_optional_schema_json = "{\"type\":\"object\",\"properties\":{\"zones\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"note\":{\"type\":\"string\",\"default\":\"n/a\"}}}}}}"

const min_items_schema_json = "{\"type\":\"object\",\"properties\":{\"zones\":{\"type\":\"array\",\"minItems\":3,\"items\":{\"type\":\"object\",\"properties\":{\"label\":{\"type\":\"string\"}}}}}}"

fn init_from_schema(schema_json: String) -> model.FormModel {
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let m =
    model.init_with_full_config(
      schema,
      None,
      False,
      dict.new(),
      ui_schema.empty_ui_schema(),
    )
  model.FormModel(
    ..m,
    values: types.ObjectValue([#("zones", types.ArrayValue([]))]),
  )
}

pub fn add_array_item_expands_the_new_row_test() {
  // Regression for the reproduced defect: an item schema with a defaulted
  // optional field and no `required` at all satisfies `is_completed` the
  // moment the row is built, before the user does anything else.
  let m0 = init_from_schema(defaulted_optional_schema_json)
  let #(m1, _) = update.update(m0, model.AddArrayItemPath(zones))
  m1.array_rows_expanded |> should.equal([row(0)])
  let assert option.Some(types.ArrayValue(rows)) =
    model.get_value_at_path(m1, zones)
  let assert Ok(zones_prop) = model.find_resolved_property_at_path(m1, zones)
  let assert option.Some(item_schema) = zones_prop.items
  let incomplete =
    array_collapse.incomplete_rows(
      zones,
      item_schema,
      rows,
      m1.selected_branches,
    )
  let assert Ok(item) = list.first(rows)
  // The predicate itself is untouched — this row genuinely is_completed.
  // It stays visible only because the expansion entry above overrides
  // collapse, which is what proves the fix is view state, not a predicate
  // change.
  array_collapse.is_completed(m1, zones, 0, item, incomplete)
  |> should.be_true
}

pub fn add_array_item_expands_the_new_index_test() {
  // init() already holds 3 rows (indices 0-2); the fresh row must be named
  // by its own new index (3), not 0 and not the previous last index (2).
  let m0 = init()
  let #(m1, _) = update.update(m0, model.AddArrayItemPath(zones))
  m1.array_rows_expanded |> should.equal([row(3)])
}

pub fn add_array_item_leaves_existing_expansion_undisturbed_test() {
  let m0 = init()
  let #(m1, _) = update.update(m0, model.array_msg(ToggleRowExpanded(row(1))))
  let #(m2, _) = update.update(m1, model.AddArrayItemPath(zones))
  m2.array_rows_expanded |> list.contains(row(1)) |> should.be_true
  m2.array_rows_expanded |> list.contains(row(3)) |> should.be_true
  list.length(m2.array_rows_expanded) |> should.equal(2)
}

pub fn bulk_collapse_after_add_discards_fresh_row_expansion_test() {
  let m0 = init()
  let #(m1, _) = update.update(m0, model.AddArrayItemPath(zones))
  m1.array_rows_expanded |> list.contains(row(3)) |> should.be_true
  let #(m2, _) =
    update.update(m1, model.array_msg(ToggleCollapseCompleted(zones)))
  let #(m3, _) =
    update.update(m2, model.array_msg(ToggleCollapseCompleted(zones)))
  m3.array_rows_expanded |> should.equal([])
}

pub fn add_array_item_does_not_force_expand_ensure_min_items_rows_test() {
  // minItems 3 on an initially empty array: the manual add lands one row,
  // then ensure_min_items tops the SAME array up to 3 in the SAME dispatch.
  // Only the user's own row (index 0) may be forced open — the two rows
  // ensure_min_items appends on top (indices 1, 2) are not user-created.
  // This also guards the off-by-one trap named in the task: computing the
  // new index from the post-reconcile array length would misname index 2.
  let m0 = init_from_schema(min_items_schema_json)
  let #(m1, _) = update.update(m0, model.AddArrayItemPath(zones))
  let assert option.Some(types.ArrayValue(rows)) =
    model.get_value_at_path(m1, zones)
  list.length(rows) |> should.equal(3)
  m1.array_rows_expanded |> should.equal([row(0)])
}
