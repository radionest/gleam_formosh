import formosh/form/path.{PropertySegment}
import formosh/schema/types
import formosh/schema/ui_parser
import formosh/schema/ui_resolver
import gleam/dict
import gleeunit/should

pub fn ui_options_reach_render_hints_test() {
  let assert Ok(ui) =
    ui_parser.parse(
      "{\"zones\":{\"ui:widget\":\"swipe-review\",\"ui:options\":{\"swipeRight\":{\"value\":\"positive\"}}}}",
    )
  let hints =
    ui_resolver.resolve_hints(
      ui,
      [PropertySegment("zones")],
      types.empty_property(),
    )
  dict.get(hints.options, "swipeRight")
  |> should.equal(
    Ok(types.ObjectValue([#("value", types.StringValue("positive"))])),
  )
}
