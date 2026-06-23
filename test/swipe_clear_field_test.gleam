import formosh/form/model.{ClearFieldPath, UpdateFieldPath}
import formosh/form/path.{PropertySegment, get_at_path}
import formosh/form/update
import formosh/schema/parser
import formosh/schema/types
import gleam/option.{None, Some}
import gleeunit/should

const schema_json = "{\"type\":\"object\",\"properties\":{\"zones\":{\"type\":\"object\",\"properties\":{\"r\":{\"type\":\"object\",\"properties\":{\"a\":{\"type\":\"string\",\"enum\":[\"positive\",\"negative\",\"inaccessible\"]}}}}}}}"

pub fn clear_field_removes_key_test() {
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let m = model.init(schema)
  let path_a = [
    PropertySegment("zones"),
    PropertySegment("r"),
    PropertySegment("a"),
  ]

  // Set a value first
  let #(m2, _) =
    update.update(m, UpdateFieldPath(path_a, types.StringValue("positive")))
  get_at_path(m2.values, path_a)
  |> should.equal(Some(types.StringValue("positive")))

  // Clear it — key must be absent (None), NOT Some(NullValue)
  let #(m3, _) = update.update(m2, ClearFieldPath(path_a))
  get_at_path(m3.values, path_a)
  |> should.equal(None)
}
