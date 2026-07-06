// minItems/maxItems: length validation, add/remove gating, auto-created rows.

import formosh/form/model.{FormModel}
import formosh/form/update
import formosh/schema/parser
import formosh/schema/types
import gleam/dict
import gleeunit/should

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
