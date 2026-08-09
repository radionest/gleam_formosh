/// Balanced-element slicer for DOM-containment assertions.
///
/// Layout tests need to prove that a marked wrapper element (`part="row"`,
/// `part="group-body"`, ...) actually CONTAINS certain descendants, not
/// merely that both happen to appear somewhere in the same rendered
/// document. `string.split_once` alone cannot express that — its tail is
/// the rest of the whole document, so anything rendered later, including
/// `layout.arrange`'s leftover append (`src/formosh/fields/layout.gleam:
/// 47-49`), would still make a bare `contains` check on that tail pass.
///
/// `slice_element` returns the substring spanned by the element whose
/// opening tag carries the **first** occurrence of `marker`: from that
/// marker through the same element's own matching closing tag, and nothing
/// that follows it. Callers wanting a later occurrence — a second `Row`, a
/// second array item — must pre-split the input themselves.
///
/// Correctness rests on one assumption: Lustre escapes `<` both in text
/// content and in attribute values, so no `<div` / `</div>` token in
/// rendered output can be spoofed by user-supplied data in a test
/// fixture — every literal `<div` / `</div>` substring found here is a
/// genuine tag boundary. Every layout wrapper (`layout.gleam`'s
/// `row_element` / `group_element`) is a plain `div`, and so is
/// `field_dispatcher`'s `part="field"` wrapper, so counting only
/// `<div` / `</div>` is sufficient — this helper does not track any other
/// element name.
import gleam/string
import gleam/string_tree.{type StringTree}

/// Slice out the element whose opening tag contains `marker` — its own
/// subtree, and nothing after it.
///
/// `Error(Nil)` when `marker` does not occur in `html`, mirroring
/// `string.split_once`'s own error convention (callers already
/// `let assert Ok(...)` that one; do the same here).
pub fn slice_element(html: String, marker: String) -> Result(String, Nil) {
  case string.split_once(html, marker) {
    Error(Nil) -> Error(Nil)
    Ok(#(_, after)) ->
      // Depth starts at 1: `marker` sits inside the opening tag of the div
      // whose subtree we want, and that tag is already "open" by the time
      // the scan starts — no need to hunt backwards for its `<div`.
      scan(after, 1, string_tree.new())
  }
}

/// Scan forward counting `<div` / `</div>` until `depth` returns to 0,
/// accumulating everything scanned so far. The `</div>` that brings depth
/// to 0 is the one that closes the element the scan started inside.
fn scan(rest: String, depth: Int, acc: StringTree) -> Result(String, Nil) {
  let open = string.split_once(rest, "<div")
  let close = string.split_once(rest, "</div>")
  case open, close {
    // No `</div>` left anywhere ahead: depth can never return to 0.
    _, Error(Nil) -> Error(Nil)
    // No more `<div` ahead, so the next `</div>` is a step towards (or
    // exactly) the one this depth is waiting for.
    Error(Nil), Ok(#(before, after)) -> close_here(acc, before, after, depth)
    Ok(#(before_open, after_open)), Ok(#(before_close, after_close)) ->
      case string.byte_size(before_open) < string.byte_size(before_close) {
        // `<div` occurs first: one level deeper. (The two tokens can never
        // start at the same offset — they differ at their second byte —
        // so this comparison is never a tie.)
        True ->
          scan(
            after_open,
            depth + 1,
            acc
              |> string_tree.append(before_open)
              |> string_tree.append("<div"),
          )
        // `</div>` occurs first.
        False -> close_here(acc, before_close, after_close, depth)
      }
  }
}

fn close_here(
  acc: StringTree,
  before: String,
  after: String,
  depth: Int,
) -> Result(String, Nil) {
  let acc = acc |> string_tree.append(before) |> string_tree.append("</div>")
  case depth - 1 {
    0 -> Ok(string_tree.to_string(acc))
    next -> scan(after, next, acc)
  }
}
