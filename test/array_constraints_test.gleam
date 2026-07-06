// minItems/maxItems: length validation, add/remove gating, auto-created rows.

import formosh/fields/field_common
import formosh/fields/field_dispatcher
import formosh/form/model.{FormModel}
import formosh/form/path.{ArraySegment, PropertySegment}
import formosh/form/update
import formosh/schema/parser
import formosh/schema/types
import formosh/schema/ui_parser
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import lustre/element

const tags_schema = "{
  \"type\": \"object\",
  \"properties\": {
    \"tags\": {
      \"type\": \"array\",
      \"minItems\": 2,
      \"maxItems\": 3,
      \"items\": {\"type\": \"string\"}
    }
  }
}"

const nested_static_schema = "{
  \"type\": \"object\",
  \"properties\": {
    \"zones\": {
      \"type\": \"array\",
      \"items\": {
        \"type\": \"object\",
        \"properties\": {
          \"lesions\": {
            \"type\": \"array\",
            \"minItems\": 2,
            \"items\": {\"type\": \"object\", \"properties\": {\"form\": {\"type\": \"string\"}}}
          }
        }
      }
    }
  }
}"

const zones_schema = "{
  \"type\": \"object\",
  \"properties\": {
    \"zones\": {
      \"type\": \"array\",
      \"items\": {
        \"type\": \"object\",
        \"properties\": {
          \"affected\": {\"type\": \"boolean\"}
        },
        \"allOf\": [
          {
            \"if\": {\"properties\": {\"affected\": {\"const\": true}}},
            \"then\": {
              \"properties\": {
                \"lesions\": {
                  \"type\": \"array\",
                  \"minItems\": 1,
                  \"items\": {
                    \"type\": \"object\",
                    \"properties\": {
                      \"form\": {\"type\": \"string\"},
                      \"diffuse\": {\"type\": \"boolean\", \"default\": false}
                    }
                  }
                }
              }
            }
          }
        ]
      }
    }
  }
}"

// Build a model with hand-set values and run a full validation pass.
// Values are overridden AFTER init so the (future) init-time reconcile
// never masks the violation under test; ValidateForm does not reconcile.
fn model_with_values(
  schema_json: String,
  values: types.Value,
) -> model.FormModel {
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let m = model.init(schema)
  let m2 = FormModel(..m, values: values)
  let #(m3, _) = update.update(m2, model.ValidateForm)
  m3
}

// --- Validation: length bounds ----------------------------------------------

pub fn min_items_error_on_short_top_level_array_test() {
  let m =
    model_with_values(
      tags_schema,
      types.ObjectValue([#("tags", types.ArrayValue([types.StringValue("a")]))]),
    )
  dict.has_key(m.errors, "tags") |> should.be_true()
}

pub fn max_items_error_on_long_top_level_array_test() {
  let m =
    model_with_values(
      tags_schema,
      types.ObjectValue([
        #(
          "tags",
          types.ArrayValue([
            types.StringValue("a"),
            types.StringValue("b"),
            types.StringValue("c"),
            types.StringValue("d"),
          ]),
        ),
      ]),
    )
  dict.has_key(m.errors, "tags") |> should.be_true()
}

pub fn length_within_bounds_is_valid_test() {
  let m =
    model_with_values(
      tags_schema,
      types.ObjectValue([
        #(
          "tags",
          types.ArrayValue([types.StringValue("a"), types.StringValue("b")]),
        ),
      ]),
    )
  dict.has_key(m.errors, "tags") |> should.be_false()
}

pub fn min_items_error_on_nested_array_test() {
  let m =
    model_with_values(
      nested_static_schema,
      types.ObjectValue([
        #(
          "zones",
          types.ArrayValue([
            types.ObjectValue([
              #("lesions", types.ArrayValue([types.ObjectValue([])])),
            ]),
          ]),
        ),
      ]),
    )
  dict.has_key(m.errors, "zones.[0].lesions") |> should.be_true()
}

pub fn conditional_min_items_error_on_revealed_empty_array_test() {
  // affected == true reveals `lesions` (minItems 1); an empty array violates it.
  let m =
    model_with_values(
      zones_schema,
      types.ObjectValue([
        #(
          "zones",
          types.ArrayValue([
            types.ObjectValue([
              #("affected", types.BooleanValue(True)),
              #("lesions", types.ArrayValue([])),
            ]),
          ]),
        ),
      ]),
    )
  dict.has_key(m.errors, "zones.[0].lesions") |> should.be_true()
}

pub fn conditional_min_items_no_error_when_hidden_test() {
  // affected == false: `lesions` is outside the resolved row schema — no error.
  let m =
    model_with_values(
      zones_schema,
      types.ObjectValue([
        #(
          "zones",
          types.ArrayValue([
            types.ObjectValue([
              #("affected", types.BooleanValue(False)),
              #("lesions", types.ArrayValue([])),
            ]),
          ]),
        ),
      ]),
    )
  dict.has_key(m.errors, "zones.[0].lesions") |> should.be_false()
}

// --- Rendering: button gating ------------------------------------------------

fn render_array(m: model.FormModel, field_name: String) -> String {
  let assert Ok(prop) =
    model.find_property_at_path(m, [PropertySegment(field_name)])
  let ctx =
    field_common.make_field_ctx(
      model: m,
      path: [PropertySegment(field_name)],
      property: prop,
      is_required: False,
      is_disabled: False,
      is_readonly: False,
    )
  field_dispatcher.render_field_at_path(ctx, m) |> element.to_string
}

fn tags_values(tags: List(String)) -> types.Value {
  types.ObjectValue([
    #("tags", types.ArrayValue(list.map(tags, types.StringValue))),
  ])
}

pub fn add_button_hidden_at_max_items_test() {
  let m = model_with_values(tags_schema, tags_values(["a", "b", "c"]))
  string.contains(render_array(m, "tags"), "add-array-item")
  |> should.be_false()
}

pub fn add_button_visible_below_max_items_test() {
  let m = model_with_values(tags_schema, tags_values(["a", "b"]))
  string.contains(render_array(m, "tags"), "add-array-item")
  |> should.be_true()
}

pub fn remove_button_hidden_at_min_items_test() {
  let m = model_with_values(tags_schema, tags_values(["a", "b"]))
  string.contains(render_array(m, "tags"), "remove-array-item")
  |> should.be_false()
}

pub fn remove_button_visible_above_min_items_test() {
  let m = model_with_values(tags_schema, tags_values(["a", "b", "c"]))
  string.contains(render_array(m, "tags"), "remove-array-item")
  |> should.be_true()
}

pub fn ui_removable_false_composes_with_min_items_test() {
  // ui:removable false hides remove even when count > minItems.
  let assert Ok(schema) = parser.parse_schema(tags_schema)
  let assert Ok(ui) = ui_parser.parse("{\"tags\": {\"ui:removable\": false}}")
  let m0 = model.init_with_full_config(schema, None, False, dict.new(), ui)
  let m = FormModel(..m0, values: tags_values(["a", "b", "c"]))
  string.contains(render_array(m, "tags"), "remove-array-item")
  |> should.be_false()
}

// Errors keyed to the array container render through the standard
// touched-gated error wrapper (no extra code — regression guard).
pub fn array_container_error_renders_when_touched_test() {
  let m = model_with_values(tags_schema, tags_values(["a"]))
  let m2 = model.mark_field_touched(m, [PropertySegment("tags")])
  let html = render_array(m2, "tags")
  string.contains(html, "data-error") |> should.be_true()
  string.contains(html, "At least 2 item(s) required") |> should.be_true()
}

// --- AddArrayItemPath: manual rows carry item defaults -----------------------

pub fn add_array_item_carries_item_defaults_test() {
  let assert Ok(schema) =
    parser.parse_schema(
      "{
      \"type\": \"object\",
      \"properties\": {
        \"lesions\": {
          \"type\": \"array\",
          \"items\": {
            \"type\": \"object\",
            \"properties\": {
              \"form\": {\"type\": \"string\"},
              \"diffuse\": {\"type\": \"boolean\", \"default\": false}
            }
          }
        }
      }
    }",
    )
  let m = model.init(schema)
  let #(m1, _) =
    update.update(m, model.AddArrayItemPath([PropertySegment("lesions")]))
  path.get_at_path(m1.values, [
    PropertySegment("lesions"),
    ArraySegment(0),
    PropertySegment("diffuse"),
  ])
  |> should.equal(Some(types.BooleanValue(False)))
}

pub fn add_item_to_conditional_array_carries_defaults_test() {
  // The lesions array only exists in the resolved row schema (affected ==
  // true), so the item template must be found via the value-resolved walk.
  let assert Ok(schema) = parser.parse_schema(zones_schema)
  let m = model.init(schema)
  let #(m1, _) =
    update.update(m, model.AddArrayItemPath([PropertySegment("zones")]))
  let #(m2, _) =
    update.update(
      m1,
      model.UpdateFieldPath(
        [
          PropertySegment("zones"),
          ArraySegment(0),
          PropertySegment("affected"),
        ],
        types.BooleanValue(True),
      ),
    )
  let lesions_path = [
    PropertySegment("zones"),
    ArraySegment(0),
    PropertySegment("lesions"),
  ]
  let #(m3, _) = update.update(m2, model.AddArrayItemPath(lesions_path))

  // Assert on the LAST row: it is the manually added one both before and
  // after the reconcile pass (Task 8) starts auto-creating the first row.
  let assert Some(types.ArrayValue(rows)) =
    path.get_at_path(m3.values, lesions_path)
  list.last(rows)
  |> should.equal(
    Ok(types.ObjectValue([#("diffuse", types.BooleanValue(False))])),
  )
}

// --- Reconcile: auto-created rows ---------------------------------------------

pub fn init_tops_up_min_items_array_test() {
  let assert Ok(schema) = parser.parse_schema(tags_schema)
  let m = model.init(schema)
  let assert Some(types.ArrayValue(rows)) =
    path.get_at_path(m.values, [PropertySegment("tags")])
  list.length(rows) |> should.equal(2)
  // And the topped-up array is valid — no minItems error on init.
  dict.has_key(m.errors, "tags") |> should.be_false()
}

pub fn reset_tops_up_min_items_array_test() {
  let assert Ok(schema) = parser.parse_schema(tags_schema)
  let m = model.reset(model.init(schema))
  let assert Some(types.ArrayValue(rows)) =
    path.get_at_path(m.values, [PropertySegment("tags")])
  list.length(rows) |> should.equal(2)
}

pub fn update_reveals_and_tops_up_conditional_array_test() {
  let assert Ok(schema) = parser.parse_schema(zones_schema)
  let m = model.init(schema)
  let #(m1, _) =
    update.update(m, model.AddArrayItemPath([PropertySegment("zones")]))
  // No lesions before the condition fires.
  path.get_at_path(m1.values, [
    PropertySegment("zones"),
    ArraySegment(0),
    PropertySegment("lesions"),
  ])
  |> should.equal(None)

  let #(m2, _) =
    update.update(
      m1,
      model.UpdateFieldPath(
        [
          PropertySegment("zones"),
          ArraySegment(0),
          PropertySegment("affected"),
        ],
        types.BooleanValue(True),
      ),
    )
  // affected == true reveals lesions; reconcile auto-creates one row with
  // the diffuse=false default applied.
  path.get_at_path(m2.values, [
    PropertySegment("zones"),
    ArraySegment(0),
    PropertySegment("lesions"),
  ])
  |> should.equal(
    Some(
      types.ArrayValue([
        types.ObjectValue([#("diffuse", types.BooleanValue(False))]),
      ]),
    ),
  )
  // The auto-created row satisfies minItems — no error on the array.
  dict.has_key(m2.errors, "zones.[0].lesions") |> should.be_false()
}

pub fn remove_below_min_is_not_fought_test() {
  // External removal below minItems: reconcile does not run on remove;
  // validation reports the violation instead.
  let assert Ok(schema) = parser.parse_schema(tags_schema)
  let m = model.init(schema)
  let #(m1, _) =
    update.update(m, model.RemoveArrayItemPath([PropertySegment("tags")], 0))
  let assert Some(types.ArrayValue(rows)) =
    path.get_at_path(m1.values, [PropertySegment("tags")])
  list.length(rows) |> should.equal(1)
  dict.has_key(m1.errors, "tags") |> should.be_true()
}
