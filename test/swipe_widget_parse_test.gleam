import formosh/schema/types.{SwipeReviewWidget}
import formosh/schema/ui_parser
import gleam/list
import gleam/option.{Some}
import gleeunit/should

pub fn parse_swipe_review_widget_test() {
  let assert Ok(ui) =
    ui_parser.parse("{\"zones\":{\"ui:widget\":\"swipe-review\"}}")
  let assert Ok(prop) = list.key_find(ui.properties, "zones")
  prop.widget |> should.equal(Some(SwipeReviewWidget))
}
