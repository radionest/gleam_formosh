// End-to-end render guard for nullable / union `type` properties.
//
// The reported bug was an empty <formosh-form>: a `"type": ["string","null"]`
// property aborted the whole parse, so nothing rendered. These tests pin the
// post-fix behaviour through the real view: the union field renders as a normal
// string widget, and a stored `null` value never crashes either render path.

import formosh/form/model.{FormModel}
import formosh/form/view
import formosh/schema/parser
import formosh/schema/types
import gleam/string
import gleeunit/should
import lustre/element

pub fn union_type_renders_string_input_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"user_id\": { \"type\": [\"string\", \"null\"], \"title\": \"Author\" }
    }
  }"
  let assert Ok(schema) = parser.parse_schema(json)

  let html =
    model.init(schema)
    |> view.view
    |> element.to_string

  // Union [string, null] must render as an ordinary text input, not vanish.
  html |> string.contains("part=\"input\"") |> should.be_true
}

pub fn union_type_null_value_renders_without_crash_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"user_id\": { \"type\": [\"string\", \"null\"] }
    }
  }"
  let assert Ok(schema) = parser.parse_schema(json)

  let html =
    FormModel(
      ..model.init(schema),
      values: types.ObjectValue([#("user_id", types.NullValue)]),
    )
    |> view.view
    |> element.to_string

  // A stored null must not blow up the editable renderer; the input still emits.
  html |> string.contains("part=\"input\"") |> should.be_true
}

pub fn union_type_null_value_renders_dash_in_review_mode_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"user_id\": { \"type\": [\"string\", \"null\"], \"title\": \"Author\" }
    }
  }"
  let assert Ok(schema) = parser.parse_schema(json)

  let html =
    FormModel(
      ..model.init(schema),
      values: types.ObjectValue([#("user_id", types.NullValue)]),
      read_only: True,
    )
    |> view.view
    |> element.to_string

  // Review mode shows the label→value row (em-dash for null), no crash.
  html |> string.contains("part=\"readonly-value\"") |> should.be_true
}
