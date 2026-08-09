/// Layout walker for `ui:layout`.
///
/// `arrange` turns a container's ordered entry list into elements, placing
/// the ones a layout names and appending the rest. It is generic in both the
/// entry value and the message type: it never resolves a leaf itself, it
/// calls back into `render_leaf`. That is the seam that keeps each render
/// site owning its own ctx-construction rules (`make_field_ctx` at the root,
/// `make_child_ctx` in containers, row-resolved `required` in arrays) —
/// re-deriving that inheritance here would be a second source of truth
/// alongside `field_common`, which `form/visibility` deliberately mirrors.
///
/// It is also where a future multi-segment leaf lands: `render_leaf` already
/// takes an arbitrary string, so path addressing extends the callers, not
/// this module.
import formosh/schema/ui_schema.{type LayoutNode, GroupNode, LeafNode, RowNode}
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

/// Default inline arrangement for a `Row`.
///
/// `auto-fit` + `minmax` collapses to fewer columns on narrow viewports
/// without a media query — inline styles cannot express one. Any
/// `::part(row)` rule from the host wins over this.
const row_style = "display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,12rem),1fr));gap:var(--formosh-row-gap,1rem)"

/// Arrange `entries` according to `layout`.
///
/// With `None`, every entry renders in the order supplied. With `Some(nodes)`,
/// nodes render in order and any entry the layout did not place is appended
/// afterwards — so a field can never disappear because the layout omitted it.
pub fn arrange(
  layout: Option(List(LayoutNode)),
  entries: List(#(String, a)),
  render_leaf: fn(String) -> Option(Element(msg)),
) -> List(Element(msg)) {
  case layout {
    None -> render_all(entries, render_leaf)
    Some(nodes) -> {
      let #(placed, used) = render_nodes(nodes, render_leaf, [])
      let leftovers =
        list.filter(entries, fn(entry) { !list.contains(used, entry.0) })
      list.append(placed, render_all(leftovers, render_leaf))
    }
  }
}

fn render_all(
  entries: List(#(String, a)),
  render_leaf: fn(String) -> Option(Element(msg)),
) -> List(Element(msg)) {
  list.filter_map(entries, fn(entry) {
    case render_leaf(entry.0) {
      Some(el) -> Ok(el)
      None -> Error(Nil)
    }
  })
}

fn render_nodes(
  nodes: List(LayoutNode),
  render_leaf: fn(String) -> Option(Element(msg)),
  used: List(String),
) -> #(List(Element(msg)), List(String)) {
  list.fold(nodes, #([], used), fn(acc, node) {
    let #(elements, used_so_far) = acc
    let #(rendered, used_next) = render_node(node, render_leaf, used_so_far)
    case rendered {
      Some(el) -> #(list.append(elements, [el]), used_next)
      None -> #(elements, used_next)
    }
  })
}

fn render_node(
  node: LayoutNode,
  render_leaf: fn(String) -> Option(Element(msg)),
  used: List(String),
) -> #(Option(Element(msg)), List(String)) {
  case node {
    LeafNode(name) -> #(render_leaf(name), [name, ..used])
    RowNode(elements) -> {
      let #(children, used_next) = render_nodes(elements, render_leaf, used)
      case children {
        [] -> #(None, used_next)
        _ -> #(Some(row_element(children)), used_next)
      }
    }
    GroupNode(label, elements) -> {
      let #(children, used_next) = render_nodes(elements, render_leaf, used)
      case children {
        [] -> #(None, used_next)
        _ -> #(Some(group_element(label, children)), used_next)
      }
    }
  }
}

fn row_element(children: List(Element(msg))) -> Element(msg) {
  html.div(
    [
      attribute.class("formosh-row"),
      attribute.attribute("part", "row"),
      attribute.attribute("style", row_style),
    ],
    children,
  )
}

fn group_element(
  label: Option(String),
  children: List(Element(msg)),
) -> Element(msg) {
  html.div(
    [attribute.class("formosh-group"), attribute.attribute("part", "group")],
    [
      case label {
        Some(text) ->
          html.div(
            [
              attribute.class("formosh-group-label"),
              attribute.attribute("part", "group-label"),
            ],
            [html.text(text)],
          )
        None -> element.none()
      },
      html.div(
        [
          attribute.class("formosh-group-body"),
          attribute.attribute("part", "group-body"),
        ],
        children,
      ),
    ],
  )
}
