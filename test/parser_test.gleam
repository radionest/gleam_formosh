import formosh/schema/parser
import formosh/schema/types
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

pub fn crossed_array_bounds_normalize_per_schema_object_test() {
  // Crossed minItems > maxItems is clamped within each schema object at
  // decode, before any $ref/allOf/anyOf merge — by design, see
  // docs/reference/schema-keywords.md#array-structure.
  let rows = [
    #(
      "on a node with allOf",
      "\"properties\":{\"x\":{\"type\":\"array\",\"minItems\":5,\"maxItems\":3,\"allOf\":[{\"title\":\"t\"}]}}",
    ),
    #(
      "in a property of an allOf member",
      "\"properties\":{\"x\":{\"type\":\"array\"}},\"allOf\":[{\"properties\":{\"x\":{\"type\":\"array\",\"minItems\":5,\"maxItems\":3}}}]",
    ),
    #(
      "in a $defs entry behind $ref",
      "\"$defs\":{\"D\":{\"type\":\"array\",\"minItems\":5,\"maxItems\":3}},\"properties\":{\"x\":{\"$ref\":\"#/$defs/D\"}}",
    ),
    #(
      "in the anyOf survivor",
      "\"properties\":{\"x\":{\"anyOf\":[{\"type\":\"array\",\"minItems\":5,\"maxItems\":3},{\"type\":\"null\"}]}}",
    ),
    #(
      "in an allOf member",
      "\"properties\":{\"x\":{\"type\":\"array\",\"allOf\":[{\"minItems\":5,\"maxItems\":3}]}}",
    ),
    #(
      "on a $ref node with allOf",
      "\"$defs\":{\"D\":{\"type\":\"array\"}},\"properties\":{\"x\":{\"$ref\":\"#/$defs/D\",\"minItems\":5,\"maxItems\":3,\"allOf\":[{\"title\":\"t\"}]}}",
    ),
    #(
      "on a $ref node whose def has allOf",
      "\"$defs\":{\"A\":{\"type\":\"array\",\"allOf\":[{\"title\":\"t\"}]}},\"properties\":{\"x\":{\"$ref\":\"#/$defs/A\",\"minItems\":5,\"maxItems\":3}}",
    ),
    #(
      "in a $defs entry used as an allOf member",
      "\"$defs\":{\"D\":{\"type\":\"array\",\"minItems\":5,\"maxItems\":3}},\"properties\":{\"x\":{\"type\":\"array\",\"allOf\":[{\"$ref\":\"#/$defs/D\"}]}}",
    ),
    #(
      "on a type [array, null] node",
      "\"properties\":{\"x\":{\"type\":[\"array\",\"null\"],\"minItems\":5,\"maxItems\":3}}",
    ),
  ]
  let clamped =
    Some(types.ArrayConstraints(
      min_items: Some(5),
      max_items: Some(5),
      unique_items: False,
    ))
  list.each(rows, fn(row) {
    let #(label, fragment) = row
    let assert Ok(schema) =
      parser.parse_schema("{\"type\":\"object\"," <> fragment <> "}")
      as { "crossed bounds " <> label <> " failed to parse" }
    let assert Ok(x) = list.key_find(schema.properties, "x")
    #(label, x.array_constraints) |> should.equal(#(label, clamped))
  })
}

pub fn crossed_array_bounds_in_any_of_member_items_normalize_test() {
  // The survivor's `items` is a schema object of its own, clamped
  // at decode before the anyOf collapse merges it into `x.items`.
  let assert Ok(schema) =
    parser.parse_schema(
      "{\"type\":\"object\",\"properties\":{\"x\":{\"type\":\"array\",\"items\":{\"type\":\"array\"},\"anyOf\":[{\"items\":{\"type\":\"array\",\"minItems\":5,\"maxItems\":3}},{\"type\":\"null\"}]}}}",
    )
  let assert Ok(x) = list.key_find(schema.properties, "x")
  let assert Some(items) = x.items
  items.array_constraints
  |> should.equal(
    Some(types.ArrayConstraints(
      min_items: Some(5),
      max_items: Some(5),
      unique_items: False,
    )),
  )
}

pub fn crossed_array_bounds_in_then_branch_normalize_test() {
  // An if/then/else branch is a schema object of its own.
  let assert Ok(schema) =
    parser.parse_schema(
      "{\"type\":\"object\",\"properties\":{\"a\":{\"type\":\"string\"}},\"if\":{\"properties\":{\"a\":{\"const\":\"y\"}}},\"then\":{\"properties\":{\"arr\":{\"type\":\"array\",\"minItems\":5,\"maxItems\":3}}}}",
    )
  let assert [rule] = schema.conditionals
  let assert Some(then_schema) = rule.then_schema
  let assert Some(then_properties) = then_schema.properties
  let assert Ok(arr) = list.key_find(then_properties, "arr")
  arr.array_constraints
  |> should.equal(
    Some(types.ArrayConstraints(
      min_items: Some(5),
      max_items: Some(5),
      unique_items: False,
    )),
  )
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
