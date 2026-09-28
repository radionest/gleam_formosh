import formosh/form/model
import formosh/form/view
import formosh/form/visibility
import formosh/schema/parser
import formosh/schema/serializer
import formosh/schema/types
import formosh/schema/ui_parser
import formosh/schema/ui_schema
import gleam/json
import gleam/list
import gleam/set
import gleam/string
import gleeunit/should
import lustre/element

const leftover_schema = "{
  \"type\": \"object\",
  \"$defs\": {\"Secret\": {\"type\": \"string\", \"x-widget\": \"hidden\"}},
  \"properties\": {
    \"tenant\": {\"type\": \"string\", \"x-widget\": \"hidden\"},
    \"via_ref\": {\"$ref\": \"#/$defs/Secret\"},
    \"photo\": {\"type\": \"string\", \"x-widget\": \"image-upload\", \"x-accept\": \"image/png\", \"x-max-file-size\": 10},
    \"tags\": {\"type\": \"array\", \"items\": {\"type\": \"string\"}, \"default\": [\"a\", \"b\"], \"x-addable\": false, \"x-removable\": false}
  }
}"

pub fn leftover_x_widget_hides_nothing_test() {
  let assert Ok(schema) = parser.parse_schema(leftover_schema)
  visibility.invisible_paths(
    schema,
    ui_schema.empty_ui_schema(),
    types.ObjectValue([]),
    False,
  )
  |> should.equal(set.new())
}

pub fn leftover_x_addable_keeps_array_controls_test() {
  let assert Ok(schema) = parser.parse_schema(leftover_schema)
  let html = model.init(schema) |> view.view |> element.to_string
  html |> string.contains("add-array-item") |> should.be_true
  html |> string.contains("remove-array-item") |> should.be_true
}

pub fn ui_addable_false_hides_add_control_test() {
  let assert Ok(schema) = parser.parse_schema(leftover_schema)
  let assert Ok(ui) = ui_parser.parse("{\"tags\":{\"ui:addable\":false}}")
  model.FormModel(..model.init(schema), ui_schema: ui)
  |> view.view
  |> element.to_string
  |> string.contains("add-array-item")
  |> should.be_false
}

pub fn reserialized_schema_has_no_x_keys_test() {
  let assert Ok(schema) = parser.parse_schema(leftover_schema)
  let out = json.to_string(serializer.schema_to_json(schema))
  ["x-widget", "x-accept", "x-max-file-size", "x-addable", "x-removable"]
  |> list.each(fn(key) { string.contains(out, key) |> should.be_false })
}

pub fn retired_paths_cover_every_subschema_position_test() {
  parser.retired_extension_paths(
    "{
      \"x-widget\": \"hidden\",
      \"$defs\": {\"D\": {\"x-accept\": \"image/png\"}},
      \"properties\": {
        \"tenant\": {\"x-widget\": \"hidden\"},
        \"lesions\": {\"type\": \"array\", \"x-addable\": false, \"items\": {\"x-removable\": false}},
        \"u\": {\"anyOf\": [{\"type\": \"null\"}, {\"x-widget\": \"hidden\"}]},
        \"o\": {\"oneOf\": [{\"x-widget\": \"a\"}]},
        \"c\": {\"allOf\": [{\"x-max-file-size\": 1}]}
      },
      \"if\": {\"x-widget\": \"a\"},
      \"then\": {\"x-widget\": \"b\"},
      \"else\": {\"x-widget\": \"c\"}
    }",
  )
  |> should.equal([
    "#", "#/$defs/D", "#/properties/tenant", "#/properties/lesions",
    "#/properties/lesions/items", "#/properties/u/anyOf/1",
    "#/properties/o/oneOf/0", "#/properties/c/allOf/0", "#/if", "#/then",
    "#/else",
  ])
}

pub fn property_named_like_extension_is_not_flagged_test() {
  parser.retired_extension_paths(
    "{\"properties\": {\"x-widget\": {\"type\": \"string\"}}}",
  )
  |> should.equal([])
}

pub fn data_values_are_not_inspected_test() {
  parser.retired_extension_paths(
    "{\"properties\": {\"cfg\": {\"type\": \"object\", \"default\": {\"x-addable\": false}, \"enum\": [{\"x-widget\": 1}]}}}",
  )
  |> should.equal([])
}

pub fn clean_and_malformed_json_yield_no_paths_test() {
  parser.retired_extension_paths("{\"type\": \"object\"}") |> should.equal([])
  parser.retired_extension_paths("{") |> should.equal([])
  parser.parse_schema("{") |> should.be_error()
}

pub fn retired_paths_escape_keys_per_rfc_6901_test() {
  parser.retired_extension_paths(
    "{\"properties\": {\"a/b\": {\"x-widget\": \"hidden\"}, \"c~d\": {\"x-widget\": \"hidden\"}}}",
  )
  |> should.equal(["#/properties/a~1b", "#/properties/c~0d"])
}
