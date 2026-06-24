//// Burndown renderer for the swipe-review widget — a shrinking "sheet": every
//// still-unanswered zone is shown at once, grouped by region, each row a
//// mini-card. Phase A: three large tap targets per row. Phase B: each row is
//// also draggable horizontally — drag right past threshold commits the
//// positive answer, left commits the negative; the tap targets remain a
//// fallback and «inaccessible» stays a button. Answering commits the row and,
//// in hide-answered mode, flies it off-screen — right for the positive answer,
//// left for the negative, a fade for the middle — before dropping it (any
//// order); a review summary replaces the sheet once every zone is answered,
//// including any card still mid-flight.
//// A "hide answered / show all" checkbox (rendered in every state) switches
//// between this shrinking sheet and a show-all view where every zone stays
//// visible and editable in place — the chosen answer is marked `data-selected`.

import formosh/fields/field_common.{type FieldRenderCtx}
import formosh/fields/swipe_review.{type Choice, type GestureConfig, type Zone}
import formosh/form/model.{
  type FormModel, type FormMsg, type SwipeDrag, ClearFieldPath,
}
import formosh/form/path
import formosh/form/widget_msg.{
  type ExitDir, AnswerZone, DragCancel, DragEnd, DragMove, DragStart, ExitDone,
  ExitFade, ExitLeft, ExitRight, FillRemaining, ToggleHideAnswered,
}
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/keyed
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
  let exiting = model.swipe_exiting
  let exiting_paths = list.map(exiting, fn(p) { p.0 })

  let body = case hide {
    // Hide answered: the shrinking sheet (still showing any card mid fly-off),
    // or the review summary once nothing is left — not even an exiting card.
    True ->
      case swipe_review.unanswered_or_exiting_by_region(zones, exiting_paths) {
        [] -> render_review(zones, config)
        groups ->
          render_sheet(
            groups,
            zones,
            config,
            answered,
            total,
            model.swipe_drag,
            exiting,
          )
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
        exiting,
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
  exiting: List(#(path.FieldPath, ExitDir)),
) -> Element(FormMsg) {
  html.div([attribute.attribute("part", "swipe-sheet")], [
    render_progress(answered, total),
    html.div(
      [attribute.attribute("part", "swipe-regions")],
      list.map(groups, fn(group) {
        let #(region_title, region_zones) = group
        render_region(region_title, region_zones, config, drag, exiting)
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
  exiting: List(#(path.FieldPath, ExitDir)),
) -> Element(FormMsg) {
  html.div([attribute.attribute("part", "swipe-region-group")], [
    html.div([attribute.attribute("part", "swipe-region")], [
      html.text(region_title),
    ]),
    // Keyed by path so removing a finished fly-off drops THAT row, instead of
    // Lustre reusing its node for the next zone (which looked like a spring-back).
    keyed.div(
      [attribute.attribute("part", "swipe-zones")],
      list.map(region_zones, fn(zone) {
        #(
          path.to_string(zone.path),
          render_zone_row(zone, config, drag, exiting),
        )
      }),
    ),
  ])
}

/// One zone row. An idle row carries a `pointerdown` that can begin a drag;
/// the row being dragged also gets the live `translateX` offset and the
/// move/up/cancel handlers. A committed row that is still flying off (`exiting`)
/// gets the off-screen transform plus a `transitionend` that finally drops it,
/// and is made inert (`pointer-events:none`) so neither swipe nor tap fires.
fn render_zone_row(
  zone: Zone,
  config: GestureConfig,
  drag: Option(SwipeDrag),
  exiting: List(#(path.FieldPath, ExitDir)),
) -> Element(FormMsg) {
  let exit_dir = list.key_find(exiting, zone.path) |> option.from_result()

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
  ]

  let attrs = case exit_dir, dragging_dx {
    // Committed, flying off: no drag/tap handlers; pointer-events:none makes the
    // whole row (its buttons included) inert until `transitionend` removes it.
    Some(dir), _ ->
      list.append(base, [
        attribute.attribute("data-exiting", "true"),
        attribute.styles([
          #("transform", exit_transform(dir)),
          #("opacity", "0"),
          #("transition", "transform 0.18s ease, opacity 0.18s ease"),
          #("pointer-events", "none"),
        ]),
        event.on(
          "transitionend",
          decode.success(model.swipe_msg(ExitDone(zone.path))),
        ),
      ])
    // Actively dragging THIS row: live offset + drag lifecycle handlers.
    None, Some(dx) ->
      list.append([on_pointer_down(zone, config), ..base], [
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
    // Idle row: only the pointerdown that can start a drag.
    None, None -> [on_pointer_down(zone, config), ..base]
  }

  html.div(attrs, [
    html.div([attribute.attribute("part", "swipe-zone-title")], [
      html.text(zone.title),
    ]),
    html.div([attribute.attribute("part", "swipe-choices")], [
      choice_button(zone, config.left, ExitLeft),
      choice_button(zone, config.button, ExitFade),
      choice_button(zone, config.right, ExitRight),
    ]),
  ])
}

/// Off-screen transform for a flying-off card: slide out to the answered side,
/// or just fade in place for the neutral middle choice.
fn exit_transform(dir: ExitDir) -> String {
  case dir {
    ExitRight -> "translateX(120%)"
    ExitLeft -> "translateX(-120%)"
    ExitFade -> "none"
  }
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

fn choice_button(zone: Zone, choice: Choice, dir: ExitDir) -> Element(FormMsg) {
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
      event.on_click(model.swipe_msg(AnswerZone(zone.path, choice.code, dir))),
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
