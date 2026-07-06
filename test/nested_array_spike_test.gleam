// Spike: verify actual support for arrays nested inside array-item objects
// (radiology carcinomatosis shape: zones[] -> lesions[]).
//
// README claims "Nested arrays within objects (shows error message)" but no
// such error exists in code. These tests establish the real status of:
//   1. parsing        2. add-item at nested path      3. value update
//   4. required validation two array levels deep      5. conditional required
//   6. rendering (outer + inner add buttons, inner fields)

import formosh/fields/field_common
import formosh/fields/field_dispatcher
import formosh/form/model.{FormModel}
import formosh/form/path.{ArraySegment, PropertySegment}
import formosh/form/update
import formosh/schema/parser
import formosh/schema/types
import gleam/dict
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should
import lustre/element

const schema_json = "{
  \"type\": \"object\",
  \"properties\": {
    \"zones\": {
      \"type\": \"array\",
      \"title\": \"Zones\",
      \"items\": {
        \"type\": \"object\",
        \"properties\": {
          \"zone_id\": {\"type\": \"integer\", \"readOnly\": true},
          \"affected\": {\"type\": \"boolean\"},
          \"lesions\": {
            \"type\": \"array\",
            \"title\": \"Lesions\",
            \"items\": {
              \"type\": \"object\",
              \"properties\": {
                \"form\": {\"type\": \"string\", \"enum\": [\"focus\", \"cystic\", \"thickening\"]},
                \"extent_mm\": {\"type\": \"number\"}
              },
              \"required\": [\"form\"],
              \"allOf\": [
                {
                  \"if\": {\"properties\": {\"form\": {\"const\": \"thickening\"}}},
                  \"then\": {
                    \"properties\": {\"uniformity\": {\"type\": \"string\", \"enum\": [\"uniform\", \"nodular\"]}},
                    \"required\": [\"uniformity\"]
                  }
                }
              ]
            }
          }
        }
      }
    }
  }
}"

fn parsed_schema() -> types.JsonSchema {
  let assert Ok(schema) = parser.parse_schema(schema_json)
  schema
}

fn zones_property(schema: types.JsonSchema) -> types.SchemaProperty {
  let assert Ok(#(_, prop)) =
    list.find(schema.properties, fn(entry) { entry.0 == "zones" })
  prop
}

// --- 1. Parsing -------------------------------------------------------------

pub fn spike_parse_nested_array_test() {
  let schema = parsed_schema()
  let zones = zones_property(schema)
  zones.field_type |> should.equal(Some(types.ArrayType))

  let assert Some(zone_item) = zones.items
  zone_item.field_type |> should.equal(Some(types.ObjectType))

  let assert Some(props) = zone_item.properties
  let assert Ok(#(_, lesions)) =
    list.find(props, fn(entry) { entry.0 == "lesions" })
  lesions.field_type |> should.equal(Some(types.ArrayType))

  let assert Some(lesion_item) = lesions.items
  lesion_item.field_type |> should.equal(Some(types.ObjectType))
  lesion_item.required |> should.equal(["form"])
}

// --- 2. Add item at nested path --------------------------------------------

pub fn spike_add_nested_array_item_test() {
  let m = model.init(parsed_schema())
  let #(m1, _) =
    update.update(m, model.AddArrayItemPath([PropertySegment("zones")]))
  let lesions_path = [
    PropertySegment("zones"),
    ArraySegment(0),
    PropertySegment("lesions"),
  ]
  let #(m2, _) = update.update(m1, model.AddArrayItemPath(lesions_path))

  path.get_at_path(m2.values, list.append(lesions_path, [ArraySegment(0)]))
  |> should.equal(Some(types.ObjectValue([])))
}

// --- 3. Update value at doubly-nested path ----------------------------------

pub fn spike_update_nested_field_test() {
  let m = model.init(parsed_schema())
  let #(m1, _) =
    update.update(m, model.AddArrayItemPath([PropertySegment("zones")]))
  let lesions_path = [
    PropertySegment("zones"),
    ArraySegment(0),
    PropertySegment("lesions"),
  ]
  let #(m2, _) = update.update(m1, model.AddArrayItemPath(lesions_path))

  let form_path =
    list.append(lesions_path, [ArraySegment(0), PropertySegment("form")])
  let #(m3, _) =
    update.update(
      m2,
      model.UpdateFieldPath(form_path, types.StringValue("focus")),
    )

  path.get_at_path(m3.values, form_path)
  |> should.equal(Some(types.StringValue("focus")))
}

// --- 4. Required validation two array levels deep ---------------------------

pub fn spike_nested_required_error_test() {
  let m = model.init(parsed_schema())
  let #(m1, _) =
    update.update(m, model.AddArrayItemPath([PropertySegment("zones")]))
  let lesions_path = [
    PropertySegment("zones"),
    ArraySegment(0),
    PropertySegment("lesions"),
  ]
  // Adding an empty lesion object: "form" is required but missing.
  let #(m2, _) = update.update(m1, model.AddArrayItemPath(lesions_path))

  dict.has_key(m2.errors, "zones.[0].lesions.[0].form")
  |> should.be_true()
}

// --- 5. Conditional (if/then) inside doubly-nested item ---------------------

pub fn spike_nested_conditional_required_test() {
  let m = model.init(parsed_schema())
  let #(m1, _) =
    update.update(m, model.AddArrayItemPath([PropertySegment("zones")]))
  let lesions_path = [
    PropertySegment("zones"),
    ArraySegment(0),
    PropertySegment("lesions"),
  ]
  let #(m2, _) = update.update(m1, model.AddArrayItemPath(lesions_path))

  let form_path =
    list.append(lesions_path, [ArraySegment(0), PropertySegment("form")])
  let #(m3, _) =
    update.update(
      m2,
      model.UpdateFieldPath(form_path, types.StringValue("thickening")),
    )

  // form == "thickening" triggers the item-level conditional: uniformity
  // becomes required and must produce an error while unset.
  dict.has_key(m3.errors, "zones.[0].lesions.[0].uniformity")
  |> should.be_true()
}

// --- 6. Rendering: inner array renders with its own controls ----------------

pub fn spike_render_nested_array_test() {
  let schema = parsed_schema()
  let m = model.init(schema)
  let values =
    types.ObjectValue([
      #(
        "zones",
        types.ArrayValue([
          types.ObjectValue([
            #("zone_id", types.IntegerValue(5)),
            #("affected", types.BooleanValue(True)),
            #("lesions", types.ArrayValue([types.ObjectValue([])])),
          ]),
        ]),
      ),
    ])
  let m2 = FormModel(..m, values: values)

  let ctx =
    field_common.make_field_ctx(
      model: m2,
      path: [PropertySegment("zones")],
      property: zones_property(schema),
      is_required: False,
      is_disabled: False,
      is_readonly: False,
    )
  let html = field_dispatcher.render_field_at_path(ctx, m2) |> element.to_string

  // Outer zones add button + inner lesions add button.
  let add_button_count = string.split(html, "add-array-item") |> list.length()
  { add_button_count >= 3 } |> should.be_true()

  // Inner lesion fields actually render.
  string.contains(html, "extent_mm") |> should.be_true()
  string.contains(html, "Lesions") |> should.be_true()
}
