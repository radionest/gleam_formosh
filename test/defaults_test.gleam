import formosh/form/model
import formosh/schema/parser
import formosh/schema/types.{
  ArrayValue, BooleanValue, IntegerValue, NullValue, ObjectValue, StringValue,
}
import gleam/dict
import gleam/option.{None}
import gleeunit/should

fn init_with(schema_json: String, values: dict.Dict(String, types.Value)) {
  let assert Ok(schema) = parser.parse_schema(schema_json)
  model.init_with_full_config(schema, None, False, values)
}

pub fn top_level_boolean_default_applied_test() {
  let schema =
    "{
      \"type\": \"object\",
      \"properties\": {
        \"is_resected\": {\"type\": \"boolean\", \"default\": false}
      },
      \"required\": [\"is_resected\"]
    }"

  let m = init_with(schema, dict.new())
  dict.get(m.values, "is_resected")
  |> should.equal(Ok(BooleanValue(False)))
}

pub fn top_level_string_default_applied_test() {
  let schema =
    "{
      \"type\": \"object\",
      \"properties\": {
        \"side\": {\"type\": \"string\", \"default\": \"left\"}
      }
    }"

  let m = init_with(schema, dict.new())
  dict.get(m.values, "side")
  |> should.equal(Ok(StringValue("left")))
}

pub fn existing_value_not_overridden_test() {
  let schema =
    "{
      \"type\": \"object\",
      \"properties\": {
        \"flag\": {\"type\": \"boolean\", \"default\": false}
      }
    }"

  let m = init_with(schema, dict.from_list([#("flag", BooleanValue(True))]))
  dict.get(m.values, "flag")
  |> should.equal(Ok(BooleanValue(True)))
}

pub fn null_value_replaced_by_default_test() {
  let schema =
    "{
      \"type\": \"object\",
      \"properties\": {
        \"flag\": {\"type\": \"boolean\", \"default\": false}
      }
    }"

  let m = init_with(schema, dict.from_list([#("flag", NullValue)]))
  dict.get(m.values, "flag")
  |> should.equal(Ok(BooleanValue(False)))
}

pub fn field_without_default_skipped_test() {
  let schema =
    "{
      \"type\": \"object\",
      \"properties\": {
        \"name\": {\"type\": \"string\"}
      }
    }"

  let m = init_with(schema, dict.new())
  dict.has_key(m.values, "name") |> should.be_false()
}

pub fn nested_object_defaults_applied_test() {
  let schema =
    "{
      \"type\": \"object\",
      \"properties\": {
        \"patient\": {
          \"type\": \"object\",
          \"properties\": {
            \"age\": {\"type\": \"integer\", \"default\": 0}
          }
        }
      }
    }"

  let m = init_with(schema, dict.new())
  dict.get(m.values, "patient")
  |> should.equal(Ok(ObjectValue([#("age", IntegerValue(0))])))
}

pub fn partial_hydration_fills_missing_subfields_test() {
  let schema =
    "{
      \"type\": \"object\",
      \"properties\": {
        \"patient\": {
          \"type\": \"object\",
          \"properties\": {
            \"name\": {\"type\": \"string\"},
            \"age\": {\"type\": \"integer\", \"default\": 0}
          }
        }
      }
    }"

  let m =
    init_with(
      schema,
      dict.from_list([
        #("patient", ObjectValue([#("name", StringValue("X"))])),
      ]),
    )

  dict.get(m.values, "patient")
  |> should.equal(
    Ok(
      ObjectValue([
        #("name", StringValue("X")),
        #("age", IntegerValue(0)),
      ]),
    ),
  )
}

pub fn array_items_get_defaults_test() {
  let schema =
    "{
      \"type\": \"object\",
      \"properties\": {
        \"lesions\": {
          \"type\": \"array\",
          \"items\": {
            \"type\": \"object\",
            \"properties\": {
              \"size\": {\"type\": \"integer\"},
              \"side\": {\"type\": \"string\", \"default\": \"left\"}
            }
          }
        }
      }
    }"

  let m =
    init_with(
      schema,
      dict.from_list([
        #(
          "lesions",
          ArrayValue([
            ObjectValue([#("size", IntegerValue(5))]),
            ObjectValue([#("size", IntegerValue(8))]),
          ]),
        ),
      ]),
    )

  dict.get(m.values, "lesions")
  |> should.equal(
    Ok(
      ArrayValue([
        ObjectValue([
          #("size", IntegerValue(5)),
          #("side", StringValue("left")),
        ]),
        ObjectValue([
          #("size", IntegerValue(8)),
          #("side", StringValue("left")),
        ]),
      ]),
    ),
  )
}

pub fn empty_array_no_items_created_test() {
  let schema =
    "{
      \"type\": \"object\",
      \"properties\": {
        \"lesions\": {
          \"type\": \"array\",
          \"items\": {
            \"type\": \"object\",
            \"properties\": {
              \"side\": {\"type\": \"string\", \"default\": \"left\"}
            }
          }
        }
      }
    }"

  let m = init_with(schema, dict.from_list([#("lesions", ArrayValue([]))]))

  dict.get(m.values, "lesions")
  |> should.equal(Ok(ArrayValue([])))
}

pub fn array_absent_no_items_created_test() {
  let schema =
    "{
      \"type\": \"object\",
      \"properties\": {
        \"lesions\": {
          \"type\": \"array\",
          \"items\": {
            \"type\": \"object\",
            \"properties\": {
              \"side\": {\"type\": \"string\", \"default\": \"left\"}
            }
          }
        }
      }
    }"

  let m = init_with(schema, dict.new())
  dict.has_key(m.values, "lesions") |> should.be_false()
}

pub fn submit_includes_defaults_test() {
  let schema =
    "{
      \"type\": \"object\",
      \"properties\": {
        \"is_resected\": {\"type\": \"boolean\", \"default\": false}
      },
      \"required\": [\"is_resected\"]
    }"

  let m = init_with(schema, dict.new())
  let resolved = model.get_resolved_values(m)
  dict.get(resolved, "is_resected")
  |> should.equal(Ok(BooleanValue(False)))
}

pub fn extra_object_keys_preserved_test() {
  let schema =
    "{
      \"type\": \"object\",
      \"properties\": {
        \"patient\": {
          \"type\": \"object\",
          \"properties\": {
            \"name\": {\"type\": \"string\"},
            \"age\": {\"type\": \"integer\", \"default\": 0}
          }
        }
      }
    }"

  let m =
    init_with(
      schema,
      dict.from_list([
        #(
          "patient",
          ObjectValue([
            #("name", StringValue("X")),
            #("legacy_id", StringValue("42")),
          ]),
        ),
      ]),
    )

  dict.get(m.values, "patient")
  |> should.equal(
    Ok(
      ObjectValue([
        #("name", StringValue("X")),
        #("age", IntegerValue(0)),
        #("legacy_id", StringValue("42")),
      ]),
    ),
  )
}

pub fn reset_reapplies_defaults_test() {
  let schema =
    "{
      \"type\": \"object\",
      \"properties\": {
        \"is_resected\": {\"type\": \"boolean\", \"default\": false}
      },
      \"required\": [\"is_resected\"]
    }"

  let m =
    init_with(schema, dict.from_list([#("is_resected", BooleanValue(True))]))
  let after_reset = model.reset(m)
  dict.get(after_reset.values, "is_resected")
  |> should.equal(Ok(BooleanValue(False)))
}
