import formosh/fields/swipe_review.{type Zone, Choice, GestureConfig, Zone}
import formosh/form/path.{PropertySegment}
import formosh/schema/types
import gleam/dict
import gleam/option.{None, Some}
import gleeunit/should

fn zone(name: String, answer: option.Option(String)) -> Zone {
  Zone(
    region_key: "r",
    region_title: "Region",
    path: [
      PropertySegment("zones"),
      PropertySegment("r"),
      PropertySegment(name),
    ],
    title: name,
    answer: answer,
  )
}

pub fn current_is_first_unanswered_test() {
  let zs = [zone("a", Some("positive")), zone("b", None), zone("c", None)]
  swipe_review.current(zs)
  |> should.equal(Some(zone("b", None)))
}

pub fn answered_count_test() {
  let zs = [
    zone("a", Some("positive")),
    zone("b", None),
    zone("c", Some("negative")),
  ]
  swipe_review.answered_count(zs) |> should.equal(2)
}

pub fn last_answered_path_test() {
  let zs = [
    zone("a", Some("positive")),
    zone("b", None),
    zone("c", Some("negative")),
  ]
  swipe_review.last_answered_path(zs)
  |> should.equal(
    Some([PropertySegment("zones"), PropertySegment("r"), PropertySegment("c")]),
  )
}

pub fn unanswered_paths_test() {
  let zs = [zone("a", Some("positive")), zone("b", None)]
  swipe_review.unanswered_paths(zs)
  |> should.equal([
    [PropertySegment("zones"), PropertySegment("r"), PropertySegment("b")],
  ])
}

pub fn gesture_config_defaults_when_empty_test() {
  let cfg = swipe_review.gesture_config(dict.new())
  cfg.button.code |> should.equal("inaccessible")
}

pub fn gesture_config_reads_options_test() {
  let options =
    dict.from_list([
      #(
        "swipeRight",
        types.ObjectValue([
          #("value", types.StringValue("positive")),
          #("label", types.StringValue("Карциноматоз")),
          #("tone", types.StringValue("danger")),
        ]),
      ),
    ])
  let cfg = swipe_review.gesture_config(options)
  cfg.right |> should.equal(Choice("positive", "Карциноматоз", "danger"))
}

pub fn label_for_test() {
  let cfg =
    GestureConfig(
      right: Choice("positive", "Карциноматоз", "danger"),
      left: Choice("negative", "Чисто", "ok"),
      button: Choice("inaccessible", "Недоступна", "muted"),
    )
  swipe_review.label_for(cfg, "negative") |> should.equal("Чисто")
}
