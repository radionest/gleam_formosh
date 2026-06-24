//// Burndown renderer for the swipe-review widget — a shrinking "sheet": every
//// still-unanswered zone is shown at once, grouped by region, each row a
//// mini-card. Phase A: three large tap targets per row. Phase B: each row is
//// also draggable horizontally — drag right past threshold commits the
//// positive answer, left commits the negative; the tap targets remain a
//// fallback and «inaccessible» stays a button. Answering removes the row (any
//// order); a review summary replaces the sheet once every zone is answered.
//// A "hide answered / show all" checkbox (rendered in every state) switches
//// between this shrinking sheet and a show-all view where every zone stays
//// visible and editable in place — the chosen answer is marked `data-selected`.

import formosh/fields/field_common.{type FieldRenderCtx}
import formosh/fields/swipe_review.{type Choice, type GestureConfig, type Zone}
import formosh/form/model.{
  type FormModel, type FormMsg, type SwipeDrag, ClearFieldPath, UpdateFieldPath,
}
import formosh/form/widget_msg.{
  DragCancel, DragEnd, DragMove, DragStart, FillRemaining, ToggleHideAnswered,
}
import formosh/schema/types
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// Horizontal travel (px) a row must pass for a release to commit an answer.
const swipe_threshold = 80.0

pub fn render(ctx: FieldRenderCtx, model: FormModel) -> Element(FormMsg) {
  let config = swipe_review.gesture_config(ctx.hints.options)
  let toggle_label = swipe_review.hide_answered_label(ctx.hints.options)
  let zones = swipe_review.zones(ctx.path, ctx.property, model)
  let total = list.length(zones)
  let answered = swipe_review.answered_count(zones)
  let hide = model.swipe_hide_answered

  let body = case hide {
    // Hide answered: the shrinking sheet, or the review summary once empty.
    True ->
      case swipe_review.unanswered_by_region(zones) {
        [] -> render_review(zones, config)
        groups ->
          render_sheet(groups, zones, config, answered, total, model.swipe_drag)
      }
    // Show all: every zone stays visible and editable; no review summary.
    False ->
      render_sheet(
        swipe_review.all_by_region(zones),
        zones,
        config,
        answered,
        total,
        model.swipe_drag,
      )
  }

  // The view toggle sits above the body so it is reachable in every state
  // (shrinking sheet, show-all, and the review summary).
  html.div(
    [
      attribute.class("formosh-swipe-review"),
      attribute.attribute("part", "swipe-review"),
    ],
    [render_view_toggle(hide, toggle_label), body],
  )
}

/// The shrinking sheet: progress, then every region that still has unanswered
/// zones (each zone a row of three tap targets), then the foot controls.
fn render_sheet(
  groups: List(#(String, List(Zone))),
  zones: List(Zone),
  config: GestureConfig,
  answered: Int,
  total: Int,
  drag: Option(SwipeDrag),
) -> Element(FormMsg) {
  html.div([attribute.attribute("part", "swipe-sheet")], [
    render_progress(answered, total),
    html.div(
      [attribute.attribute("part", "swipe-regions")],
      list.map(groups, fn(group) {
        let #(region_title, region_zones) = group
        render_region(region_title, region_zones, config, drag)
      }),
    ),
    render_controls(zones, config),
  ])
}

/// The "hide answered / show all" checkbox. Checked = answered zones are
/// hidden (the shrinking sheet); unchecked = every zone stays visible.
fn render_view_toggle(hide_answered: Bool, label: String) -> Element(FormMsg) {
  html.label([attribute.attribute("part", "swipe-toggle")], [
    html.input([
      attribute.type_("checkbox"),
      attribute.checked(hide_answered),
      event.on_click(model.swipe_msg(ToggleHideAnswered)),
    ]),
    html.text(label),
  ])
}

fn render_region(
  region_title: String,
  region_zones: List(Zone),
  config: GestureConfig,
  drag: Option(SwipeDrag),
) -> Element(FormMsg) {
  html.div([attribute.attribute("part", "swipe-region-group")], [
    html.div([attribute.attribute("part", "swipe-region")], [
      html.text(region_title),
    ]),
    html.div(
      [attribute.attribute("part", "swipe-zones")],
      list.map(region_zones, fn(zone) { render_zone_row(zone, config, drag) }),
    ),
  ])
}

/// One zone row. It always carries a `pointerdown` handler that begins a drag;
/// while THIS row is the one being dragged it also gets the live `translateX`
/// offset plus the move/up/cancel handlers. The three tap buttons remain a
/// fallback for non-swipe input.
fn render_zone_row(
  zone: Zone,
  config: GestureConfig,
  drag: Option(SwipeDrag),
) -> Element(FormMsg) {
  let dragging_dx = case drag {
    Some(d) ->
      case d.path == zone.path {
        True -> Some(d.dx)
        False -> None
      }
    None -> None
  }

  let base = [
    attribute.attribute("part", "swipe-row"),
    attribute.attribute("data-swipe-row", "true"),
    on_pointer_down(zone, config),
  ]

  let attrs = case dragging_dx {
    Some(dx) ->
      list.append(base, [
        attribute.styles([
          #("transform", "translateX(" <> float.to_string(dx) <> "px)"),
          #("transition", "none"),
        ]),
        event.on("pointermove", {
          decode.at(["clientX"], decode.float)
          |> decode.map(fn(x) { model.swipe_msg(DragMove(x)) })
        }),
        event.on("pointerup", decode.success(model.swipe_msg(DragEnd))),
        event.on("pointercancel", decode.success(model.swipe_msg(DragCancel))),
        event.on("pointerleave", decode.success(model.swipe_msg(DragCancel))),
      ])
    None -> base
  }

  html.div(attrs, [
    html.div([attribute.attribute("part", "swipe-zone-title")], [
      html.text(zone.title),
    ]),
    html.div([attribute.attribute("part", "swipe-choices")], [
      choice_button(zone, config.left),
      choice_button(zone, config.button),
      choice_button(zone, config.right),
    ]),
  ])
}

fn on_pointer_down(
  zone: Zone,
  config: GestureConfig,
) -> attribute.Attribute(FormMsg) {
  event.on("pointerdown", {
    decode.at(["clientX"], decode.float)
    |> decode.map(fn(x) {
      model.swipe_msg(DragStart(
        zone.path,
        x,
        config.right.code,
        config.left.code,
        swipe_threshold,
      ))
    })
  })
}

fn choice_button(zone: Zone, choice: Choice) -> Element(FormMsg) {
  let selected = case zone.answer {
    Some(code) -> code == choice.code
    None -> False
  }
  html.button(
    [
      attribute.type_("button"),
      attribute.class("formosh-swipe-choice"),
      attribute.attribute("part", "swipe-choice"),
      attribute.attribute("data-tone", choice.tone),
      attribute.attribute("data-selected", case selected {
        True -> "true"
        False -> "false"
      }),
      event.on_click(UpdateFieldPath(zone.path, types.StringValue(choice.code))),
    ],
    [html.text(choice.label)],
  )
}

fn render_progress(answered: Int, total: Int) -> Element(FormMsg) {
  html.div(
    [
      attribute.class("formosh-swipe-progress"),
      attribute.attribute("part", "swipe-progress"),
    ],
    [html.text(int.to_string(answered) <> " / " <> int.to_string(total))],
  )
}

fn render_controls(zones: List(Zone), config: GestureConfig) -> Element(FormMsg) {
  let undo = case swipe_review.last_answered_path(zones) {
    Some(p) ->
      html.button(
        [
          attribute.type_("button"),
          attribute.class("formosh-swipe-undo"),
          attribute.attribute("part", "swipe-undo"),
          event.on_click(ClearFieldPath(p)),
        ],
        [html.text("← Назад")],
      )
    None -> element.none()
  }
  let fill_remaining =
    html.button(
      [
        attribute.type_("button"),
        attribute.class("formosh-swipe-fill"),
        attribute.attribute("part", "swipe-fill"),
        event.on_click(
          model.swipe_msg(FillRemaining(
            swipe_review.unanswered_paths(zones),
            config.button.code,
          )),
        ),
      ],
      [html.text("Отметить оставшиеся как «" <> config.button.label <> "»")],
    )
  html.div([attribute.attribute("part", "swipe-controls")], [
    undo,
    fill_remaining,
  ])
}

fn render_review(zones: List(Zone), config: GestureConfig) -> Element(FormMsg) {
  html.div([attribute.attribute("part", "swipe-review-summary")], [
    html.div([attribute.attribute("part", "swipe-review-title")], [
      html.text("Все зоны просмотрены"),
    ]),
    html.div(
      [attribute.attribute("part", "swipe-review-list")],
      list.map(zones, fn(zone) { render_review_row(zone, config) }),
    ),
  ])
}

fn render_review_row(zone: Zone, config: GestureConfig) -> Element(FormMsg) {
  let answer_label = case zone.answer {
    Some(code) -> swipe_review.label_for(config, code)
    None -> "—"
  }
  html.button(
    [
      attribute.type_("button"),
      attribute.class("formosh-swipe-review-row"),
      attribute.attribute("part", "swipe-review-row"),
      // Tap a row to re-open that zone for correction.
      event.on_click(ClearFieldPath(zone.path)),
    ],
    [
      html.span([attribute.attribute("part", "swipe-review-zone")], [
        html.text(zone.title),
      ]),
      html.span([attribute.attribute("part", "swipe-review-answer")], [
        html.text(answer_label),
      ]),
    ],
  )
}
