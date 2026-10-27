//// `json_string_to_values` reports the same typed `ParseError` as every
//// other parse boundary (issue #82) — the pre-fix `Nil` left callers with
//// no way to tell invalid JSON from a decode failure.

import formosh/form/json_utils
import formosh/schema/types
import gleam/dict
import gleeunit/should

pub fn valid_object_decodes_test() {
  let assert Ok(values) =
    json_utils.json_string_to_values("{\"name\": \"Ada\", \"age\": 36}")
  dict.size(values) |> should.equal(2)
  dict.get(values, "name") |> should.equal(Ok(types.StringValue("Ada")))
}

pub fn malformed_json_yields_typed_error_test() {
  let assert Error(types.InvalidJson(_)) =
    json_utils.json_string_to_values("{ not json")
}

pub fn non_object_json_yields_typed_error_test() {
  // A top-level array is valid JSON but not an object — distinguishable
  // from a syntax error now.
  let assert Error(types.DecodingError(_)) =
    json_utils.json_string_to_values("[1, 2, 3]")
}
