import formosh/form/model
import formosh/form/path.{PropertySegment, get_at_path}
import formosh/form/update
import formosh/form/widget_msg.{
  AnswerZone, DragEnd, DragMove, DragStart, ExitDone, ExitLeft, ExitRight,
  ToggleHideAnswered,
}
import formosh/schema/parser
import formosh/schema/types
import gleam/option.{Some}
import gleeunit/should

const schema_json = "{\"type\":\"object\",\"properties\":{\"zones\":{\"type\":\"object\",\"properties\":{\"r\":{\"type\":\"object\",\"properties\":{\"a\":{\"type\":\"string\",\"enum\":[\"positive\",\"negative\",\"inaccessible\"]},\"b\":{\"type\":\"string\",\"enum\":[\"positive\",\"negative\",\"inaccessible\"]}}}}}}}"

const path_a = [
  PropertySegment("zones"),
  PropertySegment("r"),
  PropertySegment("a"),
]

const path_b = [
  PropertySegment("zones"),
  PropertySegment("r"),
  PropertySegment("b"),
]

fn fresh() -> model.FormModel {
  let assert Ok(schema) = parser.parse_schema(schema_json)
  model.init(schema)
}

fn dragged(move_x: Float) -> model.FormModel {
  let #(m1, _) =
    update.update(
      fresh(),
      model.swipe_msg(DragStart(path_a, 0.0, "positive", "negative", 80.0)),
    )
  let #(m2, _) = update.update(m1, model.swipe_msg(DragMove(move_x)))
  let #(m3, _) = update.update(m2, model.swipe_msg(DragEnd))
  m3
}

pub fn answer_zone_hide_commits_and_marks_exiting_test() {
  let #(m, _) =
    update.update(
      fresh(),
      model.swipe_msg(AnswerZone(path_a, "positive", ExitRight)),
    )
  get_at_path(m.values, path_a)
  |> should.equal(Some(types.StringValue("positive")))
  m.swipe_exiting |> should.equal([#(path_a, ExitRight)])
}

pub fn answer_zone_show_all_commits_without_exiting_test() {
  let #(m0, _) = update.update(fresh(), model.swipe_msg(ToggleHideAnswered))
  let #(m, _) =
    update.update(
      m0,
      model.swipe_msg(AnswerZone(path_a, "positive", ExitRight)),
    )
  get_at_path(m.values, path_a)
  |> should.equal(Some(types.StringValue("positive")))
  m.swipe_exiting |> should.equal([])
}

pub fn swipe_right_marks_exiting_right_test() {
  let m = dragged(100.0)
  m.swipe_exiting |> should.equal([#(path_a, ExitRight)])
}

pub fn swipe_left_marks_exiting_left_test() {
  let m = dragged(-100.0)
  m.swipe_exiting |> should.equal([#(path_a, ExitLeft)])
}

pub fn swipe_below_threshold_marks_no_exiting_test() {
  let m = dragged(20.0)
  m.swipe_exiting |> should.equal([])
}

pub fn exit_done_removes_only_named_card_test() {
  let #(m1, _) =
    update.update(
      fresh(),
      model.swipe_msg(AnswerZone(path_a, "positive", ExitRight)),
    )
  let #(m2, _) =
    update.update(m1, model.swipe_msg(AnswerZone(path_b, "negative", ExitLeft)))
  let #(m3, _) = update.update(m2, model.swipe_msg(ExitDone(path_a)))
  m3.swipe_exiting |> should.equal([#(path_b, ExitLeft)])
}

pub fn exit_done_unknown_path_is_noop_test() {
  let #(m1, _) =
    update.update(
      fresh(),
      model.swipe_msg(AnswerZone(path_b, "negative", ExitLeft)),
    )
  let #(m2, _) = update.update(m1, model.swipe_msg(ExitDone(path_a)))
  m2.swipe_exiting |> should.equal([#(path_b, ExitLeft)])
}

pub fn toggle_clears_exiting_test() {
  let #(m1, _) =
    update.update(
      fresh(),
      model.swipe_msg(AnswerZone(path_a, "positive", ExitRight)),
    )
  let #(m2, _) = update.update(m1, model.swipe_msg(ToggleHideAnswered))
  m2.swipe_exiting |> should.equal([])
}

pub fn clear_field_cancels_exiting_test() {
  // Undo / re-open within the fly-off window must cancel the exit, not leave
  // the card stuck in `swipe_exiting`.
  let #(m1, _) =
    update.update(
      fresh(),
      model.swipe_msg(AnswerZone(path_a, "positive", ExitRight)),
    )
  let #(m2, _) = update.update(m1, model.ClearFieldPath(path_a))
  m2.swipe_exiting |> should.equal([])
}
