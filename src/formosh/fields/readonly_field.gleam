// Static read-only ("review") rendering of submitted form values.
//
// Used when the form component runs in `read_only` mode (see
// `component.read_only` / `FormModel.read_only`). Instead of input widgets,
// every field is rendered as a "label → value" summary row:
//
// - enums / oneOf are shown as their human label (oneOf `title`), not the code
// - booleans render as Yes / No
// - nested objects expand into a labelled group of rows
// - arrays of flat objects render as a compact table (schema titles as the
//   header), other arrays as one group / bullet per item
//
// The returned `Element(FormMsg)` never dispatches a message — there are no
// inputs and no events, so the value is genuinely immutable.

import formosh/fields/field_common.{type FieldRenderCtx}
import formosh/form/model.{type FormModel, type FormMsg}
import formosh/form/path.{ArraySegment, PropertySegment}
import formosh/form/union_resolver
import formosh/schema/properties
import formosh/schema/types.{type RenderHints, type SchemaProperty, type Value}
import formosh/schema/ui_resolver
import gleam/bool
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

const dash = "—"

const password_mask = "••••••••"

/// Render a single field (at any depth) as a static summary node.
pub fn render(ctx: FieldRenderCtx, model: FormModel) -> Element(FormMsg) {
  // Only `HiddenWidget` is suppressed here. Unlike edit mode
  // (`field_dispatcher`), schema-`readOnly` fields are NOT filtered by
  // `show_readonly_fields` — a review screen deliberately shows every stored
  // value, read-only or not.
  case ctx.hints.widget == Some(types.HiddenWidget) {
    True -> element.none()
    False ->
      case ctx.property.field_type {
        Some(types.ObjectType) -> render_object(ctx, model)
        Some(types.ArrayType) -> render_array(ctx, model)
        _ ->
          render_row(
            label_for(ctx),
            display_value(ctx.property, ctx.hints, ctx.value),
          )
      }
  }
}

// --- Scalar rows ---

fn render_row(label: String, value: String) -> Element(FormMsg) {
  html.div(
    [
      attribute.class("formosh-readonly-field"),
      attribute.attribute("part", "readonly-field"),
    ],
    [
      html.span(
        [
          attribute.class("formosh-readonly-label"),
          attribute.attribute("part", "readonly-label"),
        ],
        [html.text(label)],
      ),
      html.span(
        [
          attribute.class("formosh-readonly-value"),
          attribute.attribute("part", "readonly-value"),
        ],
        [html.text(value)],
      ),
    ],
  )
}

/// Value-only node (no label) — used for empty arrays so there is no stray
/// blank label span under the array's group heading.
fn render_value_only(value: String) -> Element(FormMsg) {
  html.span(
    [
      attribute.class("formosh-readonly-value"),
      attribute.attribute("part", "readonly-value"),
    ],
    [html.text(value)],
  )
}

fn label_for(ctx: FieldRenderCtx) -> String {
  field_common.label_text(
    path.get_field_name(ctx.path),
    ctx.property,
    ctx.hints,
  )
}

/// True when a field should be masked in review mode — either the schema
/// declares `format: "password"` or a `ui:widget: "password"` hint applies.
/// The mask is a fixed string: a length-proportional one would leak the
/// value's length.
fn is_password(property: SchemaProperty, hints: RenderHints) -> Bool {
  let by_widget = hints.widget == Some(types.CustomWidget("password"))
  let by_format = case property.string_constraints {
    Some(constraints) -> constraints.format == Some(types.PasswordFormat)
    None -> False
  }
  by_widget || by_format
}

/// Format a leaf value for display, mapping enum codes to their oneOf label
/// and masking password fields.
fn display_value(
  property: SchemaProperty,
  hints: RenderHints,
  value: Option(Value),
) -> String {
  case value {
    None | Some(types.NullValue) -> dash
    Some(v) ->
      case is_password(property, hints), v {
        True, types.StringValue("") -> dash
        True, _ -> password_mask
        False, _ ->
          case enum_label(property, v) {
            Some(label) -> label
            None -> scalar_to_string(v)
          }
      }
  }
}

fn scalar_to_string(value: Value) -> String {
  case value {
    types.StringValue("") -> dash
    types.StringValue(s) -> s
    types.IntegerValue(i) -> int.to_string(i)
    types.NumberValue(n) -> float.to_string(n)
    types.BooleanValue(True) -> "Yes"
    types.BooleanValue(False) -> "No"
    types.NullValue -> dash
    // Containers are handled by render_object / render_array, never here.
    types.ArrayValue(_) | types.ObjectValue(_) -> dash
  }
}

/// Resolve a stored enum code to its human label via `oneOf` const+title
/// options. Plain `enum` lists carry no labels (the code *is* the label), so
/// they fall through to `scalar_to_string`.
fn enum_label(property: SchemaProperty, value: Value) -> Option(String) {
  case property.one_of {
    Some(schemas) -> {
      let target = scalar_to_string(value)
      one_of_options(schemas)
      |> list.find(fn(opt) { opt.0 == target })
      |> result.map(fn(opt) { opt.1 })
      |> option.from_result
    }
    None -> None
  }
}

/// Extract const+title pairs from oneOf sub-schemas. Same shape as
/// `string_field.extract_one_of_options`, kept local so the read-only path
/// has no dependency on the editable widgets; the const is formatted with
/// this module's `scalar_to_string` so the key matches `enum_label`'s lookup.
fn one_of_options(one_of: List(SchemaProperty)) -> List(#(String, String)) {
  use schema <- list.filter_map(one_of)
  use vals <- result.try(option.to_result(schema.enum_values, Nil))
  use const_val <- result.try(case vals {
    [val] -> Ok(val)
    _ -> Error(Nil)
  })
  let value = scalar_to_string(const_val)
  Ok(#(value, option.unwrap(schema.title, value)))
}

// --- Object groups ---

fn render_object(ctx: FieldRenderCtx, model: FormModel) -> Element(FormMsg) {
  let rows = case ctx.property.properties {
    Some(props) ->
      render_props(
        ctx,
        model,
        props,
        ctx.path,
        ctx.property.required,
        ctx.hints.order,
      )
    None -> []
  }
  group(label_for(ctx), rows)
}

fn render_props(
  parent: FieldRenderCtx,
  model: FormModel,
  props: List(#(String, SchemaProperty)),
  base_path: path.FieldPath,
  required: List(String),
  order: Option(List(String)),
) -> List(Element(FormMsg)) {
  properties.apply_order(props, order)
  |> list.map(fn(entry) {
    let #(child_name, child_prop) = entry
    let child_path = list.append(base_path, [PropertySegment(child_name)])
    let child_ctx =
      field_common.make_child_ctx(
        parent: parent,
        model: model,
        path: child_path,
        property: child_prop,
        is_required: list.contains(required, child_name),
      )
    render(child_ctx, model)
  })
}

// --- Arrays ---

fn render_array(ctx: FieldRenderCtx, model: FormModel) -> Element(FormMsg) {
  let items = case ctx.value {
    Some(types.ArrayValue(xs)) -> xs
    _ -> []
  }
  let body = case items, ctx.property.items {
    [], _ -> [render_value_only(dash)]
    _, Some(item_schema) ->
      case scalar_object_columns(ctx, model, item_schema) {
        Some(columns) -> [render_table(columns, items)]
        None -> render_groups(ctx, model, item_schema, items)
      }
    _, None -> [render_value_only(dash)]
  }
  group(label_for(ctx), body)
}

/// `Some(columns)` when array items are objects whose every visible property
/// is a scalar — the case that renders cleanly as a table. Anything with
/// nested objects/arrays returns `None` and falls back to per-item groups.
///
/// Each column carries its resolved `RenderHints` so the table honours the
/// same UiSchema as every other field (`ui:widget: "hidden"` drops the
/// column, `ui:title` names the header). The index in the representative
/// `ArraySegment(0)` path is ignored by `ui_resolver.lookup`, which descends
/// into the array `items` template — so it is correct for every row.
fn scalar_object_columns(
  ctx: FieldRenderCtx,
  model: FormModel,
  item_schema: SchemaProperty,
) -> Option(List(#(String, SchemaProperty, RenderHints))) {
  // Item-level conditionals make the visible field set row-dependent, which a
  // fixed-column table cannot represent. Defer to per-row groups
  // (`render_groups`), which resolve each row's then/else branch first.
  use <- bool.guard(item_schema.conditionals != [], None)
  case item_schema.field_type, item_schema.properties {
    Some(types.ObjectType), Some(props) -> {
      let columns =
        list.map(props, fn(entry) {
          let #(name, prop) = entry
          let col_path =
            list.append(ctx.path, [ArraySegment(0), PropertySegment(name)])
          #(
            name,
            prop,
            ui_resolver.resolve_hints(model.ui_schema, col_path, prop),
          )
        })
      let visible =
        list.filter(columns, fn(col) {
          let #(_, _, hints) = col
          hints.widget != Some(types.HiddenWidget)
        })
      case visible != [] && list.all(visible, fn(col) { is_scalar(col.1) }) {
        True -> Some(visible)
        False -> None
      }
    }
    _, _ -> None
  }
}

fn is_scalar(property: SchemaProperty) -> Bool {
  case property.field_type {
    Some(types.ObjectType) | Some(types.ArrayType) -> False
    _ -> True
  }
}

fn render_table(
  columns: List(#(String, SchemaProperty, RenderHints)),
  items: List(Value),
) -> Element(FormMsg) {
  let header =
    html.tr(
      [],
      list.map(columns, fn(col) {
        let #(name, prop, hints) = col
        html.th([attribute.attribute("part", "readonly-th")], [
          html.text(field_common.label_text(name, prop, hints)),
        ])
      }),
    )
  let rows =
    list.map(items, fn(item) {
      html.tr(
        [],
        list.map(columns, fn(col) {
          let #(name, prop, col_hints) = col
          let cell = path.get_at_path(item, [PropertySegment(name)])
          html.td([attribute.attribute("part", "readonly-td")], [
            html.text(display_value(prop, col_hints, cell)),
          ])
        }),
      )
    })
  html.table(
    [
      attribute.class("formosh-readonly-table"),
      attribute.attribute("part", "readonly-table"),
    ],
    [html.thead([], [header]), html.tbody([], rows)],
  )
}

fn render_groups(
  ctx: FieldRenderCtx,
  model: FormModel,
  item_schema: SchemaProperty,
  items: List(Value),
) -> List(Element(FormMsg)) {
  list.index_map(items, fn(item, index) {
    let item_path = list.append(ctx.path, [ArraySegment(index)])
    case item {
      types.ObjectValue(_) -> {
        let resolved =
          union_resolver.resolve_effective_property(
            item_schema,
            item,
            item_path,
            model.selected_branches,
          )
        let rows = case resolved.properties {
          Some(props) ->
            render_props(ctx, model, props, item_path, resolved.required, None)
          None -> []
        }
        group("#" <> int.to_string(index + 1), rows)
      }
      _ ->
        render_row(
          "#" <> int.to_string(index + 1),
          display_value(
            item_schema,
            ui_resolver.resolve_hints(model.ui_schema, item_path, item_schema),
            Some(item),
          ),
        )
    }
  })
}

// --- Shared container chrome ---

fn group(label: String, children: List(Element(FormMsg))) -> Element(FormMsg) {
  html.div(
    [
      attribute.class("formosh-readonly-group"),
      attribute.attribute("part", "readonly-group"),
    ],
    [
      html.div(
        [
          attribute.class("formosh-readonly-group-label"),
          attribute.attribute("part", "readonly-group-label"),
        ],
        [html.text(label)],
      ),
      html.div(
        [
          attribute.class("formosh-readonly-group-body"),
          attribute.attribute("part", "readonly-group-body"),
        ],
        children,
      ),
    ],
  )
}
