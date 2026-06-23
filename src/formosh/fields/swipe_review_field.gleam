//// Tap-based burndown renderer for the swipe-review widget. Phase A: a
//// shrinking "sheet" — every still-unanswered zone is shown at once, grouped
//// by region, each with three large tap targets (touch-friendly). Answering a
//// zone removes it from the sheet (any order); progress, undo, and bulk-finish
//// sit at the foot, and a review summary replaces the sheet once every zone is
//// answered. Phase B adds swipe gestures + animation on top of this same view.

import formosh/fields/field_common.{type FieldRenderCtx}
import formosh/fields/swipe_review.{type Choice, type GestureConfig, type Zone}
import formosh/form/model.{
  type FormModel, type FormMsg, ClearFieldPath, UpdateFieldPath,
}
import formosh/form/widget_msg.{FillRemaining}
import formosh/schema/types
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub fn render(ctx: FieldRenderCtx, model: FormModel) -> Element(FormMsg) {
  let config = swipe_review.gesture_config(ctx.hints.options)
  let zones = swipe_review.zones(ctx.path, ctx.property, model)
  let total = list.length(zones)
  let answered = swipe_review.answered_count(zones)

  let body = case swipe_review.unanswered_by_region(zones) {
    [] -> render_review(zones, config)
    groups -> render_sheet(groups, zones, config, answered, total)
  }

  html.div(
    [
      attribute.class("formosh-swipe-review"),
      attribute.attribute("part", "swipe-review"),
    ],
    [body],
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
) -> Element(FormMsg) {
  html.div([attribute.attribute("part", "swipe-sheet")], [
    render_progress(answered, total),
    html.div(
      [attribute.attribute("part", "swipe-regions")],
      list.map(groups, fn(group) {
        let #(region_title, region_zones) = group
        render_region(region_title, region_zones, config)
      }),
    ),
    render_controls(zones, config),
  ])
}

fn render_region(
  region_title: String,
  region_zones: List(Zone),
  config: GestureConfig,
) -> Element(FormMsg) {
  html.div([attribute.attribute("part", "swipe-region-group")], [
    html.div([attribute.attribute("part", "swipe-region")], [
      html.text(region_title),
    ]),
    html.div(
      [attribute.attribute("part", "swipe-zones")],
      list.map(region_zones, fn(zone) { render_zone_row(zone, config) }),
    ),
  ])
}

fn render_zone_row(zone: Zone, config: GestureConfig) -> Element(FormMsg) {
  html.div([attribute.attribute("part", "swipe-row")], [
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

fn choice_button(zone: Zone, choice: Choice) -> Element(FormMsg) {
  html.button(
    [
      attribute.type_("button"),
      attribute.class("formosh-swipe-choice"),
      attribute.attribute("part", "swipe-choice"),
      attribute.attribute("data-tone", choice.tone),
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
