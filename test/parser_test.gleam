import formosh/schema/parser
import formosh/schema/types
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

pub fn simple_string_schema_test() {
  let json =
    "{
    \"title\": \"Simple String Field\",
    \"type\": \"string\",
    \"maxLength\": 100
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  case result {
    Ok(schema) -> {
      should.equal(schema.title, Some("Simple String Field"))
      should.equal(schema.field_type, types.StringType)

      case schema.string_constraints {
        Some(constraints) -> {
          should.equal(constraints.max_length, Some(100))
        }
        None -> panic as "Expected string constraints"
      }
    }
    Error(_) -> panic as "Parser should succeed"
  }
}

pub fn object_with_properties_test() {
  let json =
    "{
    \"title\": \"User Registration\",
    \"type\": \"object\",
    \"properties\": {
      \"name\": {
        \"type\": \"string\",
        \"minLength\": 2
      },
      \"age\": {
        \"type\": \"integer\",
        \"minimum\": 0,
        \"maximum\": 120
      }
    },
    \"required\": [\"name\"]
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  case result {
    Ok(schema) -> {
      should.equal(schema.title, Some("User Registration"))
      should.equal(schema.field_type, types.ObjectType)
      should.equal(schema.required, ["name"])

      // Check that properties were parsed
      let property_count = list.length(schema.properties)
      should.equal(property_count, 2)
    }
    Error(_) -> panic as "Parser should succeed"
  }
}

pub fn properties_preserve_source_order_test() {
  // Keys deliberately in non-alphabetical order to detect any reordering.
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"zeta\": {\"type\": \"string\"},
      \"alpha\": {\"type\": \"integer\"},
      \"mu\": {\"type\": \"boolean\"},
      \"beta\": {\"type\": \"number\"}
    }
  }"

  let assert Ok(schema) = parser.parse_schema(json)
  schema.properties
  |> list.map(fn(entry) { entry.0 })
  |> should.equal(["zeta", "alpha", "mu", "beta"])
}

pub fn array_item_subfields_preserve_source_order_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"items\": {
        \"type\": \"array\",
        \"items\": {
          \"type\": \"object\",
          \"properties\": {
            \"zeta\": {\"type\": \"string\"},
            \"alpha\": {\"type\": \"string\"},
            \"mu\": {\"type\": \"string\"}
          }
        }
      }
    }
  }"

  let assert Ok(schema) = parser.parse_schema(json)
  let assert Ok(items) = list.key_find(schema.properties, "items")
  let assert Some(item_schema) = items.items
  let assert Some(subfields) = item_schema.properties
  subfields
  |> list.map(fn(entry) { entry.0 })
  |> should.equal(["zeta", "alpha", "mu"])
}

pub fn nested_invalid_properties_fail_test() {
  // Recursive properties_decoder must fail-fast even when the malformed
  // value sits inside a nested object, not just at the root.
  parser.parse_schema(
    "{
      \"type\": \"object\",
      \"properties\": {
        \"outer\": {
          \"type\": \"object\",
          \"properties\": \"not-an-object\"
        }
      }
    }",
  )
  |> should.be_error()
}

pub fn nested_properties_preserve_source_order_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"outer\": {
        \"type\": \"object\",
        \"properties\": {
          \"z\": {\"type\": \"string\"},
          \"a\": {\"type\": \"string\"},
          \"m\": {\"type\": \"string\"}
        }
      }
    }
  }"

  let assert Ok(schema) = parser.parse_schema(json)
  let assert Ok(outer) = list.key_find(schema.properties, "outer")
  let assert Some(nested) = outer.properties
  nested
  |> list.map(fn(entry) { entry.0 })
  |> should.equal(["z", "a", "m"])
}

pub fn array_with_items_test() {
  let json =
    "{
    \"title\": \"Number List\",
    \"type\": \"array\",
    \"items\": {
      \"type\": \"number\",
      \"minimum\": 0
    }
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  case result {
    Ok(schema) -> {
      should.equal(schema.title, Some("Number List"))
      should.equal(schema.field_type, types.ArrayType)
    }
    Error(_) -> panic as "Parser should succeed"
  }
}

pub fn schema_without_title_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"name\": {
        \"type\": \"string\"
      }
    }
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  case result {
    Ok(schema) -> {
      should.equal(schema.title, None)
      should.equal(schema.field_type, types.ObjectType)

      let property_count = list.length(schema.properties)
      should.equal(property_count, 1)
    }
    Error(_) -> panic as "Parser should succeed for schema without title"
  }
}

pub fn one_of_with_const_title_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"best_series\": {
        \"type\": \"string\",
        \"oneOf\": [
          {\"const\": \"1.2.3.4.5\", \"title\": \"S1: T1 Axial (120 images)\"},
          {\"const\": \"1.2.3.4.6\", \"title\": \"S2: T2 Coronal (80 images)\"}
        ]
      }
    }
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  let assert Ok(schema) = result
  let assert Ok(prop) = list.key_find(schema.properties, "best_series")

  // field_type should be string
  should.equal(prop.field_type, Some(types.StringType))

  // one_of should contain 2 sub-schemas
  case prop.one_of {
    Some(schemas) -> {
      should.equal(list.length(schemas), 2)

      // First sub-schema
      let assert [first, second] = schemas
      should.equal(first.enum_values, Some([types.StringValue("1.2.3.4.5")]))
      should.equal(first.title, Some("S1: T1 Axial (120 images)"))

      // Second sub-schema
      should.equal(second.enum_values, Some([types.StringValue("1.2.3.4.6")]))
      should.equal(second.title, Some("S2: T2 Coronal (80 images)"))
    }
    None -> panic as "Expected one_of to be Some"
  }
}

pub fn one_of_without_title_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"value\": {
        \"type\": \"string\",
        \"oneOf\": [
          {\"const\": \"a\"},
          {\"const\": \"b\", \"title\": \"Option B\"}
        ]
      }
    }
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  let assert Ok(schema) = result
  let assert Ok(prop) = list.key_find(schema.properties, "value")

  case prop.one_of {
    Some(schemas) -> {
      should.equal(list.length(schemas), 2)

      let assert [first, second] = schemas
      // First has no title
      should.equal(first.title, None)
      should.equal(first.enum_values, Some([types.StringValue("a")]))

      // Second has a title
      should.equal(second.title, Some("Option B"))
      should.equal(second.enum_values, Some([types.StringValue("b")]))
    }
    None -> panic as "Expected one_of to be Some"
  }
}

pub fn invalid_json_test() {
  let json = "{ invalid json"

  let result = parser.parse_schema(json)
  should.be_error(result)
}

/// `properties` must be a JSON object — non-null wrong types (strings,
/// arrays, etc.) surface a decoding error instead of silently producing an
/// empty form.
pub fn properties_must_be_object_test() {
  parser.parse_schema("{\"type\": \"object\", \"properties\": \"oops\"}")
  |> should.be_error()

  // JSON null is "absent" for compound fields (stdlib decode.optional never
  // invokes the inner decoder on null). Nested properties always behaved
  // this way; since the root shares the node decoder (#70 unification), the
  // root now matches. Non-null wrong types below still fail the parse.
  let assert Ok(schema) =
    parser.parse_schema("{\"type\": \"object\", \"properties\": null}")
  schema.properties |> should.equal([])

  parser.parse_schema("{\"type\": \"object\", \"properties\": [1, 2, 3]}")
  |> should.be_error()
}

pub fn image_upload_widget_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"photos\": {
        \"type\": \"array\",
        \"title\": \"Photos\",
        \"items\": {\"type\": \"string\", \"format\": \"uri\"},
        \"x-widget\": \"image-upload\",
        \"x-accept\": \"image/*\",
        \"x-max-file-size\": 10485760
      }
    }
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  let assert Ok(schema) = result
  let assert Ok(prop) = list.key_find(schema.properties, "photos")

  should.equal(prop.field_type, Some(types.ArrayType))
  should.equal(prop.render_hints.widget, Some(types.ImageUploadWidget))
  should.equal(prop.title, Some("Photos"))

  case prop.render_hints.upload_config {
    Some(config) -> {
      should.equal(config.accept, "image/*")
      should.equal(config.max_file_size, Some(10_485_760))
    }
    None -> panic as "Expected upload_config to be Some"
  }

  // Items should be string with uri format
  case prop.items {
    Some(items_prop) -> {
      should.equal(items_prop.field_type, Some(types.StringType))
    }
    None -> panic as "Expected items to be Some"
  }
}

pub fn image_upload_defaults_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"photos\": {
        \"type\": \"array\",
        \"x-widget\": \"image-upload\"
      }
    }
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  let assert Ok(schema) = result
  let assert Ok(prop) = list.key_find(schema.properties, "photos")

  should.equal(prop.render_hints.widget, Some(types.ImageUploadWidget))

  // upload_config should have default accept and no max_file_size
  case prop.render_hints.upload_config {
    Some(config) -> {
      should.equal(config.accept, "image/*")
      should.equal(config.max_file_size, None)
    }
    None -> panic as "Expected upload_config to be Some"
  }
}

pub fn no_widget_property_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"name\": {\"type\": \"string\"}
    }
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  let assert Ok(schema) = result
  let assert Ok(prop) = list.key_find(schema.properties, "name")

  should.equal(prop.render_hints.widget, None)
  should.equal(prop.render_hints.upload_config, None)
}

pub fn image_upload_custom_accept_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"documents\": {
        \"type\": \"array\",
        \"x-widget\": \"image-upload\",
        \"x-accept\": \"application/pdf\",
        \"x-max-file-size\": 5242880
      }
    }
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  let assert Ok(schema) = result
  let assert Ok(prop) = list.key_find(schema.properties, "documents")

  should.equal(prop.render_hints.widget, Some(types.ImageUploadWidget))
  case prop.render_hints.upload_config {
    Some(config) -> {
      should.equal(config.accept, "application/pdf")
      should.equal(config.max_file_size, Some(5_242_880))
    }
    None -> panic as "Expected upload_config to be Some"
  }
}

pub fn array_addable_removable_defaults_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"items\": {
        \"type\": \"array\",
        \"items\": { \"type\": \"string\" }
      }
    }
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  let assert Ok(schema) = result
  let assert Ok(prop) = list.key_find(schema.properties, "items")

  should.be_true(prop.addable)
  should.be_true(prop.removable)
}

pub fn array_addable_removable_explicit_false_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"items\": {
        \"type\": \"array\",
        \"x-addable\": false,
        \"x-removable\": false,
        \"items\": { \"type\": \"string\" }
      }
    }
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  let assert Ok(schema) = result
  let assert Ok(prop) = list.key_find(schema.properties, "items")

  should.be_false(prop.addable)
  should.be_false(prop.removable)
}

pub fn array_addable_removable_independent_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"items\": {
        \"type\": \"array\",
        \"x-addable\": true,
        \"x-removable\": false,
        \"items\": { \"type\": \"string\" }
      }
    }
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  let assert Ok(schema) = result
  let assert Ok(prop) = list.key_find(schema.properties, "items")

  should.be_true(prop.addable)
  should.be_false(prop.removable)
}

pub fn union_type_string_null_parses_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"user_id\": { \"type\": [\"string\", \"null\"], \"title\": \"Author\" }
    }
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  let assert Ok(schema) = result
  let assert Ok(prop) = list.key_find(schema.properties, "user_id")
  should.equal(prop.field_type, Some(types.StringType))
}

pub fn union_type_null_first_parses_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"user_id\": { \"type\": [\"null\", \"string\"] }
    }
  }"

  let assert Ok(schema) = parser.parse_schema(json)
  let assert Ok(prop) = list.key_find(schema.properties, "user_id")
  should.equal(prop.field_type, Some(types.StringType))
}

pub fn union_type_integer_null_parses_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"age\": { \"type\": [\"integer\", \"null\"] }
    }
  }"

  let assert Ok(schema) = parser.parse_schema(json)
  let assert Ok(prop) = list.key_find(schema.properties, "age")
  should.equal(prop.field_type, Some(types.IntegerType))
}

pub fn union_type_without_null_takes_first_known_test() {
  // Pure union without null: reduced to the first known type (not a parse
  // failure) so a multi-type schema still renders — see field_type_decoder doc.
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"mixed\": { \"type\": [\"string\", \"number\"] }
    }
  }"

  let assert Ok(schema) = parser.parse_schema(json)
  let assert Ok(prop) = list.key_find(schema.properties, "mixed")
  should.equal(prop.field_type, Some(types.StringType))
}

pub fn hidden_widget_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"tenant_id\": {
        \"type\": \"string\",
        \"x-widget\": \"hidden\",
        \"default\": \"acme\"
      }
    }
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  let assert Ok(schema) = result
  let assert Ok(prop) = list.key_find(schema.properties, "tenant_id")

  should.equal(prop.render_hints.widget, Some(types.HiddenWidget))
  should.equal(prop.default, Some(types.StringValue("acme")))
}

pub fn union_type_null_only_resolves_to_null_type_test() {
  // The whole point of the fix: a degenerate `type` array (here only "null")
  // must NOT abort the schema parse — it resolves to NullType.
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"nothing\": { \"type\": [\"null\"] }
    }
  }"

  let assert Ok(schema) = parser.parse_schema(json)
  let assert Ok(prop) = list.key_find(schema.properties, "nothing")
  should.equal(prop.field_type, Some(types.NullType))
}

pub fn array_constraints_parsed_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"tags\": {
        \"type\": \"array\",
        \"minItems\": 1,
        \"maxItems\": 5,
        \"items\": {\"type\": \"string\"}
      }
    }
  }"

  let assert Ok(schema) = parser.parse_schema(json)
  let assert Ok(#(_, tags)) =
    list.find(schema.properties, fn(entry) { entry.0 == "tags" })
  tags.array_constraints
  |> should.equal(
    Some(types.ArrayConstraints(
      min_items: Some(1),
      max_items: Some(5),
      unique_items: False,
    )),
  )
}

pub fn array_constraints_min_only_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"tags\": {\"type\": \"array\", \"minItems\": 2, \"items\": {\"type\": \"string\"}}
    }
  }"

  let assert Ok(schema) = parser.parse_schema(json)
  let assert Ok(#(_, tags)) =
    list.find(schema.properties, fn(entry) { entry.0 == "tags" })
  tags.array_constraints
  |> should.equal(
    Some(types.ArrayConstraints(
      min_items: Some(2),
      max_items: None,
      unique_items: False,
    )),
  )
}

pub fn array_constraints_absent_is_none_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"tags\": {\"type\": \"array\", \"items\": {\"type\": \"string\"}}
    }
  }"

  let assert Ok(schema) = parser.parse_schema(json)
  let assert Ok(#(_, tags)) =
    list.find(schema.properties, fn(entry) { entry.0 == "tags" })
  tags.array_constraints |> should.equal(None)
}

pub fn array_constraints_min_above_max_normalizes_test() {
  // minItems > maxItems is unsatisfiable; the parser normalizes it so
  // minItems wins — otherwise reconcile tops the array up past maxItems
  // and wedges the form (both buttons hidden, submit blocked).
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"tags\": {\"type\": \"array\", \"minItems\": 3, \"maxItems\": 1, \"items\": {\"type\": \"string\"}}
    }
  }"

  let assert Ok(schema) = parser.parse_schema(json)
  let assert Ok(#(_, tags)) =
    list.find(schema.properties, fn(entry) { entry.0 == "tags" })
  tags.array_constraints
  |> should.equal(
    Some(types.ArrayConstraints(
      min_items: Some(3),
      max_items: Some(3),
      unique_items: False,
    )),
  )
}

pub fn crossed_array_bounds_clamped_everywhere_test() {
  // No merge below rejects its crossing, so each one clamps to minItems —
  // wherever the runtime reads it: nested, items, $ref'd, union branches,
  // oneOf members, conditional branches.
  let json =
    "{
    \"type\": \"object\",
    \"$defs\": {
      \"Crossed\": {\"type\": \"array\", \"minItems\": 5, \"maxItems\": 3},
      \"Free\": {\"type\": \"array\"}
    },
    \"properties\": {
      \"plain\": {\"type\": \"array\", \"minItems\": 5, \"maxItems\": 3},
      \"nested\": {\"type\": \"object\", \"properties\": {
        \"inner\": {\"type\": \"array\", \"minItems\": 5, \"maxItems\": 3}
      }},
      \"grid\": {\"type\": \"array\", \"items\": {\"type\": \"array\", \"minItems\": 5, \"maxItems\": 3}},
      \"via_ref\": {\"$ref\": \"#/$defs/Crossed\"},
      \"ref_sibling\": {\"$ref\": \"#/$defs/Free\", \"minItems\": 5, \"maxItems\": 3},
      \"ref_crossed_plus_bound\": {\"$ref\": \"#/$defs/Crossed\", \"maxItems\": 1},
      \"union\": {\"type\": \"array\", \"minItems\": 5, \"maxItems\": 3, \"anyOf\": [
        {\"type\": \"array\", \"minItems\": 5, \"maxItems\": 3, \"items\": {\"type\": \"string\"}},
        {\"type\": \"array\", \"items\": {\"type\": \"integer\"}}
      ]},
      \"choice\": {\"oneOf\": [{\"type\": \"array\", \"minItems\": 5, \"maxItems\": 3}]}
    },
    \"if\": {\"properties\": {\"when\": {\"type\": \"array\", \"minItems\": 5, \"maxItems\": 3}}},
    \"then\": {\"properties\": {\"yes\": {\"type\": \"array\", \"minItems\": 5, \"maxItems\": 3}}},
    \"else\": {\"properties\": {\"no\": {\"type\": \"array\", \"minItems\": 5, \"maxItems\": 3}}}
  }"

  let assert Ok(schema) = parser.parse_schema(json)
  types.SchemaProperty(
    ..types.empty_property(),
    properties: Some(schema.properties),
    conditionals: schema.conditionals,
  )
  |> item_bounds("#")
  |> should.equal([
    #("#/plain", 5, 5),
    #("#/nested/inner", 5, 5),
    #("#/grid/items", 5, 5),
    #("#/via_ref", 5, 5),
    #("#/ref_sibling", 5, 5),
    #("#/ref_crossed_plus_bound", 5, 5),
    #("#/union", 5, 5),
    #("#/union/anyOf/0", 5, 5),
    #("#/choice/oneOf/0", 5, 5),
    #("#/if/when", 5, 5),
    #("#/then/yes", 5, 5),
    #("#/else/no", 5, 5),
  ])
}

/// Every `#(path, minItems, maxItems)` in a parsed tree. Walked here rather
/// than by the parser, so a subtree its clamp pass skips shows up crossed.
fn item_bounds(
  prop: types.SchemaProperty,
  path: String,
) -> List(#(String, Int, Int)) {
  let sub = fn(child, key) { item_bounds(child, path <> "/" <> key) }
  let indexed = fn(members, key) {
    option.unwrap(members, [])
    |> list.index_map(fn(m, i) { sub(m, key <> "/" <> int.to_string(i)) })
    |> list.flatten
  }
  let own = case prop.array_constraints {
    Some(types.ArrayConstraints(min_items: Some(min), max_items: Some(max), ..)) -> [
      #(path, min, max),
    ]
    _ -> []
  }
  list.flatten([
    own,
    list.flat_map(option.unwrap(prop.properties, []), fn(e) { sub(e.1, e.0) }),
    option.map(prop.items, sub(_, "items")) |> option.unwrap([]),
    indexed(prop.any_of, "anyOf"),
    indexed(prop.one_of, "oneOf"),
    list.flat_map(prop.conditionals, fn(rule) {
      list.flatten([
        sub(rule.if_schema, "if"),
        option.map(rule.then_schema, sub(_, "then")) |> option.unwrap([]),
        option.map(rule.else_schema, sub(_, "else")) |> option.unwrap([]),
      ])
    }),
  ])
}

fn parsed_root_format(json: String) -> option.Option(types.StringFormat) {
  let assert Ok(schema) = parser.parse_schema(json)
  case schema.string_constraints {
    Some(constraints) -> constraints.format
    None -> panic as "Expected string constraints"
  }
}

pub fn date_format_decodes_to_date_format_test() {
  parsed_root_format("{\"type\": \"string\", \"format\": \"date\"}")
  |> should.equal(Some(types.DateFormat))
}

pub fn time_format_decodes_to_time_format_test() {
  parsed_root_format("{\"type\": \"string\", \"format\": \"time\"}")
  |> should.equal(Some(types.TimeFormat))
}

pub fn password_format_decodes_to_password_format_test() {
  parsed_root_format("{\"type\": \"string\", \"format\": \"password\"}")
  |> should.equal(Some(types.PasswordFormat))
}

// Deliberate non-promotion — see docs/reference/widgets.md ("HTML input
// type from `format`"). RFC 3339 date-time requires a UTC offset that
// <input type="datetime-local"> rejects, so wiring it would silently blank
// the input for every offset-bearing backend value.
pub fn date_time_format_stays_custom_test() {
  parsed_root_format("{\"type\": \"string\", \"format\": \"date-time\"}")
  |> should.equal(Some(types.CustomFormat("date-time")))
}

pub fn unknown_format_stays_custom_test() {
  parsed_root_format("{\"type\": \"string\", \"format\": \"ipv4\"}")
  |> should.equal(Some(types.CustomFormat("ipv4")))
}
