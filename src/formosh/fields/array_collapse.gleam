//// Pure logic for collapsing completed array rows: `ui:options` parsing, the
//// completed predicate, and summary-text assembly. No Lustre/DOM dependency —
//// the renderer (`array_field`) builds on these, mirroring the
//// `swipe_review` / `swipe_review_field` split.

import formosh/fields/value_display
import formosh/form/model.{type FormModel}
import formosh/form/path.{type FieldPath}
import formosh/form/union_resolver
import formosh/schema/properties
import formosh/schema/types.{type SchemaProperty, type Value}
import formosh/schema/ui_resolver
import formosh/schema/ui_schema.{type UiSchema}
import formosh/schema/validator
import formosh/validation/field_requirements
import gleam/dict.{type Dict}
import gleam/int
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

/// Display strings for one row's summary line, in `fields` order. The caller
/// wraps each in its own element — this module stays Lustre-free.
///
/// Names are looked up against the row's RESOLVED schema, so a field a
/// conditional branch introduced is available and one it removed is skipped.
/// An empty `fields` defaults to every scalar field in schema order, which
/// deliberately excludes arrays: a lesion count only appears when the author
/// lists it.
pub fn summary_values(
  ui_schema: UiSchema,
  row_path: FieldPath,
  item_schema: SchemaProperty,
  item: Value,
  selected: List(#(FieldPath, Int)),
  fields: List(String),
) -> List(String) {
  let resolved =
    union_resolver.resolve_effective_property(
      item_schema,
      item,
      row_path,
      selected,
    )
  case resolved.properties {
    option.Some(props) -> {
      let names = case fields {
        [] ->
          // `scalar_names` filters on the declared `field_type`, which is
          // `None` for a property with no `"type"` key — so an untyped
          // property holding an array still needs excluding here, by its
          // actual row value, to honour "the default set excludes arrays".
          scalar_names(props)
          |> list.filter(fn(name) {
            case field_value(item, name) {
              option.Some(types.ArrayValue(_)) -> False
              _ -> True
            }
          })
        chosen -> chosen
      }
      list.filter_map(names, fn(name) {
        case properties.get(props, name), field_value(item, name) {
          option.Some(prop), option.Some(value) ->
            case entry(ui_schema, row_path, name, prop, value) {
              option.Some(text) -> Ok(text)
              option.None -> Error(Nil)
            }
          _, _ -> Error(Nil)
        }
      })
    }
    option.None -> []
  }
}

fn scalar_names(props: List(#(String, SchemaProperty))) -> List(String) {
  props
  |> list.filter(fn(pair) {
    case { pair.1 }.field_type {
      option.Some(types.ArrayType) | option.Some(types.ObjectType) -> False
      _ -> True
    }
  })
  |> list.map(fn(pair) { pair.0 })
}

fn field_value(item: Value, name: String) -> option.Option(Value) {
  case item {
    types.ObjectValue(fields) ->
      list.key_find(fields, name) |> option.from_result
    _ -> option.None
  }
}

fn entry(
  ui_schema: UiSchema,
  row_path: FieldPath,
  name: String,
  prop: SchemaProperty,
  value: Value,
) -> option.Option(String) {
  let field_path = list.append(row_path, [path.PropertySegment(name)])
  let hints = ui_resolver.resolve_hints(ui_schema, field_path, prop)
  let title = value_display.label_text(name, prop, hints)
  case value {
    // Empty values are omitted outright rather than rendered as the unset
    // dash `display_value` would return — a summary line is not a review
    // row. Password or not: omission discloses strictly less than a mask.
    types.NullValue | types.StringValue("") -> option.None
    types.ArrayValue([]) -> option.None
    non_empty ->
      case value_display.is_password(prop, hints) {
        // A password field masks every non-empty value uniformly, whatever
        // its shape — including BooleanValue(False). Patching one shape's
        // arm at a time (as the ArrayValue arm briefly was) leaves every
        // other shape still able to leak; hoisting the check here is what
        // stops the next arm from reintroducing the same hole.
        True -> option.Some(value_display.password_mask)
        False ->
          case non_empty {
            types.ArrayValue(xs) ->
              option.Some(title <> ": " <> int.to_string(list.length(xs)))
            types.BooleanValue(False) -> option.None
            types.BooleanValue(True) -> option.Some(title)
            types.ObjectValue(_) -> option.None
            other ->
              option.Some(value_display.display_value(
                prop,
                hints,
                option.Some(other),
              ))
          }
      }
  }
}
