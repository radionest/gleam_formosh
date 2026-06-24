import formosh/form/model
import formosh/form/path.{PropertySegment, get_at_path}
import formosh/form/update
import formosh/form/widget_msg.{DragEnd, DragMove, DragStart}
import formosh/schema/parser
import formosh/schema/types
import gleam/option.{None, Some}
import gleeunit/should

const schema_json = "{\"type\":\"object\",\"properties\":{\"zones\":{\"type\":\"object\",\"properties\":{\"r\":{\"type\":\"object\",\"properties\":{\"a\":{\"type\":\"string\",\"enum\":[\"positive\",\"negative\",\"inaccessible\"]}}}}}}}"

const path_a = [
  PropertySegment("zones"),
  PropertySegment("r"),
  PropertySegment("a"),
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

pub fn swipe_right_past_threshold_commits_positive_test() {
  let m = dragged(100.0)
  get_at_path(m.values, path_a)
  |> should.equal(Some(types.StringValue("positive")))
  m.swipe_drag |> should.equal(None)
}

pub fn swipe_left_past_threshold_commits_negative_test() {
  let m = dragged(-100.0)
  get_at_path(m.values, path_a)
  |> should.equal(Some(types.StringValue("negative")))
  m.swipe_drag |> should.equal(None)
}

pub fn swipe_below_threshold_does_not_commit_test() {
  let m = dragged(20.0)
  get_at_path(m.values, path_a) |> should.equal(None)
  m.swipe_drag |> should.equal(None)
}
