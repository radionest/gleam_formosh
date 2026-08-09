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
///
/// Every node — leaf, `Row`, or `Group` — always occupies exactly one slot
/// in its parent's children list, whether or not it currently has anything
/// to show: an absent leaf and a `Row`/`Group` with nothing real beneath it
/// both render as `element.none()` rather than being omitted. Lustre's
/// children at these seams are unkeyed, so omitting a node instead of
/// holding its slot would shift every later sibling's index whenever a
/// conditionally-injected field flips a node between present and absent,
/// forcing a positional diff to rebuild them from scratch. "Real" tracks
/// whether `render_leaf` answered `Some`, never whether the resulting
/// element happens to equal `element.none()` — a present-but-suppressed
/// leaf (`ui:widget: "hidden"`) answers `Some(element.none())` and must
/// still count as real, exactly like a visible one, while a genuinely
/// absent leaf answers `None` and must not.
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
/// nodes render in order and any entry the layout did not name is appended
/// afterwards — so a field can never disappear because the layout omitted it.
/// Any name the layout visits is excluded from that fallback whether or not
/// it produced output there — correct only because `render_leaf` must be a
/// deterministic function of the name, so a second call could only repeat
/// the same answer.
pub fn arrange(
  layout: Option(List(LayoutNode)),
  entries: List(#(String, a)),
  render_leaf: fn(String) -> Option(Element(msg)),
) -> List(Element(msg)) {
  case layout {
    None -> render_all(entries, render_leaf)
    Some(nodes) -> {
      let #(placed, used, _any_real) = render_nodes(nodes, render_leaf, [])
      let leftovers =
        list.filter(entries, fn(entry) { !list.contains(used, entry.0) })
      list.append(placed, render_all(leftovers, render_leaf))
    }
  }
}

// Unlike `render_node`, dropping a `None` here is correct as-is: every real
// call site passes `entries` (or a filter of it) as both the list iterated
// here and the list `render_leaf` looks names up against, so `render_leaf`
// can only answer `None` for a name that was never in `entries` to begin
// with — there is no slot to hold open. Only a `LayoutNode` leaf can name
// something outside that closed loop (a layout referencing a field that
// isn't currently resolved), which is exactly what `render_node` guards.
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

// The third element of the tuple is "did any leaf in this subtree answer
// `Some`", OR-folded across every node — see `render_node` for why a
// `Row`/`Group` needs it instead of asking whether its own children list is
// empty (it never is, once every node holds its own slot).
fn render_nodes(
  nodes: List(LayoutNode),
  render_leaf: fn(String) -> Option(Element(msg)),
  used: List(String),
) -> #(List(Element(msg)), List(String), Bool) {
  list.fold(nodes, #([], used, False), fn(acc, node) {
    let #(elements, used_so_far, any_real_so_far) = acc
    let #(el, used_next, node_real) =
      render_node(node, render_leaf, used_so_far)
    #(list.append(elements, [el]), used_next, any_real_so_far || node_real)
  })
}

fn render_node(
  node: LayoutNode,
  render_leaf: fn(String) -> Option(Element(msg)),
  used: List(String),
) -> #(Element(msg), List(String), Bool) {
  case node {
    LeafNode(name) ->
      case render_leaf(name) {
        // Present (even if suppressed to `element.none()` by the
        // dispatcher) — counts as real, and the element IS the slot.
        Some(el) -> #(el, [name, ..used], True)
        // Absent — still occupies its slot, as `element.none()`, but does
        // not count as real: a `Row`/`Group` of only such leaves must
        // still collapse (see the RowNode/GroupNode branches below).
        None -> #(element.none(), [name, ..used], False)
      }
    RowNode(elements) -> {
      let #(children, used_next, any_real) =
        render_nodes(elements, render_leaf, used)
      case any_real {
        // Nothing real beneath this Row — it holds its own slot instead of
        // rendering an empty grid. `children` alone can no longer answer
        // this: every present child now holds its own slot too, so a Row
        // of only absent/suppressed leaves has a non-empty `children` full
        // of placeholders, indistinguishable by length from one with real
        // content — `any_real` is the only signal left that tells them
        // apart (a `RowNode([])` with no declared elements at all is the
        // one case `children` is still `[]`, and `any_real` is correctly
        // `False` for it too).
        False -> #(element.none(), used_next, False)
        True -> #(row_element(children), used_next, True)
      }
    }
    GroupNode(label, elements) -> {
      let #(children, used_next, any_real) =
        render_nodes(elements, render_leaf, used)
      case any_real {
        // See the RowNode branch above — same collapse rationale.
        False -> #(element.none(), used_next, False)
        True -> #(group_element(label, children), used_next, True)
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
