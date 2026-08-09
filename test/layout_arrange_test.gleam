// Unit tests for the layout walker, independent of schema and FormMsg.
// `arrange` is generic, so a leaf renderer here is just "a span naming the
// leaf" — which keeps these tests about structure, not about field widgets.

import dom_containment
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
  let assert Ok(#(before, _)) = string.split_once(html, "data-n=\"b\"")
  before |> string.contains("data-n=\"a\"") |> should.be_true
}

pub fn row_wraps_children_in_a_row_part_test() {
  let nodes = Some([RowNode([LeafNode("year"), LeafNode("month")])])
  let html = render(nodes, ["year", "month"], ["year", "month"])
  let assert Ok(row) = dom_containment.slice_element(html, "part=\"row\"")
  row
  |> string.contains(
    "display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,12rem),1fr));gap:var(--formosh-row-gap,1rem)",
  )
  |> should.be_true
  row |> string.contains("data-n=\"year\"") |> should.be_true
  row |> string.contains("data-n=\"month\"") |> should.be_true
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
  let nodes =
    Some([
      GroupNode(Some("Пусто"), [LeafNode("gone")]),
      RowNode([LeafNode("gone")]),
    ])
  let html = render(nodes, [], [])
  html |> string.contains("part=\"group\"") |> should.be_false
  html |> string.contains("Пусто") |> should.be_false
  html |> string.contains("part=\"row\"") |> should.be_false
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
  let assert Ok(body) =
    dom_containment.slice_element(html, "part=\"group-body\"")
  body |> string.contains("data-n=\"a\"") |> should.be_true
  body |> string.contains("part=\"row\"") |> should.be_true
  let assert Ok(row) = dom_containment.slice_element(body, "part=\"row\"")
  row |> string.contains("data-n=\"b\"") |> should.be_true
  row |> string.contains("data-n=\"c\"") |> should.be_true
}

/// A Group whose only leaf is currently absent must still occupy its slot
/// in the returned list — markup cannot observe this (`element.none()`
/// serializes to nothing), so the assertion targets `arrange`'s returned
/// list directly, mirroring the slot-holding pattern established at
/// `array_field.gleam:228-236`. Without the fix, the collapsed Group is
/// dropped from the list entirely and this equals 1, not 2.
pub fn collapsed_group_keeps_its_slot_test() {
  let nodes =
    Some([GroupNode(Some("Пусто"), [LeafNode("gone")]), LeafNode("a")])
  let rendered = layout.arrange(nodes, entries(["a"]), leaf_renderer(["a"]))
  list.length(rendered) |> should.equal(2)
}

/// Same layout, rendered once with the Group's leaf absent (Group collapses
/// to `element.none()`) and once present (Group renders normally) — the
/// returned list length must stay identical either way, so "a" always lands
/// at the same index. An unkeyed positional diff only ever sees index 0
/// change shape; it must never see a length change that would reindex and
/// rebuild "a" from scratch.
pub fn group_collapse_does_not_shift_sibling_position_test() {
  let nodes =
    Some([GroupNode(Some("Пусто"), [LeafNode("gone")]), LeafNode("a")])
  let collapsed = layout.arrange(nodes, entries(["a"]), leaf_renderer(["a"]))
  let expanded =
    layout.arrange(nodes, entries(["a", "gone"]), leaf_renderer(["a", "gone"]))
  list.length(collapsed) |> should.equal(list.length(expanded))
}
