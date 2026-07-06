// Integration tests for demo/schemas/carcinomatosis_radiology.json — the
// radiology form with a nested array (lesions[] inside zones[] rows) and
// per-lesion if/then conditionals ($defs/$ref + multi-property if).

import formosh/fields/field_common
import formosh/fields/field_dispatcher
import formosh/form/model
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
import simplifile

fn load_schema() -> types.JsonSchema {
  let assert Ok(json) =
    simplifile.read("demo/schemas/carcinomatosis_radiology.json")
  let assert Ok(schema) = parser.parse_schema(json)
  schema
}

// Schema parses and the $defs/$ref lesion item resolves inside the nested
// array: zones.items.properties.lesions.items must be the lesion object.
pub fn parse_and_resolve_lesion_ref_test() {
  let schema = load_schema()
  let assert Ok(#(_, zones)) =
    list.find(schema.properties, fn(entry) { entry.0 == "zones" })
  let assert Some(zone_item) = zones.items
  let assert Some(zone_props) = zone_item.properties
  let assert Ok(#(_, lesions)) =
    list.find(zone_props, fn(entry) { entry.0 == "lesions" })
  let assert Some(lesion) = lesions.items
  lesion.field_type |> should.equal(Some(types.ObjectType))
  lesion.required |> should.equal(["form", "contour"])
}

// The zones array default prefills all rows on init.
pub fn zones_prefilled_from_default_test() {
  let m = model.init(load_schema())
  let assert Some(types.ArrayValue(rows)) =
    path.get_at_path(m.values, [PropertySegment("zones")])
  list.length(rows) |> should.equal(4)

  path.get_at_path(m.values, [
    PropertySegment("zones"),
    ArraySegment(3),
    PropertySegment("zone_id"),
  ])
  |> should.equal(Some(types.IntegerValue(28)))
}

// form == "утолщение" + diffuse == false reveals extent/thickness and makes
// them required (multi-property if inside the nested lesion item).
pub fn thickening_requires_size_fields_test() {
  let m = model.init(load_schema())
  let lesions_path = [
    PropertySegment("zones"),
    ArraySegment(0),
    PropertySegment("lesions"),
  ]
  let #(m1, _) = update.update(m, model.AddArrayItemPath(lesions_path))
  let lesion_field = fn(name) {
    list.append(lesions_path, [ArraySegment(0), PropertySegment(name)])
  }
  let #(m2, _) =
    update.update(
      m1,
      model.UpdateFieldPath(
        lesion_field("form"),
        types.StringValue("утолщение"),
      ),
    )
  let #(m3, _) =
    update.update(
      m2,
      model.UpdateFieldPath(lesion_field("diffuse"), types.BooleanValue(False)),
    )

  dict.has_key(m3.errors, "zones.[0].lesions.[0].extent_mm")
  |> should.be_true()
  dict.has_key(m3.errors, "zones.[0].lesions.[0].thickness_mm")
  |> should.be_true()

  // diffuse == true drops the size requirement again.
  let #(m4, _) =
    update.update(
      m3,
      model.UpdateFieldPath(lesion_field("diffuse"), types.BooleanValue(True)),
    )
  dict.has_key(m4.errors, "zones.[0].lesions.[0].extent_mm")
  |> should.be_false()
}

// The zones array renders its prefilled rows with the nested lesions array.
pub fn render_zones_with_nested_lesions_test() {
  let schema = load_schema()
  let m = model.init(schema)
  let assert Ok(#(_, zones_prop)) =
    list.find(schema.properties, fn(entry) { entry.0 == "zones" })

  let ctx =
    field_common.make_field_ctx(
      model: m,
      path: [PropertySegment("zones")],
      property: zones_prop,
      is_required: True,
      is_disabled: False,
      is_readonly: False,
    )
  let html = field_dispatcher.render_field_at_path(ctx, m) |> element.to_string

  string.contains(html, "Очаги") |> should.be_true()
  string.contains(html, "Поражение в зоне") |> should.be_true()
}
