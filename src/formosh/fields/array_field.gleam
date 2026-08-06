/// Array container renderer.
///
/// Renders the array label, item-level frames (remove button),
/// and the add-item button. Child field rendering is delegated back to
/// the caller via `render_child` — this keeps a single source of truth
/// for widget dispatch (see `field_dispatcher.render_field_at_path`).
import formosh/fields/array_collapse
import formosh/fields/field_common.{type FieldRenderCtx}
import formosh/form/model.{
  type FormModel, type FormMsg, AddArrayItemPath, MoveArrayItemPath,
  RemoveArrayItemPath,
}
import formosh/form/path
import formosh/form/union_resolver
import formosh/form/widget_msg.{ToggleCollapseCompleted, ToggleRowExpanded}
import formosh/schema/properties
import formosh/schema/types.{type SchemaProperty, type Value}
import formosh/schema/ui_resolver
import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import lustre/attribute.{class, disabled, type_}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// Render an array field as a labelled container of items.
///
/// Each item gets an optional remove-button header followed by its child
/// fields. Items resolve their own conditionals against the row's own
/// values, so every row is treated independently.
///
/// The dispatcher passes itself as `render_child` so any child field —
/// including nested arrays and objects — goes through the same widget
/// dispatch as top-level fields.
pub fn render_container(
  ctx: FieldRenderCtx,
  model: FormModel,
  render_child: fn(FieldRenderCtx, FormModel) -> Element(FormMsg),
) -> Element(FormMsg) {
  let array_name = path.get_field_name(ctx.path)
  let description = ctx.property.description

  let items = case ctx.value {
    Some(types.ArrayValue(xs)) -> xs
    Some(_) -> []
    None -> []
  }

  let count = list.length(items)
  let #(min_items, max_items) = case ctx.property.array_constraints {
    Some(c) -> #(option.unwrap(c.min_items, 0), c.max_items)
    None -> #(0, None)
  }

  // `resolve_hints` always wraps `addable`/`removable` in `Some`
  // (UiSchema override or `SchemaProperty.addable` Bool fallback), so the
  // outer `option.unwrap` default below is just a defensive no-op.
  // minItems/maxItems gate on top: the add button is hidden once the array
  // is full, per-row remove is hidden once shrinking would violate minItems.
  let addable =
    option.unwrap(ctx.hints.addable, True)
    && case max_items {
      Some(max) -> count < max
      None -> True
    }
  let removable = option.unwrap(ctx.hints.removable, True) && count > min_items
  let orderable = option.unwrap(ctx.hints.orderable, True)

  let collapse = array_collapse.options(ctx.hints.options)
  let collapse_available = collapse.enabled && !ctx.is_readonly
  let collapse_active =
    collapse_available && !list.contains(model.array_collapse_off, ctx.path)
  let incomplete = case collapse_available, ctx.property.items {
    True, Some(item_schema) ->
      array_collapse.incomplete_rows(
        ctx.path,
        item_schema,
        items,
        model.selected_branches,
      )
    _, _ -> set.new()
  }
  let completed_count =
    list.index_fold(items, 0, fn(acc, item, index) {
      case
        array_collapse.is_completed(model, ctx.path, index, item, incomplete)
      {
        True -> acc + 1
        False -> acc
      }
    })

  html.div([class("array-field")], [
    field_common.render_container_label(
      field_name: array_name,
      property: ctx.property,
      is_required: ctx.is_required,
      css_class: "array-label",
      hints: ctx.hints,
    ),
    case description {
      Some(desc) -> html.p([class("field-description")], [html.text(desc)])
      None -> element.none()
    },
    case collapse_available {
      True ->
        render_collapse_header(
          ctx,
          collapse.label,
          collapse_active,
          completed_count,
          count,
        )
      False -> element.none()
    },
    html.div(
      [class("array-items")],
      list.index_map(items, fn(item, index) {
        render_array_item(
          ctx,
          removable,
          orderable,
          count,
          item,
          index,
          collapse,
          collapse_active,
          incomplete,
          model,
          render_child,
        )
      }),
    ),
    case ctx.is_readonly || !addable {
      True -> element.none()
      False ->
        html.button(
          [
            type_("button"),
            class("add-array-item"),
            event.on_click(AddArrayItemPath(ctx.path)),
          ],
          [html.text("Добавить элемент")],
        )
    },
  ])
}

/// Toggle + progress. Rendered whenever collapsing is available, including
/// while the user has it switched off — gating this on `array_collapse_off`
/// would delete the only control that can switch it back on.
fn render_collapse_header(
  ctx: FieldRenderCtx,
  label: String,
  active: Bool,
  completed: Int,
  total: Int,
) -> Element(FormMsg) {
  html.div([class("array-collapse-header")], [
    html.label([attribute.attribute("part", "array-toggle")], [
      html.input([
        type_("checkbox"),
        attribute.checked(active),
        event.on_click(model.array_msg(ToggleCollapseCompleted(ctx.path))),
      ]),
      html.text(label),
    ]),
    html.span([attribute.attribute("part", "array-progress")], [
      html.text(int.to_string(completed) <> " / " <> int.to_string(total)),
    ]),
  ])
}

/// Render a single row: optional control header, plus child fields.
///
/// A completed row (per `is_completed`, gated on `collapse_active`) always
/// renders its summary control, in both the collapsed and expanded state —
/// only `array-item-fields` toggles, so the move/remove header and the way
/// back to the fields stay reachable either way.
fn render_array_item(
  ctx: FieldRenderCtx,
  removable: Bool,
  orderable: Bool,
  count: Int,
  item: Value,
  index: Int,
  collapse: array_collapse.CollapseOptions,
  collapse_active: Bool,
  incomplete: set.Set(Int),
  model: FormModel,
  render_child: fn(FieldRenderCtx, FormModel) -> Element(FormMsg),
) -> Element(FormMsg) {
  case ctx.property.items {
    Some(item_schema) -> {
      let row_path = list.append(ctx.path, [path.ArraySegment(index)])
      let is_completed =
        collapse_active
        && array_collapse.is_completed(model, ctx.path, index, item, incomplete)
      let is_collapsed =
        is_completed && !list.contains(model.array_rows_expanded, row_path)
      let summary = case is_completed {
        True -> [
          render_item_summary(
            row_path,
            item_schema,
            item,
            collapse.summary_fields,
            model,
          ),
        ]
        False -> []
      }
      let body = case is_collapsed {
        True -> []
        False -> [
          html.div(
            [
              class("array-item-fields"),
              attribute.attribute("part", "array-item-fields"),
            ],
            render_item_fields(
              ctx,
              item_schema,
              item,
              index,
              model,
              render_child,
            ),
          ),
        ]
      }
      html.div(
        [
          class("array-item"),
          attribute.attribute("part", "array-item"),
          attribute.attribute("data-collapsed", bool.to_string(is_collapsed)),
        ],
        list.flatten([
          summary,
          [render_array_item_header(ctx, removable, orderable, count, index)],
          body,
        ]),
      )
    }
    None -> element.none()
  }
}

/// The summary line — a real button, so it is focusable and keyboard-operable.
/// Rendered for a completed row in BOTH states: collapsing hides only the
/// fields, so the control that reopens the row never disappears.
fn render_item_summary(
  row_path: path.FieldPath,
  item_schema: SchemaProperty,
  item: Value,
  fields: List(String),
  model: FormModel,
) -> Element(FormMsg) {
  let values =
    array_collapse.summary_values(
      model.ui_schema,
      row_path,
      item_schema,
      item,
      model.selected_branches,
      fields,
    )
  let expanded = list.contains(model.array_rows_expanded, row_path)
  html.button(
    [
      type_("button"),
      class("array-item-summary"),
      attribute.attribute("part", "array-item-summary"),
      attribute.attribute("aria-expanded", bool.to_string(expanded)),
      event.on_click(model.array_msg(ToggleRowExpanded(row_path))),
    ],
    list.index_map(values, fn(text, i) { summary_span(text, i) })
      |> list.flatten,
  )
}

/// A literal separator between values, so the line reads correctly with no
/// stylesheet applied.
fn summary_span(text: String, index: Int) -> List(Element(FormMsg)) {
  let value =
    html.span([attribute.attribute("part", "array-item-summary-value")], [
      html.text(text),
    ])
  case index {
    0 -> [value]
    _ -> [
      html.span([attribute.attribute("part", "array-item-summary-sep")], [
        html.text(" · "),
      ]),
      value,
    ]
  }
}

/// Per-row control header: move up/down (when orderable and the array has
/// more than one row) followed by remove (when removable). Renders nothing
/// in readonly mode or when no control applies.
fn render_array_item_header(
  ctx: FieldRenderCtx,
  removable: Bool,
  orderable: Bool,
  count: Int,
  index: Int,
) -> Element(FormMsg) {
  let move_buttons = case orderable && count > 1 {
    True -> [
      html.button(
        [
          type_("button"),
          class("move-array-item-up"),
          disabled(index == 0),
          event.on_click(MoveArrayItemPath(ctx.path, index, index - 1)),
        ],
        [html.text("▲")],
      ),
      html.button(
        [
          type_("button"),
          class("move-array-item-down"),
          disabled(index == count - 1),
          event.on_click(MoveArrayItemPath(ctx.path, index, index + 1)),
        ],
        [html.text("▼")],
      ),
    ]
    False -> []
  }
  let remove_button = case removable {
    True -> [
      html.button(
        [
          type_("button"),
          class("remove-array-item"),
          event.on_click(RemoveArrayItemPath(ctx.path, index)),
        ],
        [html.text("Удалить")],
      ),
    ]
    False -> []
  }
  let controls = list.append(move_buttons, remove_button)
  use <- bool.guard(ctx.is_readonly || list.is_empty(controls), element.none())
  html.div([class("array-item-header")], controls)
}

/// Render every child field of a single row.
///
/// Resolves the item schema against the row's own values — active union
/// branch first, then item-level `if/then/else` rules (design D4) — then
/// dispatches every visible property through `render_child`. `is_disabled`
/// is inherited as-is from the array container; `is_readonly` is
/// OR-inherited with each child's own `read_only`.
fn render_item_fields(
  ctx: FieldRenderCtx,
  item_schema: SchemaProperty,
  item: Value,
  index: Int,
  model: FormModel,
  render_child: fn(FieldRenderCtx, FormModel) -> Element(FormMsg),
) -> List(Element(FormMsg)) {
  let item_path = list.append(ctx.path, [path.ArraySegment(index)])
  let resolved =
    union_resolver.resolve_effective_property(
      item_schema,
      item,
      item_path,
      model.selected_branches,
    )

  // For array items, the row order is controlled by the array's `items`
  // template, looked up via the row's path.
  let item_hints =
    ui_resolver.resolve_hints(model.ui_schema, item_path, item_schema)
  case resolved.properties {
    Some(props) ->
      properties.apply_order(props, item_hints.order)
      |> list.map(fn(entry) {
        let #(child_name, child_prop) = entry
        let child_path =
          list.append(item_path, [path.PropertySegment(child_name)])
        let child_ctx =
          field_common.make_child_ctx(
            parent: ctx,
            model: model,
            path: child_path,
            property: child_prop,
            is_required: list.contains(resolved.required, child_name),
          )
        render_child(child_ctx, model)
      })
    None -> []
  }
}
