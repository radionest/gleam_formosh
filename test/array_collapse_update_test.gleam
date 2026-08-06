import formosh/form/model
import formosh/form/path.{ArraySegment, PropertySegment}
import formosh/form/update
import formosh/form/widget_msg.{ToggleCollapseCompleted, ToggleRowExpanded}
import formosh/schema/parser
import formosh/schema/types
import formosh/schema/ui_parser
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
  let m0 = init()
  let #(m1, _) = update.update(m0, model.array_msg(ToggleRowExpanded(row(1))))
  let #(m2, _) =
    update.update(m1, model.array_msg(ToggleCollapseCompleted(zones)))
  let #(m3, _) =
    update.update(m2, model.array_msg(ToggleCollapseCompleted(zones)))
  m3.array_rows_expanded |> should.equal([])
}

pub fn expanding_one_row_leaves_siblings_test() {
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
  let #(m2, _) = update.update(m1, model.RemoveArrayItemPath(zones, 0))
  m2.array_rows_expanded |> should.equal([row(1)])
}

pub fn removing_expanded_row_drops_its_state_test() {
  let m0 = init()
  let #(m1, _) = update.update(m0, model.array_msg(ToggleRowExpanded(row(1))))
  let #(m2, _) = update.update(m1, model.RemoveArrayItemPath(zones, 1))
  m2.array_rows_expanded |> should.equal([])
}

pub fn moving_row_carries_expansion_test() {
  let m0 = init()
  let #(m1, _) = update.update(m0, model.array_msg(ToggleRowExpanded(row(0))))
  let #(m2, _) = update.update(m1, model.MoveArrayItemPath(zones, 0, 2))
  m2.array_rows_expanded |> should.equal([row(2)])
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
