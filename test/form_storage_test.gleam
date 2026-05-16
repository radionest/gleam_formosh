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
import formosh/schema/ui_schema
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
  model.init_with_full_config(
    schema,
    None,
    False,
    initial,
    ui_schema.empty_ui_schema(),
  )
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

const items_schema = "{
  \"type\": \"object\",
  \"properties\": {
    \"items\": {
      \"type\": \"array\",
      \"items\": {
        \"type\": \"object\",
        \"properties\": {
          \"name\": {\"type\": \"string\"}
        },
        \"required\": [\"name\"]
      }
    }
  }
}"

fn init_items() -> model.FormModel {
  let assert Ok(schema) = parser.parse_schema(items_schema)
  model.init(schema)
}

fn item_name_path(index: Int) -> path.FieldPath {
  [
    path.PropertySegment("items"),
    path.ArraySegment(index),
    path.PropertySegment("name"),
  ]
}

fn add_item(m: model.FormModel) -> model.FormModel {
  let #(after, _) =
    update.update(m, model.AddArrayItemPath([path.PropertySegment("items")]))
  after
}

fn set_item_name(
  m: model.FormModel,
  index: Int,
  name: String,
) -> model.FormModel {
  let #(after, _) =
    update.update(
      m,
      model.UpdateFieldPath(item_name_path(index), StringValue(name)),
    )
  after
}

fn remove_item(m: model.FormModel, index: Int) -> model.FormModel {
  let #(after, _) =
    update.update(
      m,
      model.RemoveArrayItemPath([path.PropertySegment("items")], index),
    )
  after
}

// Regression: removing an array item must shift touched_fields entries with
// matching prefix down (index > removed_index → index - 1), drop the row
// being removed, and leave unrelated paths intact.
pub fn remove_array_item_reindexes_touched_fields_test() {
  let m =
    init_items()
    |> add_item
    |> add_item
    |> add_item
    |> set_item_name(0, "Alice")
    |> set_item_name(1, "Bob")

  // Sanity: both items are touched before removal.
  model.is_field_touched(m, item_name_path(0)) |> should.be_true()
  model.is_field_touched(m, item_name_path(1)) |> should.be_true()
  model.is_field_touched(m, item_name_path(2)) |> should.be_false()

  let after = remove_item(m, 0)

  // After removing item[0] (Alice was here): touch on items.[1].name (Bob)
  // must reindex to items.[0].name; items.[1].name is no longer touched.
  model.is_field_touched(after, item_name_path(0)) |> should.be_true()
  model.is_field_touched(after, item_name_path(1)) |> should.be_false()

  // touched_fields length goes from 2 → 1 (Alice's row dropped, Bob's
  // reindexed in place).
  list.length(after.touched_fields) |> should.equal(1)
}

// Regression: adding an array item appends to the end, so existing touched
// entries must stay intact (no shift). is_dirty is set so consumers can
// detect the change.
pub fn add_array_item_preserves_existing_touched_test() {
  let m =
    init_items()
    |> add_item
    |> set_item_name(0, "Alice")

  model.is_field_touched(m, item_name_path(0)) |> should.be_true()

  let after = add_item(m)

  // After append: item[0] is still Alice (still touched), item[1] is empty
  // (not touched).
  model.is_field_touched(after, item_name_path(0)) |> should.be_true()
  model.is_field_touched(after, item_name_path(1)) |> should.be_false()
  after.is_dirty |> should.be_true()
}

// Regression: errors keyed by `path.to_string` must reindex after removal.
// items.[0] valid, items.[1]/[2] missing required → errors at [1]/[2]. After
// removing [0] (the valid row), the formerly invalid [1] becomes [0] and
// the formerly invalid [2] becomes [1]; old keys must clear.
pub fn remove_array_item_reindexes_errors_test() {
  let m =
    init_items()
    |> add_item
    |> add_item
    |> add_item
    |> set_item_name(0, "Alice")

  // Sanity before removal: [0] valid, [1] and [2] required-empty → errors.
  model.has_errors_at_path(m, item_name_path(0)) |> should.be_false()
  model.has_errors_at_path(m, item_name_path(1)) |> should.be_true()
  model.has_errors_at_path(m, item_name_path(2)) |> should.be_true()

  let after = remove_item(m, 0)

  // After removing item[0]: former [1] → [0] (still empty, still error),
  // former [2] → [1] (still empty, still error). No item at index [2].
  model.has_errors_at_path(after, item_name_path(0)) |> should.be_true()
  model.has_errors_at_path(after, item_name_path(1)) |> should.be_true()
  model.has_errors_at_path(after, item_name_path(2)) |> should.be_false()
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
