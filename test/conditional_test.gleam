/// Tests for JSON Schema conditional logic (if/then/else)
import formosh/form/model
import formosh/form/path
import formosh/form/update
import formosh/schema/conditional_resolver
import formosh/schema/parser
import formosh/schema/types.{
  type SchemaProperty, BooleanValue, ConditionalRule, IntegerValue, JsonSchema,
  ObjectValue, SchemaProperty, StringValue, empty_property, has_property_key,
}
import gleam/list
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

fn has_field(value: types.Value, name: String) -> Bool {
  path.get_at_path(value, path.from_field_name(name)) |> option.is_some
}

/// Test that conditional fields are added when condition is met
pub fn conditional_field_appears_when_condition_met_test() {
  // Create a schema with conditional logic similar to contact form
  let base_properties = [#("subject", empty_property())]

  // Create conditional rule: if subject == "Общий вопрос", then add is_confidential field
  let if_condition =
    SchemaProperty(
      ..empty_property(),
      properties: Some([
        #(
          "subject",
          SchemaProperty(
            ..empty_property(),
            enum_values: Some([StringValue("Общий вопрос")]),
          ),
        ),
      ]),
    )

  let then_schema =
    SchemaProperty(
      ..empty_property(),
      properties: Some([
        #(
          "is_confidential",
          SchemaProperty(
            ..empty_property(),
            field_type: Some(types.BooleanType),
            title: Some("Конфиденциально"),
          ),
        ),
      ]),
    )

  let conditional_rule =
    ConditionalRule(
      if_schema: if_condition,
      then_schema: Some(then_schema),
      else_schema: None,
    )

  let schema =
    JsonSchema(
      title: Some("Test Form"),
      description: None,
      field_type: types.ObjectType,
      properties: base_properties,
      required: [],
      defs: None,
      conditionals: [conditional_rule],
      string_constraints: None,
      number_constraints: None,
    )

  // Test when condition is met
  let form_values_met =
    ObjectValue([
      #("subject", StringValue("Общий вопрос")),
    ])

  let resolved_schema =
    conditional_resolver.resolve_conditional_schema(schema, form_values_met)

  // Check that is_confidential field was added
  resolved_schema.properties
  |> has_property_key("is_confidential")
  |> should.be_true()

  // Test when condition is not met
  let form_values_not_met =
    ObjectValue([
      #("subject", StringValue("Техническая поддержка")),
    ])

  let resolved_schema_no_match =
    conditional_resolver.resolve_conditional_schema(schema, form_values_not_met)

  // Check that is_confidential field was NOT added
  resolved_schema_no_match.properties
  |> has_property_key("is_confidential")
  |> should.be_false()
}

/// Test that else branch is applied when condition is not met
pub fn conditional_else_branch_test() {
  let base_properties = [#("hasAccount", empty_property())]

  // If hasAccount == true, show login field, else show registration fields
  let if_condition =
    SchemaProperty(
      ..empty_property(),
      properties: Some([
        #(
          "hasAccount",
          SchemaProperty(
            ..empty_property(),
            enum_values: Some([types.BooleanValue(True)]),
          ),
        ),
      ]),
    )

  let then_schema =
    SchemaProperty(
      ..empty_property(),
      properties: Some([
        #(
          "username",
          SchemaProperty(
            ..empty_property(),
            field_type: Some(types.StringType),
            title: Some("Username"),
          ),
        ),
      ]),
    )

  let else_schema =
    SchemaProperty(
      ..empty_property(),
      properties: Some([
        #(
          "email",
          SchemaProperty(
            ..empty_property(),
            field_type: Some(types.StringType),
            title: Some("Email"),
          ),
        ),
        #(
          "password",
          SchemaProperty(
            ..empty_property(),
            field_type: Some(types.StringType),
            title: Some("Password"),
          ),
        ),
      ]),
    )

  let conditional_rule =
    ConditionalRule(
      if_schema: if_condition,
      then_schema: Some(then_schema),
      else_schema: Some(else_schema),
    )

  let schema =
    JsonSchema(
      title: Some("Test Form"),
      description: None,
      field_type: types.ObjectType,
      properties: base_properties,
      required: [],
      defs: None,
      conditionals: [conditional_rule],
      string_constraints: None,
      number_constraints: None,
    )

  // Test when hasAccount is true (then branch)
  let form_values_true =
    ObjectValue([
      #("hasAccount", BooleanValue(True)),
    ])

  let resolved_then =
    conditional_resolver.resolve_conditional_schema(schema, form_values_true)

  // Should have username field
  resolved_then.properties
  |> has_property_key("username")
  |> should.be_true()

  // Should NOT have email/password fields
  resolved_then.properties
  |> has_property_key("email")
  |> should.be_false()

  // Test when hasAccount is false (else branch)
  let form_values_false =
    ObjectValue([
      #("hasAccount", BooleanValue(False)),
    ])

  let resolved_else =
    conditional_resolver.resolve_conditional_schema(schema, form_values_false)

  // Should NOT have username field
  resolved_else.properties
  |> has_property_key("username")
  |> should.be_false()

  // Should have email/password fields
  resolved_else.properties
  |> has_property_key("email")
  |> should.be_true()

  resolved_else.properties
  |> has_property_key("password")
  |> should.be_true()
}

/// Test field visibility helper function
pub fn is_field_visible_test() {
  // Set up schema with conditional field
  let base_properties = [
    #("subject", empty_property()),
    #("message", empty_property()),
    // This field is always visible
  ]

  let if_condition =
    SchemaProperty(
      ..empty_property(),
      properties: Some([
        #(
          "subject",
          SchemaProperty(
            ..empty_property(),
            enum_values: Some([StringValue("Special")]),
          ),
        ),
      ]),
    )

  let then_schema =
    SchemaProperty(
      ..empty_property(),
      properties: Some([#("special_field", empty_property())]),
    )

  let conditional_rule =
    ConditionalRule(
      if_schema: if_condition,
      then_schema: Some(then_schema),
      else_schema: None,
    )

  let schema =
    JsonSchema(
      title: Some("Test Form"),
      description: None,
      field_type: types.ObjectType,
      properties: base_properties,
      required: [],
      defs: None,
      conditionals: [conditional_rule],
      string_constraints: None,
      number_constraints: None,
    )

  let form_values_met =
    ObjectValue([
      #("subject", StringValue("Special")),
    ])

  let form_values_not_met =
    ObjectValue([
      #("subject", StringValue("Normal")),
    ])

  // Base field should always be visible
  conditional_resolver.is_field_visible("message", schema, form_values_met)
  |> should.be_true()

  conditional_resolver.is_field_visible("message", schema, form_values_not_met)
  |> should.be_true()

  // Conditional field should only be visible when condition is met
  conditional_resolver.is_field_visible(
    "special_field",
    schema,
    form_values_met,
  )
  |> should.be_true()

  conditional_resolver.is_field_visible(
    "special_field",
    schema,
    form_values_not_met,
  )
  |> should.be_false()
}

/// Test multiple conditionals via allOf array
pub fn multiple_conditionals_allof_test() {
  let schema_json =
    "{
      \"title\": \"Test Form\",
      \"type\": \"object\",
      \"properties\": {
        \"air_bubble\": {\"type\": \"boolean\"},
        \"pneumoperitoneum\": {\"type\": \"boolean\"}
      },
      \"allOf\": [
        {
          \"if\": {\"properties\": {\"air_bubble\": {\"const\": true}}},
          \"then\": {
            \"properties\": {
              \"air_bubble_size\": {\"type\": \"number\", \"title\": \"Bubble Size\"}
            }
          }
        },
        {
          \"if\": {\"properties\": {\"pneumoperitoneum\": {\"const\": true}}},
          \"then\": {
            \"properties\": {
              \"pneumo_thickness\": {\"type\": \"number\", \"title\": \"Thickness\"}
            }
          }
        }
      ]
    }"

  // Parse the schema
  let assert Ok(parsed_schema) = parser.parse_schema(schema_json)

  // Check that we have 2 conditional rules
  parsed_schema.conditionals
  |> list.length()
  |> should.equal(2)

  // Test when air_bubble is true
  let form_values_air = ObjectValue([#("air_bubble", BooleanValue(True))])

  let resolved_air =
    conditional_resolver.resolve_conditional_schema(
      parsed_schema,
      form_values_air,
    )

  // Should have air_bubble_size field
  resolved_air.properties
  |> has_property_key("air_bubble_size")
  |> should.be_true()

  // Should NOT have pneumo_thickness field
  resolved_air.properties
  |> has_property_key("pneumo_thickness")
  |> should.be_false()

  // Test when pneumoperitoneum is true
  let form_values_pneumo =
    ObjectValue([#("pneumoperitoneum", BooleanValue(True))])

  let resolved_pneumo =
    conditional_resolver.resolve_conditional_schema(
      parsed_schema,
      form_values_pneumo,
    )

  // Should have pneumo_thickness field
  resolved_pneumo.properties
  |> has_property_key("pneumo_thickness")
  |> should.be_true()

  // Should NOT have air_bubble_size field
  resolved_pneumo.properties
  |> has_property_key("air_bubble_size")
  |> should.be_false()

  // Test when both are true
  let form_values_both =
    ObjectValue([
      #("air_bubble", BooleanValue(True)),
      #("pneumoperitoneum", BooleanValue(True)),
    ])

  let resolved_both =
    conditional_resolver.resolve_conditional_schema(
      parsed_schema,
      form_values_both,
    )

  // Should have both conditional fields
  resolved_both.properties
  |> has_property_key("air_bubble_size")
  |> should.be_true()

  resolved_both.properties
  |> has_property_key("pneumo_thickness")
  |> should.be_true()
}

/// Test that const keyword is parsed correctly
pub fn const_keyword_parsing_test() {
  let schema_json =
    "{
      \"title\": \"Test Form\",
      \"type\": \"object\",
      \"properties\": {
        \"flag\": {\"type\": \"boolean\"}
      },
      \"if\": {\"properties\": {\"flag\": {\"const\": true}}},
      \"then\": {
        \"properties\": {
          \"extra_field\": {\"type\": \"string\"}
        }
      }
    }"

  let assert Ok(parsed_schema) = parser.parse_schema(schema_json)

  // Test that const: true works like enum: [true]
  let form_values_true = ObjectValue([#("flag", BooleanValue(True))])

  let resolved_true =
    conditional_resolver.resolve_conditional_schema(
      parsed_schema,
      form_values_true,
    )

  resolved_true.properties
  |> has_property_key("extra_field")
  |> should.be_true()

  // Test that const: false doesn't match true
  let form_values_false = ObjectValue([#("flag", BooleanValue(False))])

  let resolved_false =
    conditional_resolver.resolve_conditional_schema(
      parsed_schema,
      form_values_false,
    )

  resolved_false.properties
  |> has_property_key("extra_field")
  |> should.be_false()
}

/// Test that get_resolved_values filters out hidden conditional fields
pub fn get_resolved_values_filters_hidden_fields_test() {
  let schema_json =
    "{
      \"title\": \"Test Form\",
      \"type\": \"object\",
      \"properties\": {
        \"flag\": {\"type\": \"boolean\"},
        \"always_field\": {\"type\": \"string\"}
      },
      \"if\": {\"properties\": {\"flag\": {\"const\": true}}},
      \"then\": {
        \"properties\": {
          \"extra_field\": {\"type\": \"string\"}
        }
      }
    }"

  let assert Ok(parsed_schema) = parser.parse_schema(schema_json)

  // Build model with flag=true, fill all fields
  let values_true =
    ObjectValue([
      #("flag", BooleanValue(True)),
      #("always_field", StringValue("ok")),
      #("extra_field", StringValue("data")),
    ])

  let resolved_true =
    conditional_resolver.resolve_conditional_schema(parsed_schema, values_true)

  let form_model_true =
    model.FormModel(
      ..model.init(parsed_schema),
      values: values_true,
      resolved_schema: resolved_true,
    )

  // When flag=true, resolved values should include extra_field
  let resolved_values_true = model.get_resolved_values(form_model_true)
  has_field(resolved_values_true, "flag") |> should.be_true()
  has_field(resolved_values_true, "always_field") |> should.be_true()
  has_field(resolved_values_true, "extra_field") |> should.be_true()

  // Switch flag=false — extra_field should be filtered out
  let values_false =
    ObjectValue([
      #("flag", BooleanValue(False)),
      #("always_field", StringValue("ok")),
      #("extra_field", StringValue("data")),
    ])

  let resolved_false =
    conditional_resolver.resolve_conditional_schema(parsed_schema, values_false)

  let form_model_false =
    model.FormModel(
      ..model.init(parsed_schema),
      values: values_false,
      resolved_schema: resolved_false,
    )

  let resolved_values_false = model.get_resolved_values(form_model_false)
  has_field(resolved_values_false, "flag") |> should.be_true()
  has_field(resolved_values_false, "always_field") |> should.be_true()
  has_field(resolved_values_false, "extra_field") |> should.be_false()

  // model.values still contains extra_field (not deleted)
  has_field(form_model_false.values, "extra_field") |> should.be_true()
}

/// Test that hidden field values are preserved and reappear on toggle
pub fn resolved_values_preserved_on_toggle_test() {
  let schema_json =
    "{
      \"title\": \"Test Form\",
      \"type\": \"object\",
      \"properties\": {
        \"flag\": {\"type\": \"boolean\"}
      },
      \"if\": {\"properties\": {\"flag\": {\"const\": true}}},
      \"then\": {
        \"properties\": {
          \"extra_field\": {\"type\": \"string\"}
        }
      }
    }"

  let assert Ok(parsed_schema) = parser.parse_schema(schema_json)

  // Step 1: flag=true, fill extra_field
  let values =
    ObjectValue([
      #("flag", BooleanValue(True)),
      #("extra_field", StringValue("my data")),
    ])

  let resolved =
    conditional_resolver.resolve_conditional_schema(parsed_schema, values)

  let form_model =
    model.FormModel(
      ..model.init(parsed_schema),
      values: values,
      resolved_schema: resolved,
    )

  model.get_resolved_values(form_model)
  |> path.get_at_path(path.from_field_name("extra_field"))
  |> should.equal(Some(StringValue("my data")))

  // Step 2: flag=false — extra_field hidden but data preserved in values
  let values_off =
    path.set_at_path(values, path.from_field_name("flag"), BooleanValue(False))
  let form_model_off =
    model.FormModel(
      ..form_model,
      values: values_off,
      resolved_schema: conditional_resolver.resolve_conditional_schema(
        parsed_schema,
        values_off,
      ),
    )

  model.get_resolved_values(form_model_off)
  |> has_field("extra_field")
  |> should.be_false()

  // Step 3: flag=true again — extra_field reappears with original data
  let values_on =
    path.set_at_path(
      form_model_off.values,
      path.from_field_name("flag"),
      BooleanValue(True),
    )
  let form_model_on =
    model.FormModel(
      ..form_model_off,
      values: values_on,
      resolved_schema: conditional_resolver.resolve_conditional_schema(
        parsed_schema,
        values_on,
      ),
    )

  model.get_resolved_values(form_model_on)
  |> path.get_at_path(path.from_field_name("extra_field"))
  |> should.equal(Some(StringValue("my data")))
}

/// Test that validate_all_fields validates conditional required fields
pub fn validate_all_fields_conditional_required_test() {
  let schema_json =
    "{
      \"title\": \"Test Form\",
      \"type\": \"object\",
      \"properties\": {
        \"flag\": {\"type\": \"boolean\"}
      },
      \"if\": {\"properties\": {\"flag\": {\"const\": true}}},
      \"then\": {
        \"properties\": {
          \"extra_field\": {\"type\": \"string\"}
        },
        \"required\": [\"extra_field\"]
      }
    }"

  let assert Ok(parsed_schema) = parser.parse_schema(schema_json)

  // flag=true, extra_field not filled → should have validation error
  let values_true =
    ObjectValue([
      #("flag", BooleanValue(True)),
    ])

  let resolved_true =
    conditional_resolver.resolve_conditional_schema(parsed_schema, values_true)

  let form_model_true =
    model.FormModel(
      ..model.init(parsed_schema),
      values: values_true,
      resolved_schema: resolved_true,
    )

  let validated_true = update.validate_all_fields(form_model_true)
  // extra_field should have a required error
  model.has_errors_at_path(validated_true, path.from_field_name("extra_field"))
  |> should.be_true()

  // flag=false → no error on extra_field (field not in resolved schema)
  let values_false =
    ObjectValue([
      #("flag", BooleanValue(False)),
    ])

  let resolved_false =
    conditional_resolver.resolve_conditional_schema(parsed_schema, values_false)

  let form_model_false =
    model.FormModel(
      ..model.init(parsed_schema),
      values: values_false,
      resolved_schema: resolved_false,
    )

  let validated_false = update.validate_all_fields(form_model_false)
  model.has_errors_at_path(validated_false, path.from_field_name("extra_field"))
  |> should.be_false()
}

/// Conditional then-properties are appended after the base properties,
/// preserving the schema's declared order.
pub fn conditional_appends_after_base_properties_test() {
  let schema_json =
    "{
      \"type\": \"object\",
      \"properties\": {
        \"alpha\": {\"type\": \"string\"},
        \"beta\": {\"type\": \"string\"}
      },
      \"if\": {\"properties\": {\"alpha\": {\"const\": \"x\"}}},
      \"then\": {
        \"properties\": {
          \"zeta\": {\"type\": \"string\"},
          \"gamma\": {\"type\": \"string\"}
        }
      }
    }"

  let assert Ok(parsed_schema) = parser.parse_schema(schema_json)
  let form_values = ObjectValue([#("alpha", StringValue("x"))])
  let resolved =
    conditional_resolver.resolve_conditional_schema(parsed_schema, form_values)

  resolved.properties
  |> list.map(fn(entry) { entry.0 })
  |> should.equal(["alpha", "beta", "zeta", "gamma"])
}

/// Symmetric to `conditional_appends_after_base_properties_test` — the
/// else-branch goes through the same `merge_property_lists` path and must
/// append its properties after the base ones in declared order.
pub fn conditional_else_appends_after_base_properties_test() {
  let schema_json =
    "{
      \"type\": \"object\",
      \"properties\": {
        \"alpha\": {\"type\": \"string\"},
        \"beta\": {\"type\": \"string\"}
      },
      \"if\": {\"properties\": {\"alpha\": {\"const\": \"x\"}}},
      \"else\": {
        \"properties\": {
          \"zeta\": {\"type\": \"string\"},
          \"gamma\": {\"type\": \"string\"}
        }
      }
    }"

  let assert Ok(parsed_schema) = parser.parse_schema(schema_json)
  // alpha != "x" → condition fails → else branch activates
  let form_values = ObjectValue([#("alpha", StringValue("other"))])
  let resolved =
    conditional_resolver.resolve_conditional_schema(parsed_schema, form_values)

  resolved.properties
  |> list.map(fn(entry) { entry.0 })
  |> should.equal(["alpha", "beta", "zeta", "gamma"])
}

/// Conditional override of an existing key keeps the field at its original
/// position rather than moving it to the end of the list.
pub fn conditional_override_keeps_position_test() {
  let schema_json =
    "{
      \"type\": \"object\",
      \"properties\": {
        \"alpha\": {\"type\": \"string\"},
        \"beta\": {\"type\": \"string\"},
        \"gamma\": {\"type\": \"string\"}
      },
      \"if\": {\"properties\": {\"alpha\": {\"const\": \"x\"}}},
      \"then\": {
        \"properties\": {
          \"beta\": {\"type\": \"integer\"},
          \"delta\": {\"type\": \"string\"}
        }
      }
    }"

  let assert Ok(parsed_schema) = parser.parse_schema(schema_json)
  let form_values = ObjectValue([#("alpha", StringValue("x"))])
  let resolved =
    conditional_resolver.resolve_conditional_schema(parsed_schema, form_values)

  resolved.properties
  |> list.map(fn(entry) { entry.0 })
  |> should.equal(["alpha", "beta", "gamma", "delta"])

  // The override changed beta's type from string to integer.
  let assert Ok(beta) = list.key_find(resolved.properties, "beta")
  beta.field_type |> should.equal(Some(types.IntegerType))
}

// ----------------------------------------------------------------------------
// Item-level conditionals inside array `items` (if/then/else, allOf)
// ----------------------------------------------------------------------------

/// Minimised real-world schema from the downstream histology-simple form.
fn lesions_schema_json() -> String {
  "{
    \"type\": \"object\",
    \"properties\": {
      \"lesions\": {
        \"type\": \"array\",
        \"items\": {
          \"type\": \"object\",
          \"properties\": {
            \"lesion_num\":  {\"type\": \"integer\"},
            \"is_resected\": {\"type\": \"boolean\"}
          },
          \"required\": [\"lesion_num\", \"is_resected\"],
          \"allOf\": [
            {
              \"if\":   {\"properties\": {\"is_resected\": {\"const\": true}}},
              \"then\": {
                \"properties\": {
                  \"visible\":     {\"type\": \"string\", \"enum\": [\"yes\", \"no\", \"no_data\"]},
                  \"tumor_cells\": {\"type\": \"string\", \"enum\": [\"yes\", \"no\", \"no_data\"]}
                },
                \"required\": [\"visible\"]
              }
            },
            {
              \"if\":   {\"properties\": {\"visible\": {\"const\": \"yes\"}}},
              \"then\": {
                \"properties\": {
                  \"conclusion\": {\"type\": \"string\", \"enum\": [\"metastasis\", \"fibrosis\", \"hemangioma\", \"cyst\", \"steatosis\"]}
                },
                \"required\": [\"conclusion\"]
              }
            }
          ]
        }
      }
    }
  }"
}

/// Parse the lesions schema and pull out the `items` SchemaProperty.
fn lesions_item_schema() -> SchemaProperty {
  let assert Ok(schema) = parser.parse_schema(lesions_schema_json())
  let assert Ok(lesions) = list.key_find(schema.properties, "lesions")
  let assert Some(item_schema) = lesions.items
  item_schema
}

/// is_resected=false hides visible/tumor_cells/conclusion in the resolved row.
pub fn array_item_hides_conditional_fields_when_condition_false_test() {
  let item_schema = lesions_item_schema()

  let values =
    ObjectValue([
      #("lesion_num", IntegerValue(1)),
      #("is_resected", BooleanValue(False)),
    ])

  let resolved =
    conditional_resolver.resolve_conditional_property(item_schema, values)

  let assert Some(props) = resolved.properties
  has_property_key(props, "lesion_num") |> should.be_true()
  has_property_key(props, "is_resected") |> should.be_true()
  has_property_key(props, "visible") |> should.be_false()
  has_property_key(props, "tumor_cells") |> should.be_false()
  has_property_key(props, "conclusion") |> should.be_false()
}

/// is_resected=true reveals visible/tumor_cells and makes visible required.
pub fn array_item_shows_and_requires_visible_when_resected_test() {
  let item_schema = lesions_item_schema()

  let values =
    ObjectValue([
      #("lesion_num", IntegerValue(1)),
      #("is_resected", BooleanValue(True)),
    ])

  let resolved =
    conditional_resolver.resolve_conditional_property(item_schema, values)

  let assert Some(props) = resolved.properties
  has_property_key(props, "visible") |> should.be_true()
  has_property_key(props, "tumor_cells") |> should.be_true()
  list.contains(resolved.required, "visible") |> should.be_true()
}

/// Cascade: is_resected=true + visible="yes" adds conclusion as required.
pub fn array_item_cascade_conclusion_required_test() {
  let item_schema = lesions_item_schema()

  let values =
    ObjectValue([
      #("lesion_num", IntegerValue(1)),
      #("is_resected", BooleanValue(True)),
      #("visible", StringValue("yes")),
    ])

  let resolved =
    conditional_resolver.resolve_conditional_property(item_schema, values)

  let assert Some(props) = resolved.properties
  has_property_key(props, "conclusion") |> should.be_true()
  list.contains(resolved.required, "conclusion") |> should.be_true()
}

/// Each row resolves independently — two rows with different is_resected
/// values produce different resolved item schemas.
pub fn array_items_resolve_independently_per_row_test() {
  let item_schema = lesions_item_schema()

  let row_collapsed = ObjectValue([#("is_resected", BooleanValue(False))])
  let row_expanded = ObjectValue([#("is_resected", BooleanValue(True))])

  let resolved_collapsed =
    conditional_resolver.resolve_conditional_property(
      item_schema,
      row_collapsed,
    )
  let resolved_expanded =
    conditional_resolver.resolve_conditional_property(item_schema, row_expanded)

  let assert Some(collapsed_props) = resolved_collapsed.properties
  let assert Some(expanded_props) = resolved_expanded.properties

  has_property_key(collapsed_props, "visible") |> should.be_false()
  has_property_key(expanded_props, "visible") |> should.be_true()

  list.contains(resolved_collapsed.required, "visible") |> should.be_false()
  list.contains(resolved_expanded.required, "visible") |> should.be_true()
}

/// Parser populates `SchemaProperty.conditionals` on items with allOf.
pub fn array_item_conditionals_extracted_by_parser_test() {
  let item_schema = lesions_item_schema()
  item_schema.conditionals
  |> list.length()
  |> should.equal(2)
}

/// Full validate_all_fields flow catches item-level conditional required errors.
pub fn validate_all_fields_array_item_required_test() {
  let assert Ok(parsed_schema) = parser.parse_schema(lesions_schema_json())

  // One row with is_resected=true and missing `visible` (required by then-branch).
  let row =
    types.ObjectValue([
      #("lesion_num", IntegerValue(1)),
      #("is_resected", BooleanValue(True)),
    ])
  let values = ObjectValue([#("lesions", types.ArrayValue([row]))])

  let resolved_schema =
    conditional_resolver.resolve_conditional_schema(parsed_schema, values)

  let form_model =
    model.FormModel(
      ..model.init(parsed_schema),
      values: values,
      resolved_schema: resolved_schema,
    )

  let validated = update.validate_all_fields(form_model)

  // Path-keyed error for the missing required field appears on the model.
  // Format matches `path.to_string` — `<array>.[<index>].<field>`.
  model.has_errors_at_path(
    validated,
    path.to_array_item_field("lesions", 0, "visible"),
  )
  |> should.be_true()

  // Filling visible="yes" cascades into conclusion being required.
  let row_visible =
    types.ObjectValue([
      #("lesion_num", IntegerValue(1)),
      #("is_resected", BooleanValue(True)),
      #("visible", StringValue("yes")),
    ])
  let values2 = ObjectValue([#("lesions", types.ArrayValue([row_visible]))])

  let resolved2 =
    conditional_resolver.resolve_conditional_schema(parsed_schema, values2)

  let form_model2 =
    model.FormModel(..form_model, values: values2, resolved_schema: resolved2)

  let validated2 = update.validate_all_fields(form_model2)
  model.has_errors_at_path(
    validated2,
    path.to_array_item_field("lesions", 0, "conclusion"),
  )
  |> should.be_true()

  // Switching is_resected back to false clears all conditional errors.
  let row_collapsed =
    types.ObjectValue([
      #("lesion_num", IntegerValue(1)),
      #("is_resected", BooleanValue(False)),
    ])
  let values3 = ObjectValue([#("lesions", types.ArrayValue([row_collapsed]))])

  let resolved3 =
    conditional_resolver.resolve_conditional_schema(parsed_schema, values3)

  let form_model3 =
    model.FormModel(..form_model, values: values3, resolved_schema: resolved3)

  let validated3 = update.validate_all_fields(form_model3)
  model.has_errors_at_path(
    validated3,
    path.to_array_item_field("lesions", 0, "visible"),
  )
  |> should.be_false()
  model.has_errors_at_path(
    validated3,
    path.to_array_item_field("lesions", 0, "conclusion"),
  )
  |> should.be_false()
}

// ----------------------------------------------------------------------------
// Extra coverage: else-branch, multi-row, missing-if-field, key format,
// path-key alignment with `path.to_string`.
// ----------------------------------------------------------------------------

/// Schema where the if-branch toggles between two distinct property sets
/// (then vs else). Used to verify the `else` branch is honoured.
fn category_items_schema_json() -> String {
  "{
    \"type\": \"object\",
    \"properties\": {
      \"items\": {
        \"type\": \"array\",
        \"items\": {
          \"type\": \"object\",
          \"properties\": {
            \"kind\": {\"type\": \"string\", \"enum\": [\"book\", \"movie\"]}
          },
          \"required\": [\"kind\"],
          \"if\":   {\"properties\": {\"kind\": {\"const\": \"book\"}}},
          \"then\": {
            \"properties\": {\"pages\": {\"type\": \"integer\"}},
            \"required\": [\"pages\"]
          },
          \"else\": {
            \"properties\": {\"runtime\": {\"type\": \"integer\"}},
            \"required\": [\"runtime\"]
          }
        }
      }
    }
  }"
}

fn category_item_schema() -> SchemaProperty {
  let parse_result = parser.parse_schema(category_items_schema_json())
  parse_result |> should.be_ok()
  let assert Ok(schema) = parse_result
  let items_result = list.key_find(schema.properties, "items")
  items_result |> should.be_ok()
  let assert Ok(items) = items_result
  let assert Some(item_schema) = items.items
  item_schema
}

/// When the if-condition is False, the else-branch's properties/required
/// are merged into the resolved item.
pub fn array_item_else_branch_applies_when_condition_false_test() {
  let item_schema = category_item_schema()

  let movie_row = ObjectValue([#("kind", StringValue("movie"))])

  let resolved =
    conditional_resolver.resolve_conditional_property(item_schema, movie_row)

  let assert Some(props) = resolved.properties
  types.has_property_key(props, "runtime") |> should.be_true()
  types.has_property_key(props, "pages") |> should.be_false()
  list.contains(resolved.required, "runtime") |> should.be_true()
  list.contains(resolved.required, "pages") |> should.be_false()
}

/// When the if-condition is True, the then-branch fields show, else does not.
pub fn array_item_then_branch_applies_when_condition_true_test() {
  let item_schema = category_item_schema()

  let book_row = ObjectValue([#("kind", StringValue("book"))])

  let resolved =
    conditional_resolver.resolve_conditional_property(item_schema, book_row)

  let assert Some(props) = resolved.properties
  types.has_property_key(props, "pages") |> should.be_true()
  types.has_property_key(props, "runtime") |> should.be_false()
  list.contains(resolved.required, "pages") |> should.be_true()
}

/// Two rows in the same array — only the row missing its conditional-required
/// field produces an error; the other row stays clean.
pub fn array_items_multi_row_independent_validation_test() {
  let parse_result = parser.parse_schema(lesions_schema_json())
  parse_result |> should.be_ok()
  let assert Ok(parsed_schema) = parse_result

  // Row 0: is_resected=true, missing `visible` → should produce an error.
  // Row 1: is_resected=false → no conditional-required at all, should be clean.
  let row0 =
    types.ObjectValue([
      #("lesion_num", IntegerValue(1)),
      #("is_resected", BooleanValue(True)),
    ])
  let row1 =
    types.ObjectValue([
      #("lesion_num", IntegerValue(2)),
      #("is_resected", BooleanValue(False)),
    ])
  let values = ObjectValue([#("lesions", types.ArrayValue([row0, row1]))])

  let resolved_schema =
    conditional_resolver.resolve_conditional_schema(parsed_schema, values)

  let form_model =
    model.FormModel(
      ..model.init(parsed_schema),
      values: values,
      resolved_schema: resolved_schema,
    )

  let validated = update.validate_all_fields(form_model)

  // Row 0 has the conditional-required `visible` missing.
  model.has_errors_at_path(
    validated,
    path.to_array_item_field("lesions", 0, "visible"),
  )
  |> should.be_true()
  // Row 1 should NOT have a `visible` error — visible isn't even in its
  // resolved schema (is_resected=False).
  model.has_errors_at_path(
    validated,
    path.to_array_item_field("lesions", 1, "visible"),
  )
  |> should.be_false()
}

/// `evaluate_condition` returns False when the value referenced by `if` is
/// missing from the row, so the then-branch must not apply.
pub fn array_item_missing_if_field_falls_through_test() {
  let item_schema = lesions_item_schema()

  // Empty row — no is_resected at all.
  let empty_row = ObjectValue([])

  let resolved =
    conditional_resolver.resolve_conditional_property(item_schema, empty_row)

  let assert Some(props) = resolved.properties
  // Without is_resected, the then-branch fields stay hidden.
  types.has_property_key(props, "visible") |> should.be_false()
  types.has_property_key(props, "tumor_cells") |> should.be_false()
}

/// Error keys in the model match `path.to_string` exactly, so any UI code
/// looking up errors via `get_errors_at_path` will find them.
pub fn array_item_error_key_matches_path_to_string_test() {
  let parse_result = parser.parse_schema(lesions_schema_json())
  parse_result |> should.be_ok()
  let assert Ok(parsed_schema) = parse_result

  let row =
    types.ObjectValue([
      #("lesion_num", IntegerValue(1)),
      #("is_resected", BooleanValue(True)),
    ])
  let values = ObjectValue([#("lesions", types.ArrayValue([row]))])

  let resolved_schema =
    conditional_resolver.resolve_conditional_schema(parsed_schema, values)

  let form_model =
    model.FormModel(
      ..model.init(parsed_schema),
      values: values,
      resolved_schema: resolved_schema,
    )

  let validated = update.validate_all_fields(form_model)

  let field_path = path.to_array_item_field("lesions", 0, "visible")

  // Path-based API (used by UI) finds the error under the canonical key.
  model.has_errors_at_path(validated, field_path)
  |> should.be_true()

  // And the canonical key has the expected literal format with brackets.
  path.to_string(field_path)
  |> should.equal("lesions.[0].visible")
}

/// Top-level object with a required nested property routes through
/// `validate_nested` → `validate_object_fields` and keys the error under
/// `<parent>.<child>` (no array index involved).
pub fn validate_top_level_object_nested_required_test() {
  let json =
    "{
      \"type\": \"object\",
      \"properties\": {
        \"address\": {
          \"type\": \"object\",
          \"properties\": {
            \"street\": {\"type\": \"string\"},
            \"city\":   {\"type\": \"string\"}
          },
          \"required\": [\"street\"]
        }
      }
    }"
  let parse_result = parser.parse_schema(json)
  parse_result |> should.be_ok()
  let assert Ok(parsed_schema) = parse_result

  // `address` exists but is missing the required `street`.
  let values =
    ObjectValue([
      #("address", types.ObjectValue([#("city", StringValue("NYC"))])),
    ])
  let resolved_schema =
    conditional_resolver.resolve_conditional_schema(parsed_schema, values)

  let form_model =
    model.FormModel(
      ..model.init(parsed_schema),
      values: values,
      resolved_schema: resolved_schema,
    )

  let validated = update.validate_all_fields(form_model)

  let address_street_path = [
    path.PropertySegment("address"),
    path.PropertySegment("street"),
  ]
  let address_city_path = [
    path.PropertySegment("address"),
    path.PropertySegment("city"),
  ]
  // Error is keyed under the canonical "<parent>.<child>" format.
  model.has_errors_at_path(validated, address_street_path)
  |> should.be_true()
  // Sibling that was provided has no errors.
  model.has_errors_at_path(validated, address_city_path)
  |> should.be_false()
}

// ----------------------------------------------------------------------------
// is_required_at_path tests
// ----------------------------------------------------------------------------

fn simple_required_schema_json() -> String {
  "{
    \"type\": \"object\",
    \"properties\": {
      \"name\":     {\"type\": \"string\"},
      \"optional\": {\"type\": \"string\"}
    },
    \"required\": [\"name\"]
  }"
}

fn parse_form_model(json: String) -> model.FormModel {
  let assert Ok(parsed) = parser.parse_schema(json)
  model.init(parsed)
}

pub fn is_required_at_path_root_required_test() {
  let form_model = parse_form_model(simple_required_schema_json())
  model.is_required_at_path(form_model, path.from_field_name("name"))
  |> should.be_true()
}

pub fn is_required_at_path_root_not_required_test() {
  let form_model = parse_form_model(simple_required_schema_json())
  model.is_required_at_path(form_model, path.from_field_name("optional"))
  |> should.be_false()
}

pub fn is_required_at_path_root_missing_test() {
  let form_model = parse_form_model(simple_required_schema_json())
  model.is_required_at_path(form_model, path.from_field_name("ghost"))
  |> should.be_false()
}

fn nested_object_schema_json() -> String {
  "{
    \"type\": \"object\",
    \"properties\": {
      \"address\": {
        \"type\": \"object\",
        \"properties\": {
          \"street\": {\"type\": \"string\"},
          \"city\":   {\"type\": \"string\"}
        },
        \"required\": [\"street\"]
      }
    }
  }"
}

pub fn is_required_at_path_nested_object_required_test() {
  let form_model = parse_form_model(nested_object_schema_json())
  let street_path = [
    path.PropertySegment("address"),
    path.PropertySegment("street"),
  ]
  model.is_required_at_path(form_model, street_path)
  |> should.be_true()
}

pub fn is_required_at_path_nested_object_not_required_test() {
  let form_model = parse_form_model(nested_object_schema_json())
  let city_path = [
    path.PropertySegment("address"),
    path.PropertySegment("city"),
  ]
  model.is_required_at_path(form_model, city_path)
  |> should.be_false()
}

pub fn is_required_at_path_array_item_required_test() {
  let form_model = parse_form_model(lesions_schema_json())
  let p = path.to_array_item_field("lesions", 0, "lesion_num")
  model.is_required_at_path(form_model, p)
  |> should.be_true()
}

pub fn is_required_at_path_array_item_not_required_test() {
  // `visible` becomes required only via `allOf` (item-level conditional),
  // which is not resolved by the static walk in PR 2. Expect False.
  let form_model = parse_form_model(lesions_schema_json())
  let p = path.to_array_item_field("lesions", 0, "visible")
  model.is_required_at_path(form_model, p)
  |> should.be_false()
}

fn deep_object_in_array_schema_json() -> String {
  "{
    \"type\": \"object\",
    \"properties\": {
      \"outer\": {
        \"type\": \"array\",
        \"items\": {
          \"type\": \"object\",
          \"properties\": {
            \"inner\": {
              \"type\": \"object\",
              \"properties\": {
                \"leaf\": {\"type\": \"string\"}
              },
              \"required\": [\"leaf\"]
            }
          }
        }
      }
    }
  }"
}

pub fn is_required_at_path_deep_object_in_array_test() {
  let form_model = parse_form_model(deep_object_in_array_schema_json())
  let p = [
    path.PropertySegment("outer"),
    path.ArraySegment(0),
    path.PropertySegment("inner"),
    path.PropertySegment("leaf"),
  ]
  model.is_required_at_path(form_model, p)
  |> should.be_true()
}

pub fn is_required_at_path_empty_test() {
  let form_model = parse_form_model(simple_required_schema_json())
  model.is_required_at_path(form_model, [])
  |> should.be_false()
}

pub fn is_required_at_path_leading_array_segment_test() {
  let form_model = parse_form_model(simple_required_schema_json())
  model.is_required_at_path(form_model, [
    path.ArraySegment(0),
    path.PropertySegment("name"),
  ])
  |> should.be_false()
}

pub fn is_required_at_path_intermediate_scalar_test() {
  // `name` is a string scalar — path tries to descend further, must fall through.
  let form_model = parse_form_model(simple_required_schema_json())
  let p = [path.PropertySegment("name"), path.PropertySegment("subfield")]
  model.is_required_at_path(form_model, p)
  |> should.be_false()
}

/// view.gleam now uses `is_required_at_path` over `resolved_schema`, so root
/// fields surfaced by a conditional then-branch appear as required only
/// after the condition is satisfied.
pub fn is_required_at_path_root_required_in_then_branch_test() {
  let schema_json =
    "{
      \"type\": \"object\",
      \"properties\": {
        \"flag\": {\"type\": \"boolean\"}
      },
      \"if\":   {\"properties\": {\"flag\": {\"const\": true}}},
      \"then\": {
        \"properties\": {\"extra\": {\"type\": \"string\"}},
        \"required\": [\"extra\"]
      }
    }"
  let assert Ok(parsed) = parser.parse_schema(schema_json)

  // Base `schema.required` never contains "extra" — only the resolved
  // version sees it after the condition fires. This guards against
  // regressions where `view.render_field` consulted `model.schema`.
  list.contains(parsed.required, "extra") |> should.be_false()

  // flag=false → `extra` not required (it's not even in resolved properties)
  let values_off = ObjectValue([#("flag", BooleanValue(False))])
  let resolved_off =
    conditional_resolver.resolve_conditional_schema(parsed, values_off)
  let model_off =
    model.FormModel(
      ..model.init(parsed),
      values: values_off,
      resolved_schema: resolved_off,
    )
  model.is_required_at_path(model_off, path.from_field_name("extra"))
  |> should.be_false()

  // flag=true → `extra` required, surfaced only via resolved_schema
  let values_on = ObjectValue([#("flag", BooleanValue(True))])
  let resolved_on =
    conditional_resolver.resolve_conditional_schema(parsed, values_on)
  let model_on =
    model.FormModel(
      ..model.init(parsed),
      values: values_on,
      resolved_schema: resolved_on,
    )
  model.is_required_at_path(model_on, path.from_field_name("extra"))
  |> should.be_true()
}
