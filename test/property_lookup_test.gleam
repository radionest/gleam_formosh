// Tests for model.find_property_at_path — recursive lookup of a
// SchemaProperty by FieldPath across nested objects and array items.
// Anchors PR 4: image-upload widgets that live deeper than the root
// must still resolve their `upload_config` via the resolved schema.

import formosh/form/model
import formosh/form/path
import formosh/schema/parser
import formosh/schema/types
import formosh/schema/ui_schema
import gleam/dict
import gleam/option.{None, Some}
import gleeunit/should

const lookup_schema = "{
  \"type\": \"object\",
  \"properties\": {
    \"name\": {\"type\": \"string\"},
    \"user\": {
      \"type\": \"object\",
      \"properties\": {
        \"email\": {\"type\": \"string\"}
      }
    },
    \"lesions\": {
      \"type\": \"array\",
      \"items\": {
        \"type\": \"object\",
        \"properties\": {
          \"photo\": {
            \"type\": \"array\",
            \"items\": {\"type\": \"string\"},
            \"x-widget\": \"image-upload\",
            \"x-accept\": \"image/png\",
            \"x-max-file-size\": 1024
          }
        }
      }
    },
    \"tags\": {
      \"type\": \"array\",
      \"items\": {\"type\": \"string\"}
    }
  }
}"

fn init_for_lookup() -> model.FormModel {
  let assert Ok(schema) = parser.parse_schema(lookup_schema)
  model.init_with_full_config(
    schema,
    None,
    False,
    dict.new(),
    ui_schema.empty_ui_schema(),
  )
}

pub fn top_level_property_resolves_test() {
  let m = init_for_lookup()
  let result = model.find_property_at_path(m, [path.PropertySegment("name")])
  should.be_ok(result)
  let assert Ok(prop) = result
  prop.field_type |> should.equal(Some(types.StringType))
}

pub fn nested_object_property_resolves_test() {
  let m = init_for_lookup()
  let result =
    model.find_property_at_path(m, [
      path.PropertySegment("user"),
      path.PropertySegment("email"),
    ])
  should.be_ok(result)
  let assert Ok(prop) = result
  prop.field_type |> should.equal(Some(types.StringType))
}

// Anchors the actual PR 4 user-visible fix: a `photo` image-upload field
// nested inside an array item must resolve to its own SchemaProperty,
// carrying the upload_config parsed from x-accept / x-max-file-size.
pub fn array_item_field_resolves_with_upload_config_test() {
  let m = init_for_lookup()
  let result =
    model.find_property_at_path(m, [
      path.PropertySegment("lesions"),
      path.ArraySegment(0),
      path.PropertySegment("photo"),
    ])
  should.be_ok(result)
  let assert Ok(prop) = result
  prop.render_hints.widget |> should.equal(Some(types.ImageUploadWidget))
  prop.render_hints.upload_config
  |> should.equal(Some(types.UploadConfig("image/png", Some(1024))))
}

pub fn missing_property_returns_error_test() {
  let m = init_for_lookup()
  model.find_property_at_path(m, [path.PropertySegment("nonexistent")])
  |> should.be_error()
}

pub fn array_segment_prefix_returns_error_test() {
  let m = init_for_lookup()
  model.find_property_at_path(m, [path.ArraySegment(0)])
  |> should.be_error()
}

pub fn empty_path_returns_error_test() {
  let m = init_for_lookup()
  model.find_property_at_path(m, [])
  |> should.be_error()
}

// `name` is a scalar string — trying to descend into a child PropertySegment
// has no schema-level meaning. Lookup must bottom out at Error(Nil), not
// silently return the parent or crash on the missing `properties` field.
pub fn descending_past_scalar_returns_error_test() {
  let m = init_for_lookup()
  model.find_property_at_path(m, [
    path.PropertySegment("name"),
    path.PropertySegment("foo"),
  ])
  |> should.be_error()
}

// `tags` is an array of strings — once we step into an item, the items-
// schema has no `properties` of its own. A further PropertySegment after
// ArraySegment must yield Error(Nil).
pub fn descending_through_array_of_scalars_returns_error_test() {
  let m = init_for_lookup()
  model.find_property_at_path(m, [
    path.PropertySegment("tags"),
    path.ArraySegment(0),
    path.PropertySegment("foo"),
  ])
  |> should.be_error()
}
