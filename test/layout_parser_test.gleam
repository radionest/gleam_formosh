// Parser coverage for ui:layout. The rejection cases matter as much as the
// happy path: a dotted leaf must fail loudly now so that relaxing the rule
// later (path addressing) stays non-breaking, and a non-array layout must
// fail because object key order does not survive PostgreSQL JSONB.

import formosh/schema/ui_parser
import formosh/schema/ui_schema.{GroupNode, LeafNode, RowNode}
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

pub fn absent_layout_is_none_test() {
  let assert Ok(ui) = ui_parser.parse("{\"a\":{\"ui:title\":\"A\"}}")
  ui.layout |> should.equal(None)
}

pub fn root_layout_of_leaves_test() {
  let assert Ok(ui) = ui_parser.parse("{\"ui:layout\":[\"a\",\"b\"]}")
  ui.layout |> should.equal(Some([LeafNode("a"), LeafNode("b")]))
}

pub fn row_node_test() {
  let json =
    "{\"ui:layout\":[{\"type\":\"Row\",\"elements\":[\"year\",\"month\"]}]}"
  let assert Ok(ui) = ui_parser.parse(json)
  ui.layout
  |> should.equal(Some([RowNode([LeafNode("year"), LeafNode("month")])]))
}

pub fn group_node_with_label_test() {
  let json =
    "{\"ui:layout\":[{\"type\":\"Group\",\"label\":\"Газ\",\"elements\":[\"a\"]}]}"
  let assert Ok(ui) = ui_parser.parse(json)
  ui.layout
  |> should.equal(Some([GroupNode(Some("Газ"), [LeafNode("a")])]))
}

pub fn group_node_without_label_test() {
  let json = "{\"ui:layout\":[{\"type\":\"Group\",\"elements\":[\"a\"]}]}"
  let assert Ok(ui) = ui_parser.parse(json)
  ui.layout |> should.equal(Some([GroupNode(None, [LeafNode("a")])]))
}

pub fn nested_row_inside_group_test() {
  let json =
    "{\"ui:layout\":[{\"type\":\"Group\",\"elements\":[\"a\",{\"type\":\"Row\",\"elements\":[\"b\",\"c\"]}]}]}"
  let assert Ok(ui) = ui_parser.parse(json)
  ui.layout
  |> should.equal(
    Some([
      GroupNode(None, [LeafNode("a"), RowNode([LeafNode("b"), LeafNode("c")])]),
    ]),
  )
}

pub fn nested_group_inside_group_test() {
  let json =
    "{\"ui:layout\":[{\"type\":\"Group\",\"label\":\"Outer\",\"elements\":[\"a\",{\"type\":\"Group\",\"label\":\"Inner\",\"elements\":[\"b\"]}]}]}"
  let assert Ok(ui) = ui_parser.parse(json)
  ui.layout
  |> should.equal(
    Some([
      GroupNode(Some("Outer"), [
        LeafNode("a"),
        GroupNode(Some("Inner"), [LeafNode("b")]),
      ]),
    ]),
  )
}

pub fn nested_row_inside_row_test() {
  let json =
    "{\"ui:layout\":[{\"type\":\"Row\",\"elements\":[\"a\",{\"type\":\"Row\",\"elements\":[\"b\",\"c\"]}]}]}"
  let assert Ok(ui) = ui_parser.parse(json)
  ui.layout
  |> should.equal(
    Some([RowNode([LeafNode("a"), RowNode([LeafNode("b"), LeafNode("c")])])]),
  )
}

pub fn layout_on_nested_property_test() {
  let json =
    "{\"start\":{\"ui:layout\":[{\"type\":\"Row\",\"elements\":[\"year\"]}]}}"
  let assert Ok(ui) = ui_parser.parse(json)
  let assert Ok(start) = list.key_find(ui.properties, "start")
  start.layout |> should.equal(Some([RowNode([LeafNode("year")])]))
}

pub fn layout_on_items_template_test() {
  let json = "{\"events\":{\"items\":{\"ui:layout\":[\"type\"]}}}"
  let assert Ok(ui) = ui_parser.parse(json)
  let assert Ok(events) = list.key_find(ui.properties, "events")
  let assert Some(items) = events.items
  items.layout |> should.equal(Some([LeafNode("type")]))
}

pub fn dotted_leaf_is_rejected_test() {
  ui_parser.parse("{\"ui:layout\":[\"address.city\"]}")
  |> should.be_error
}

pub fn non_array_layout_is_rejected_test() {
  ui_parser.parse("{\"ui:layout\":{\"Row\":[\"a\"]}}")
  |> should.be_error
}

pub fn non_array_elements_is_rejected_test() {
  ui_parser.parse("{\"ui:layout\":[{\"type\":\"Row\",\"elements\":\"a\"}]}")
  |> should.be_error
}

pub fn missing_elements_is_rejected_test() {
  ui_parser.parse("{\"ui:layout\":[{\"type\":\"Row\"}]}")
  |> should.be_error
}

pub fn unknown_node_type_is_rejected_test() {
  ui_parser.parse("{\"ui:layout\":[{\"type\":\"Tabs\",\"elements\":[\"a\"]}]}")
  |> should.be_error
}

pub fn layout_key_is_not_parsed_as_a_child_test() {
  let assert Ok(ui) = ui_parser.parse("{\"ui:layout\":[\"a\"]}")
  list.key_find(ui.properties, "ui:layout") |> should.be_error
}
