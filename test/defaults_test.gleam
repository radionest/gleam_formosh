import formosh/form/model
import formosh/form/path
import formosh/schema/parser
import formosh/schema/types.{
  ArrayValue, BooleanValue, IntegerValue, NullValue, ObjectValue, StringValue,
}
import gleam/dict
import gleam/option.{None, Some}
import gleeunit/should

fn init_with(schema_json: String, values: dict.Dict(String, types.Value)) {
  let assert Ok(schema) = parser.parse_schema(schema_json)
  model.init_with_full_config(schema, None, False, values)
}

fn read(m: model.FormModel, name: String) -> option.Option(types.Value) {
  model.get_value_at_path(m, path.from_field_name(name))
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
  read(m, "is_resected")
  |> should.equal(Some(BooleanValue(False)))
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
  read(m, "side")
  |> should.equal(Some(StringValue("left")))
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
  read(m, "flag")
  |> should.equal(Some(BooleanValue(True)))
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
  read(m, "flag")
  |> should.equal(Some(BooleanValue(False)))
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
  read(m, "name") |> should.equal(None)
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
  read(m, "patient")
  |> should.equal(Some(ObjectValue([#("age", IntegerValue(0))])))
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

  read(m, "patient")
  |> should.equal(
    Some(
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

  read(m, "lesions")
  |> should.equal(
    Some(
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

  read(m, "lesions")
  |> should.equal(Some(ArrayValue([])))
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
  read(m, "lesions") |> should.equal(None)
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
  path.get_at_path(resolved, path.from_field_name("is_resected"))
  |> should.equal(Some(BooleanValue(False)))
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

  read(m, "patient")
  |> should.equal(
    Some(
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
  model.get_value_at_path(after_reset, path.from_field_name("is_resected"))
  |> should.equal(Some(BooleanValue(False)))
}
