// Unit tests for the layout walker, independent of schema and FormMsg.
// `arrange` is generic, so a leaf renderer here is just "a span naming the
// leaf" — which keeps these tests about structure, not about field widgets.

import formosh/fields/layout
import formosh/schema/ui_schema.{GroupNode, LeafNode, RowNode}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit/should
import lustre/attribute
import lustre/element
import lustre/element/html

fn entries(names: List(String)) -> List(#(String, Nil)) {
  list.map(names, fn(n) { #(n, Nil) })
}

/// Renders a leaf only when it is in `present`, mimicking a conditional
/// field that is currently absent from the resolved schema.
fn leaf_renderer(
  present: List(String),
) -> fn(String) -> Option(element.Element(Nil)) {
  fn(name) {
    case list.contains(present, name) {
      True -> Some(html.span([attribute.attribute("data-n", name)], []))
      False -> None
    }
  }
}

fn render(
  nodes: Option(List(ui_schema.LayoutNode)),
  declared: List(String),
  present: List(String),
) -> String {
  layout.arrange(nodes, entries(declared), leaf_renderer(present))
  |> list.map(element.to_string)
  |> string.join("")
}

pub fn no_layout_renders_entries_in_order_test() {
  let html = render(None, ["a", "b"], ["a", "b"])
  html |> string.contains("data-n=\"a\"") |> should.be_true
  html |> string.contains("data-n=\"b\"") |> should.be_true
}

pub fn row_wraps_children_in_a_row_part_test() {
  let nodes = Some([RowNode([LeafNode("year"), LeafNode("month")])])
  let html = render(nodes, ["year", "month"], ["year", "month"])
  html |> string.contains("part=\"row\"") |> should.be_true
  html |> string.contains("display:grid") |> should.be_true
}

pub fn group_emits_label_and_body_test() {
  let nodes = Some([GroupNode(Some("Газ"), [LeafNode("a")])])
  let html = render(nodes, ["a"], ["a"])
  html |> string.contains("part=\"group\"") |> should.be_true
  html |> string.contains("part=\"group-label\"") |> should.be_true
  html |> string.contains("Газ") |> should.be_true
  html |> string.contains("part=\"group-body\"") |> should.be_true
}

pub fn group_without_label_emits_no_label_test() {
  let nodes = Some([GroupNode(None, [LeafNode("a")])])
  let html = render(nodes, ["a"], ["a"])
  html |> string.contains("part=\"group-label\"") |> should.be_false
  html |> string.contains("part=\"group-body\"") |> should.be_true
}

pub fn absent_leaf_is_skipped_test() {
  let nodes = Some([RowNode([LeafNode("a"), LeafNode("gone")])])
  let html = render(nodes, ["a"], ["a"])
  html |> string.contains("data-n=\"a\"") |> should.be_true
  html |> string.contains("data-n=\"gone\"") |> should.be_false
  html |> string.contains("part=\"row\"") |> should.be_true
}

pub fn node_with_no_surviving_children_renders_nothing_test() {
  let nodes = Some([GroupNode(Some("Пусто"), [LeafNode("gone")])])
  let html = render(nodes, [], [])
  html |> string.contains("part=\"group\"") |> should.be_false
  html |> string.contains("Пусто") |> should.be_false
}

pub fn unplaced_entries_are_appended_test() {
  let nodes = Some([LeafNode("b")])
  let html = render(nodes, ["a", "b", "c"], ["a", "b", "c"])
  let assert Ok(#(before, after)) = string.split_once(html, "data-n=\"b\"")
  before |> string.contains("data-n=\"a\"") |> should.be_false
  after |> string.contains("data-n=\"a\"") |> should.be_true
  after |> string.contains("data-n=\"c\"") |> should.be_true
}

pub fn leftovers_follow_caller_supplied_order_test() {
  // Callers pass entries already ordered by properties.apply_order, so the
  // leftover order is whatever the caller handed in.
  let nodes = Some([LeafNode("b")])
  let html = render(nodes, ["c", "a", "b"], ["a", "b", "c"])
  let assert Ok(#(_, after)) = string.split_once(html, "data-n=\"b\"")
  let assert Ok(#(first, _)) = string.split_once(after, "data-n=\"a\"")
  first |> string.contains("data-n=\"c\"") |> should.be_true
}

pub fn nested_nodes_render_in_place_test() {
  let nodes =
    Some([
      GroupNode(None, [LeafNode("a"), RowNode([LeafNode("b"), LeafNode("c")])]),
    ])
  let html = render(nodes, ["a", "b", "c"], ["a", "b", "c"])
  html |> string.contains("part=\"group-body\"") |> should.be_true
  html |> string.contains("part=\"row\"") |> should.be_true
}
