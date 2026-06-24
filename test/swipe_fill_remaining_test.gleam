import formosh/form/model
import formosh/form/path.{PropertySegment, get_at_path}
import formosh/form/update
import formosh/form/widget_msg.{FillRemaining}
import formosh/schema/parser
import formosh/schema/types
import gleam/option.{Some}
import gleeunit/should

const schema_json = "{\"type\":\"object\",\"properties\":{\"zones\":{\"type\":\"object\",\"properties\":{\"r\":{\"type\":\"object\",\"properties\":{\"a\":{\"type\":\"string\",\"enum\":[\"positive\",\"negative\",\"inaccessible\"]},\"b\":{\"type\":\"string\",\"enum\":[\"positive\",\"negative\",\"inaccessible\"]}}}}}}}"

pub fn fill_remaining_sets_all_paths_test() {
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let m = model.init(schema)
  let path_a = [
    PropertySegment("zones"),
    PropertySegment("r"),
    PropertySegment("a"),
  ]
  let path_b = [
    PropertySegment("zones"),
    PropertySegment("r"),
    PropertySegment("b"),
  ]
  let #(m2, _) =
    update.update(
      m,
      model.swipe_msg(FillRemaining([path_a, path_b], "inaccessible")),
    )
  get_at_path(m2.values, path_a)
  |> should.equal(Some(types.StringValue("inaccessible")))
  get_at_path(m2.values, path_b)
  |> should.equal(Some(types.StringValue("inaccessible")))
}
