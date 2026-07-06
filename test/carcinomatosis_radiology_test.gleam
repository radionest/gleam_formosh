// Integration tests for demo/schemas/carcinomatosis_radiology.json — the
// radiology form where lesions[] exists inside a zone row only while the
// zone is affected (array inside `then`, minItems 1, auto-created row).

import formosh/fields/field_common
import formosh/fields/field_dispatcher
import formosh/form/model
import formosh/form/path.{ArraySegment, PropertySegment}
import formosh/form/update
import formosh/schema/conditional_resolver
import formosh/schema/parser
import formosh/schema/types
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
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

// lesions is NOT in the base zone item — it lives in the conditional
// `then` branch and appears after per-row resolution with affected == true,
// carrying minItems 1 and the inlined lesion item definition.
pub fn lesions_revealed_by_condition_test() {
  let schema = load_schema()
  let assert Ok(#(_, zones)) =
    list.find(schema.properties, fn(entry) { entry.0 == "zones" })
  let assert Some(zone_item) = zones.items
  let assert Some(zone_props) = zone_item.properties
  list.find(zone_props, fn(entry) { entry.0 == "lesions" })
  |> should.be_error()

  let resolved =
    conditional_resolver.resolve_conditional_property(
      zone_item,
      types.ObjectValue([#("affected", types.BooleanValue(True))]),
    )
  let assert Some(resolved_props) = resolved.properties
  let assert Ok(#(_, lesions)) =
    list.find(resolved_props, fn(entry) { entry.0 == "lesions" })
  lesions.array_constraints
  |> should.equal(
    Some(types.ArrayConstraints(min_items: Some(1), max_items: None)),
  )
  let assert Some(lesion) = lesions.items
  lesion.field_type |> should.equal(Some(types.ObjectType))
  lesion.required |> should.equal(["form", "contour"])
}

// The zones array default prefills all rows on init; no lesions yet.
pub fn zones_prefilled_without_lesions_test() {
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

  path.get_at_path(m.values, [
    PropertySegment("zones"),
    ArraySegment(0),
    PropertySegment("lesions"),
  ])
  |> should.equal(None)
}

// affected == true auto-creates the first lesion row (minItems 1) with the
// diffuse=false default applied.
pub fn affected_zone_auto_creates_lesion_row_test() {
  let m = model.init(load_schema())
  let #(m1, _) =
    update.update(
      m,
      model.UpdateFieldPath(
        [
          PropertySegment("zones"),
          ArraySegment(0),
          PropertySegment("affected"),
        ],
        types.BooleanValue(True),
      ),
    )
  let assert Some(types.ArrayValue([types.ObjectValue(row)])) =
    path.get_at_path(m1.values, [
      PropertySegment("zones"),
      ArraySegment(0),
      PropertySegment("lesions"),
    ])
  list.key_find(row, "diffuse")
  |> should.equal(Ok(types.BooleanValue(False)))
}

// form == "утолщение" on the auto-created row (diffuse defaults to false)
// reveals extent/thickness and makes them required; diffuse == true drops
// the requirement again.
pub fn thickening_requires_size_fields_test() {
  let m = model.init(load_schema())
  let #(m1, _) =
    update.update(
      m,
      model.UpdateFieldPath(
        [
          PropertySegment("zones"),
          ArraySegment(0),
          PropertySegment("affected"),
        ],
        types.BooleanValue(True),
      ),
    )
  let lesion_field = fn(name) {
    [
      PropertySegment("zones"),
      ArraySegment(0),
      PropertySegment("lesions"),
      ArraySegment(0),
      PropertySegment(name),
    ]
  }
  let #(m2, _) =
    update.update(
      m1,
      model.UpdateFieldPath(
        lesion_field("form"),
        types.StringValue("утолщение"),
      ),
    )

  dict.has_key(m2.errors, "zones.[0].lesions.[0].extent_mm")
  |> should.be_true()
  dict.has_key(m2.errors, "zones.[0].lesions.[0].thickness_mm")
  |> should.be_true()

  let #(m3, _) =
    update.update(
      m2,
      model.UpdateFieldPath(lesion_field("diffuse"), types.BooleanValue(True)),
    )
  dict.has_key(m3.errors, "zones.[0].lesions.[0].extent_mm")
  |> should.be_false()
}

// Render: lesions hidden while the zone is not affected; revealed (with
// the auto-created row) once affected is switched on.
pub fn render_lesions_only_when_affected_test() {
  let schema = load_schema()
  let render = fn(m: model.FormModel) {
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
    field_dispatcher.render_field_at_path(ctx, m) |> element.to_string
  }

  let m = model.init(schema)
  string.contains(render(m), "Очаги") |> should.be_false()

  let #(m1, _) =
    update.update(
      m,
      model.UpdateFieldPath(
        [
          PropertySegment("zones"),
          ArraySegment(0),
          PropertySegment("affected"),
        ],
        types.BooleanValue(True),
      ),
    )
  string.contains(render(m1), "Очаги") |> should.be_true()
}
