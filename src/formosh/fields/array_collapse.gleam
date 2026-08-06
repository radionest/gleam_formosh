//// Pure logic for collapsing completed array rows: `ui:options` parsing, the
//// completed predicate, and summary-text assembly. No Lustre/DOM dependency —
//// the renderer (`array_field`) builds on these, mirroring the
//// `swipe_review` / `swipe_review_field` split.

import formosh/schema/types.{type Value}
import gleam/dict.{type Dict}
import gleam/list

/// `ui:options` keys read by the array collapse feature.
pub type CollapseOptions {
  CollapseOptions(enabled: Bool, label: String, summary_fields: List(String))
}

/// Parse the collapse settings out of an `ui:options` bag. Every key is
/// optional and a wrong-typed value falls back to its default, so a malformed
/// UiSchema degrades to "feature off" rather than failing the render.
pub fn options(bag: Dict(String, Value)) -> CollapseOptions {
  CollapseOptions(
    enabled: case dict.get(bag, "collapseCompleted") {
      Ok(types.BooleanValue(b)) -> b
      _ -> False
    },
    label: case dict.get(bag, "collapseCompletedLabel") {
      Ok(types.StringValue(s)) -> s
      _ -> "Collapse completed"
    },
    summary_fields: case dict.get(bag, "summaryFields") {
      Ok(types.ArrayValue(xs)) ->
        list.filter_map(xs, fn(x) {
          case x {
            types.StringValue(s) -> Ok(s)
            _ -> Error(Nil)
          }
        })
      _ -> []
    },
  )
}
