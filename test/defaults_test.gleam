import formosh/form/defaults
import formosh/form/model
import formosh/form/path
import formosh/schema/parser
import formosh/schema/types.{
  ArrayValue, BooleanValue, IntegerValue, NullValue, ObjectValue, StringValue,
}
import formosh/schema/ui_schema
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

fn init_with(schema_json: String, values: dict.Dict(String, types.Value)) {
  let assert Ok(schema) = parser.parse_schema(schema_json)
  model.init_with_full_config(
    schema,
    None,
    False,
    values,
    ui_schema.empty_ui_schema(),
  )
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

// `extra_object_keys_preserved_test` covers the basic "extras survive"
// case but only one declared key carries a default. This pins the more
// involved mix: multiple declared keys (one with a hydrated value, one
// with a missing default) interleaved with extras at arbitrary
// positions. Expected order is *all declared* (in schema order) followed
// by *all extras* (in the caller's original order) — extras must never
// jump ahead of the declared block, even if the user supplied them
// first.
pub fn declared_with_defaults_and_extras_order_test() {
  let schema =
    "{
      \"type\": \"object\",
      \"properties\": {
        \"patient\": {
          \"type\": \"object\",
          \"properties\": {
            \"name\": {\"type\": \"string\"},
            \"age\": {\"type\": \"integer\", \"default\": 0},
            \"role\": {\"type\": \"string\", \"default\": \"patient\"}
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
            // Caller order: extra, declared (hydrated), extra, declared
            // (missing → default fills), extra. Schema order is name,
            // age, role.
            #("legacy_a", StringValue("first")),
            #("name", StringValue("Ada")),
            #("legacy_b", StringValue("second")),
            #("age", IntegerValue(42)),
            #("legacy_c", StringValue("third")),
          ]),
        ),
      ]),
    )

  read(m, "patient")
  |> should.equal(
    Some(
      ObjectValue([
        // Declared block in schema order; `role` came from the default.
        #("name", StringValue("Ada")),
        #("age", IntegerValue(42)),
        #("role", StringValue("patient")),
        // Extras in caller order, after the declared block.
        #("legacy_a", StringValue("first")),
        #("legacy_b", StringValue("second")),
        #("legacy_c", StringValue("third")),
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

// --- new_array_item ----------------------------------------------------------

fn item_schema_of(
  schema_json: String,
  array_name: String,
) -> types.SchemaProperty {
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(#(_, prop)) =
    list.find(schema.properties, fn(entry) { entry.0 == array_name })
  let assert Some(item_schema) = prop.items
  item_schema
}

pub fn new_array_item_object_with_defaults_test() {
  let item =
    item_schema_of(
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
      "lesions",
    )
  defaults.new_array_item(item)
  |> should.equal(ObjectValue([#("diffuse", BooleanValue(False))]))
}

pub fn new_array_item_object_without_defaults_test() {
  let item =
    item_schema_of(
      "{
      \"type\": \"object\",
      \"properties\": {
        \"lesions\": {
          \"type\": \"array\",
          \"items\": {
            \"type\": \"object\",
            \"properties\": {\"form\": {\"type\": \"string\"}}
          }
        }
      }
    }",
      "lesions",
    )
  defaults.new_array_item(item)
  |> should.equal(ObjectValue([]))
}

pub fn new_array_item_scalar_with_default_test() {
  let item =
    item_schema_of(
      "{
      \"type\": \"object\",
      \"properties\": {
        \"tags\": {
          \"type\": \"array\",
          \"items\": {\"type\": \"string\", \"default\": \"x\"}
        }
      }
    }",
      "tags",
    )
  defaults.new_array_item(item)
  |> should.equal(StringValue("x"))
}

pub fn new_array_item_scalar_without_default_test() {
  let item =
    item_schema_of(
      "{
      \"type\": \"object\",
      \"properties\": {
        \"tags\": {\"type\": \"array\", \"items\": {\"type\": \"string\"}}
      }
    }",
      "tags",
    )
  defaults.new_array_item(item)
  |> should.equal(NullValue)
}

// --- ensure_min_items --------------------------------------------------------

fn props_of(schema_json: String) -> List(#(String, types.SchemaProperty)) {
  let assert Ok(schema) = parser.parse_schema(schema_json)
  schema.properties
}

const min_items_schema = "{
  \"type\": \"object\",
  \"properties\": {
    \"tags\": {
      \"type\": \"array\",
      \"minItems\": 2,
      \"items\": {\"type\": \"string\", \"default\": \"x\"}
    }
  }
}"

const conditional_lesions_schema = "{
  \"type\": \"object\",
  \"properties\": {
    \"zones\": {
      \"type\": \"array\",
      \"items\": {
        \"type\": \"object\",
        \"properties\": {\"affected\": {\"type\": \"boolean\"}},
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

pub fn ensure_min_items_creates_missing_array_test() {
  defaults.ensure_min_items(props_of(min_items_schema), ObjectValue([]))
  |> should.equal(
    ObjectValue([#("tags", ArrayValue([StringValue("x"), StringValue("x")]))]),
  )
}

pub fn ensure_min_items_tops_up_partial_array_test() {
  defaults.ensure_min_items(
    props_of(min_items_schema),
    ObjectValue([#("tags", ArrayValue([StringValue("a")]))]),
  )
  |> should.equal(
    ObjectValue([#("tags", ArrayValue([StringValue("a"), StringValue("x")]))]),
  )
}

pub fn ensure_min_items_idempotent_test() {
  let once =
    defaults.ensure_min_items(props_of(min_items_schema), ObjectValue([]))
  defaults.ensure_min_items(props_of(min_items_schema), once)
  |> should.equal(once)
}

pub fn ensure_min_items_never_removes_surplus_rows_test() {
  let values =
    ObjectValue([
      #(
        "tags",
        ArrayValue([StringValue("a"), StringValue("b"), StringValue("c")]),
      ),
    ])
  defaults.ensure_min_items(props_of(min_items_schema), values)
  |> should.equal(values)
}

pub fn ensure_min_items_leaves_unconstrained_arrays_test() {
  let schema =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"tags\": {\"type\": \"array\", \"items\": {\"type\": \"string\"}}
    }
  }"
  defaults.ensure_min_items(props_of(schema), ObjectValue([]))
  |> should.equal(ObjectValue([]))
}

pub fn ensure_min_items_creates_conditionally_revealed_array_test() {
  let values =
    ObjectValue([
      #(
        "zones",
        ArrayValue([
          ObjectValue([#("affected", BooleanValue(True))]),
          ObjectValue([#("affected", BooleanValue(False))]),
        ]),
      ),
    ])
  let result =
    defaults.ensure_min_items(props_of(conditional_lesions_schema), values)

  // Row 0 (affected): lesions created with one default-hydrated row.
  path.get_at_path(result, [
    path.PropertySegment("zones"),
    path.ArraySegment(0),
    path.PropertySegment("lesions"),
  ])
  |> should.equal(
    Some(ArrayValue([ObjectValue([#("diffuse", BooleanValue(False))])])),
  )

  // Row 1 (not affected): no lesions key at all.
  path.get_at_path(result, [
    path.PropertySegment("zones"),
    path.ArraySegment(1),
    path.PropertySegment("lesions"),
  ])
  |> should.equal(None)
}
