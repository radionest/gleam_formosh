// Tests covering PR 3: single hierarchical Value root for form storage.
// These tests assert behaviours that only make sense once `model.values`
// is one Value tree — initial-values hydration of nested structures,
// sibling preservation through `UpdateFieldPath`, and the new return
// types of `get_form_values` / submit serialisation.

import formosh/form/json_utils
import formosh/form/model
import formosh/form/path
import formosh/form/update
import formosh/schema/parser
import formosh/schema/types.{ArrayValue, ObjectValue, StringValue}
import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

const nested_schema = "{
  \"type\": \"object\",
  \"properties\": {
    \"user\": {
      \"type\": \"object\",
      \"properties\": {
        \"name\": {\"type\": \"string\"},
        \"address\": {
          \"type\": \"object\",
          \"properties\": {
            \"street\": {\"type\": \"string\"},
            \"city\": {\"type\": \"string\"}
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

fn init_with_nested(initial: dict.Dict(String, types.Value)) -> model.FormModel {
  let assert Ok(schema) = parser.parse_schema(nested_schema)
  model.init_with_full_config(schema, None, False, initial)
}

// Initial values for a deeply nested structure must be hydrated into the
// single Value tree exactly as supplied — no flattening, no key loss.
pub fn init_hydrates_nested_initial_values_test() {
  let initial =
    dict.from_list([
      #(
        "user",
        ObjectValue([
          #("name", StringValue("Ada")),
          #(
            "address",
            ObjectValue([
              #("street", StringValue("Main St")),
              #("city", StringValue("London")),
            ]),
          ),
        ]),
      ),
    ])

  let m = init_with_nested(initial)

  model.get_value_at_path(m, [
    path.PropertySegment("user"),
    path.PropertySegment("address"),
    path.PropertySegment("street"),
  ])
  |> should.equal(Some(StringValue("Main St")))

  model.get_value_at_path(m, [
    path.PropertySegment("user"),
    path.PropertySegment("address"),
    path.PropertySegment("city"),
  ])
  |> should.equal(Some(StringValue("London")))

  model.get_value_at_path(m, [
    path.PropertySegment("user"),
    path.PropertySegment("name"),
  ])
  |> should.equal(Some(StringValue("Ada")))
}

// `UpdateFieldPath` for a deep leaf must not destroy the sibling branches
// at any nesting level. This is the regression the old Dict↔Value adapter
// pair was designed to avoid; with the single Value root and direct
// `path.set_at_path`, the property holds without any conversion glue.
pub fn update_field_path_preserves_siblings_test() {
  let initial =
    dict.from_list([
      #(
        "user",
        ObjectValue([
          #("name", StringValue("Ada")),
          #(
            "address",
            ObjectValue([
              #("street", StringValue("Main St")),
              #("city", StringValue("London")),
            ]),
          ),
        ]),
      ),
      #("tags", ArrayValue([StringValue("admin")])),
    ])
  let m = init_with_nested(initial)

  let leaf_path = [
    path.PropertySegment("user"),
    path.PropertySegment("address"),
    path.PropertySegment("street"),
  ]
  let #(updated, _effect) =
    update.update(m, model.UpdateFieldPath(leaf_path, StringValue("New St")))

  // Leaf updated.
  model.get_value_at_path(updated, leaf_path)
  |> should.equal(Some(StringValue("New St")))

  // Sibling at the same nested level survives.
  model.get_value_at_path(updated, [
    path.PropertySegment("user"),
    path.PropertySegment("address"),
    path.PropertySegment("city"),
  ])
  |> should.equal(Some(StringValue("London")))

  // Sibling one level up survives.
  model.get_value_at_path(updated, [
    path.PropertySegment("user"),
    path.PropertySegment("name"),
  ])
  |> should.equal(Some(StringValue("Ada")))

  // Sibling at the root survives.
  model.get_value_at_path(updated, [path.PropertySegment("tags")])
  |> should.equal(Some(ArrayValue([StringValue("admin")])))
}

// Public `get_form_values` returns the hierarchical Value tree itself
// (always rooted at ObjectValue), not a flat Dict. Earlier the same call
// returned `Dict(String, Value)`; this is the BREAKING boundary of PR 3.
pub fn get_form_values_returns_value_root_test() {
  let initial =
    dict.from_list([
      #("user", ObjectValue([#("name", StringValue("Ada"))])),
    ])
  let m = init_with_nested(initial)

  case model.get_form_values(m) {
    ObjectValue(fields) ->
      // The single declared root key is preserved as a top-level pair —
      // the function does not flatten nested objects.
      list.contains(list.map(fields, fn(p) { p.0 }), "user")
      |> should.be_true()
    _ -> panic as "get_form_values must return ObjectValue at the root"
  }
}

// End-to-end submit path: the values tree round-trips through
// `value_to_json` to a faithful JSON document with the full nested
// hierarchy, including arrays and nested objects.
pub fn submit_serializes_full_hierarchy_test() {
  let initial =
    dict.from_list([
      #(
        "user",
        ObjectValue([
          #("name", StringValue("Ada")),
          #(
            "address",
            ObjectValue([
              #("street", StringValue("Main St")),
            ]),
          ),
        ]),
      ),
      #("tags", ArrayValue([StringValue("admin"), StringValue("ops")])),
    ])
  let m = init_with_nested(initial)

  let serialised =
    m
    |> model.get_resolved_values
    |> json_utils.value_to_json
    |> json.to_string

  serialised
  |> should.equal(
    "{\"user\":{\"name\":\"Ada\",\"address\":{\"street\":\"Main St\"}},\"tags\":[\"admin\",\"ops\"]}",
  )
}
