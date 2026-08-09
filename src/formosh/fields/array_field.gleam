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
  // `is_completed` -> `has_errors_under_path` walks the whole error map per
  // row, so each row's flag is computed exactly once here and reused below
  // for both the header count and that row's own render, rather than paying
  // for the scan twice per row. Gated on `collapse_available` alone (not
  // `collapse_active`) so the header keeps reporting a count while the user
  // has collapsing switched off, and so this stays a no-op when collapsing
  // isn't available at all — mirrors the `incomplete` guard just above.
  let row_completed = case collapse_available {
    True ->
      list.index_map(items, fn(item, index) {
        array_collapse.is_completed(model, ctx.path, index, item, incomplete)
      })
    False -> list.map(items, fn(_) { False })
  }
  let completed_count =
    list.fold(row_completed, 0, fn(acc, item_completed) {
      case item_completed {
        True -> acc + 1
        False -> acc
      }
    })

  html.div([class("array-field"), attribute.attribute("part", "array-field")], [
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
      [class("array-items"), attribute.attribute("part", "array-items")],
      list.index_map(list.zip(items, row_completed), fn(pair, index) {
        let #(item, item_completed) = pair
        render_array_item(
          ctx,
          removable,
          orderable,
          count,
          item,
          index,
          collapse,
          collapse_available,
          collapse_active,
          item_completed,
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
            attribute.attribute("part", "array-add"),
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
  html.div(
    [
      class("array-collapse-header"),
      attribute.attribute("part", "array-collapse-header"),
    ],
    [
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
    ],
  )
}

/// Render a single row: optional control header, plus child fields.
///
/// A completed row (per `is_completed`, gated on `collapse_active`) always
/// renders its summary control, in both the collapsed and expanded state —
/// only the row body folds, so the move/remove header and the way back to
/// the fields stay reachable either way.
fn render_array_item(
  ctx: FieldRenderCtx,
  removable: Bool,
  orderable: Bool,
  count: Int,
  item: Value,
  index: Int,
  collapse: array_collapse.CollapseOptions,
  collapse_available: Bool,
  collapse_active: Bool,
  row_completed: Bool,
  model: FormModel,
  render_child: fn(FieldRenderCtx, FormModel) -> Element(FormMsg),
) -> Element(FormMsg) {
  case ctx.property.items {
    Some(item_schema) -> {
      let row_path = list.append(ctx.path, [path.ArraySegment(index)])
      let is_completed = collapse_active && row_completed
      // Computed once and reused below (`is_collapsed` and the summary's
      // own `aria-expanded`) instead of re-deriving the same
      // `list.contains` scan a second time inside `render_item_summary`.
      let expanded = list.contains(model.array_rows_expanded, row_path)
      let is_collapsed = is_completed && !expanded
      // Occupies its slot in every state — `element.none()` renders as an
      // empty text node, so the markup is unchanged, but the row's children
      // keep a stable length. They are unkeyed: a summary that appeared only
      // once the row completed would shift the header and the body down one
      // index, and a positional diff would then rebuild the body from
      // scratch. A freshly created element already at `0fr` has no previous
      // computed value to transition from, so the automatic fold would snap
      // shut — and the row's inputs would be torn down mid-edit.
      let summary = case is_completed {
        True ->
          render_item_summary(
            row_path,
            item_schema,
            item,
            collapse.summary_fields,
            model,
            expanded,
          )
        False -> element.none()
      }
      let body =
        render_item_body(
          ctx,
          item_schema,
          item,
          index,
          collapse_available,
          is_collapsed,
          model,
          render_child,
        )
      // Presence-only, lowercase — matches the `data-error`/`data-readonly`
      // convention (`field_dispatcher.wrap_with_errors`) and `data-exiting`
      // (`swipe_review_field`): a bare `bool.to_string` would emit
      // `data-collapsed="False"` on every row even with collapsing off,
      // which is neither a valid presence selector nor consistent casing.
      let collapsed_attr = case is_collapsed {
        True -> [attribute.attribute("data-collapsed", "true")]
        False -> []
      }
      html.div(
        list.flatten([
          [class("array-item"), attribute.attribute("part", "array-item")],
          collapsed_attr,
        ]),
        [
          summary,
          render_array_item_header(ctx, removable, orderable, count, index),
          body,
        ],
      )
    }
    None -> element.none()
  }
}

/// The row's fields, plus — for a collapse-enabled array only — the wrapper
/// that folds them.
///
/// The wrapper is rendered for *every* row of such an array, collapsed or
/// not: an element that only appears once the row is already collapsed has
/// nothing to animate from. Because it persists, the single value that
/// changes between renders (`grid-template-rows`) transitions, in both
/// directions and for the automatic fold a row does the moment it becomes
/// completed.
///
/// Styles are inline for the same reason `swipe_review_field` puts its
/// fly-off transition inline: the library ships no stylesheet, and without
/// them a collapsed row would simply show its fields. Appearance stays with
/// the caller — this is only the folding mechanism. Duration is overridable
/// via `--formosh-collapse-duration`, everything else via `!important`
/// (author `!important` outranks inline styles), which is also how the
/// standard `prefers-reduced-motion` reset switches the fold off.
///
/// An array with no collapsing configured renders exactly as it did before
/// the feature existed: the bare fields container, no wrapper, no styles.
fn render_item_body(
  ctx: FieldRenderCtx,
  item_schema: SchemaProperty,
  item: Value,
  index: Int,
  collapse_available: Bool,
  is_collapsed: Bool,
  model: FormModel,
  render_child: fn(FieldRenderCtx, FormModel) -> Element(FormMsg),
) -> Element(FormMsg) {
  let fields_attrs = [
    class("array-item-fields"),
    attribute.attribute("part", "array-item-fields"),
  ]
  let children =
    render_item_fields(ctx, item_schema, item, index, model, render_child)

  use <- bool.guard(!collapse_available, html.div(fields_attrs, children))

  html.div(
    list.flatten([
      [
        class("array-item-body"),
        attribute.attribute("part", "array-item-body"),
        attribute.styles([
          #("display", "grid"),
          #("grid-template-rows", case is_collapsed {
            True -> "0fr"
            False -> "1fr"
          }),
          #("overflow", "hidden"),
          #(
            "transition",
            "grid-template-rows var(--formosh-collapse-duration, 180ms) ease",
          ),
        ]),
      ],
      // Keeps the folded fields out of the tab order and off assistive
      // tech — they stay in the DOM so the fold has something to animate,
      // but a collapsed row must not be reachable as if it were open.
      case is_collapsed {
        True -> [attribute.attribute("inert", "true")]
        False -> []
      },
    ]),
    [
      html.div(
        // A grid item's automatic minimum size would hold the `0fr` track
        // open at its content height. Zeroing it here rather than clipping
        // (`overflow: hidden`, which the wrapper does) leaves the part the
        // caller actually styles free of a visual side effect.
        list.append(fields_attrs, [attribute.styles([#("min-height", "0")])]),
        children,
      ),
    ],
  )
}

/// The summary line — a real button, so it is focusable and keyboard-operable.
/// Rendered for a completed row in BOTH states: collapsing folds only the
/// fields, so the control that reopens the row never disappears.
///
/// `expanded` is computed once by the caller (`render_array_item`, which
/// already needs the same `array_rows_expanded` lookup for `is_collapsed`)
/// and passed in rather than re-derived here.
fn render_item_summary(
  row_path: path.FieldPath,
  item_schema: SchemaProperty,
  item: Value,
  fields: List(String),
  model: FormModel,
  expanded: Bool,
) -> Element(FormMsg) {
  let values =
    array_collapse.summary_values(
      model.ui_schema,
      row_path,
      item_schema,
      item,
      model.selected_branches,
      fields,
      model.show_readonly_fields,
    )
  // `summary_values` can legitimately return `[]` (unknown names, `false`
  // booleans, blank strings all omitted) while the row is still
  // `is_completed` — completion only needs ONE non-blank field, and
  // `BooleanValue(False)` counts as non-blank. Without a fallback that
  // renders a zero-content `<button>`: no visible text, no accessible name,
  // and no way back into the row — the exact failure D1 exists to prevent.
  let spans = case values {
    [] -> [summary_fallback_span(row_path)]
    _ ->
      list.index_map(values, fn(text, i) { summary_span(text, i) })
      |> list.flatten
  }
  html.button(
    [
      type_("button"),
      class("array-item-summary"),
      attribute.attribute("part", "array-item-summary"),
      attribute.attribute("aria-expanded", case expanded {
        True -> "true"
        False -> "false"
      }),
      event.on_click(model.array_msg(ToggleRowExpanded(row_path))),
    ],
    spans,
  )
}

/// Fallback content for a completed row whose `summary_values` yields
/// nothing: the row's 1-based position, read off `row_path`'s own trailing
/// `ArraySegment` — keeps the button non-empty and its accessible name
/// non-empty either way.
fn summary_fallback_span(row_path: path.FieldPath) -> Element(FormMsg) {
  let index = case list.last(row_path) {
    Ok(path.ArraySegment(i)) -> i
    _ -> 0
  }
  html.span([attribute.attribute("part", "array-item-summary-value")], [
    html.text(int.to_string(index + 1)),
  ])
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
  html.div(
    [
      class("array-item-header"),
      attribute.attribute("part", "array-item-header"),
    ],
    controls,
  )
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
