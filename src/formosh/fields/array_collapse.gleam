//// Pure logic for collapsing completed array rows: `ui:options` parsing, the
//// completed predicate, and summary-text assembly. No Lustre/DOM dependency —
//// the renderer (`array_field`) builds on these, mirroring the
//// `swipe_review` / `swipe_review_field` split.

import formosh/form/model.{type FormModel}
import formosh/form/path.{type FieldPath}
import formosh/schema/types.{type SchemaProperty, type Value}
import formosh/schema/validator
import formosh/validation/field_requirements
import gleam/dict.{type Dict}
import gleam/list
import gleam/option
import gleam/set.{type Set}

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

/// Row indices that failed array-item validation, from ONE pass over the whole
/// array. `validate_array_items` resolves each row's own unions and
/// `if/then/else` internally, so the raw item schema is what goes in.
pub fn incomplete_rows(
  array_path: FieldPath,
  item_schema: SchemaProperty,
  items: List(Value),
  selected: List(#(FieldPath, Int)),
) -> Set(Int) {
  validator.validate_array_items(
    array_path,
    item_schema,
    types.ArrayValue(items),
    selected,
  )
  |> list.filter_map(fn(err) { row_index(array_path, err.field) })
  |> set.from_list
}

fn row_index(array_path: FieldPath, err_path: FieldPath) -> Result(Int, Nil) {
  case path.relative_to(err_path, array_path) {
    option.Some([path.ArraySegment(i), ..]) -> Ok(i)
    _ -> Error(Nil)
  }
}

/// A row may collapse only when all three hold: it carries at least one
/// non-empty own field, array-item validation reported nothing for it, and no
/// recorded error lies under its path.
///
/// The third conjunct is what makes "collapsed ⇒ nothing hidden" true rather
/// than merely asserted: a cross-field validator (set through the component's
/// `validator` JS property) can record a submit-blocking error inside a row the
/// schema validator considers clean. The first stops an all-optional or
/// freshly added row from collapsing blank at first paint. Both only ever
/// narrow the collapsible set.
pub fn is_completed(
  model: FormModel,
  array_path: FieldPath,
  index: Int,
  item: Value,
  incomplete: Set(Int),
) -> Bool {
  let row_path = list.append(array_path, [path.ArraySegment(index)])
  has_any_value(item)
  && !set.contains(incomplete, index)
  && !model.has_errors_under_path(model, row_path)
}

fn has_any_value(item: Value) -> Bool {
  case item {
    types.ObjectValue(fields) ->
      list.any(fields, fn(pair) { !is_blank(pair.1) })
    _ -> False
  }
}

/// The library's own emptiness rule (None / null / empty string), widened to
/// empty containers — a row holding only `[]` is not "filled in".
fn is_blank(value: Value) -> Bool {
  case value {
    types.ArrayValue([]) | types.ObjectValue([]) -> True
    other -> field_requirements.is_empty_value(option.Some(other))
  }
}
