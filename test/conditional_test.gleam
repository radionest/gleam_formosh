/// Tests for JSON Schema conditional logic (if/then/else)
import formosh/form/model
import formosh/form/update
import formosh/schema/conditional_resolver
import formosh/schema/parser
import formosh/schema/types.{
  BooleanValue, ConditionalRule, JsonSchema, SchemaProperty, StringValue,
  empty_property,
}
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

/// Test that conditional fields are added when condition is met
pub fn conditional_field_appears_when_condition_met_test() {
  // Create a schema with conditional logic similar to contact form
  let base_properties =
    dict.from_list([
      #("subject", empty_property()),
    ])

  // Create conditional rule: if subject == "Общий вопрос", then add is_confidential field
  let if_condition =
    SchemaProperty(
      ..empty_property(),
      properties: Some(
        dict.from_list([
          #(
            "subject",
            SchemaProperty(
              ..empty_property(),
              enum_values: Some([StringValue("Общий вопрос")]),
            ),
          ),
        ]),
      ),
    )

  let then_schema =
    SchemaProperty(
      ..empty_property(),
      properties: Some(
        dict.from_list([
          #(
            "is_confidential",
            SchemaProperty(
              ..empty_property(),
              field_type: Some(types.BooleanType),
              title: Some("Конфиденциально"),
            ),
          ),
        ]),
      ),
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
    dict.from_list([
      #("subject", StringValue("Общий вопрос")),
    ])

  let resolved_schema =
    conditional_resolver.resolve_conditional_schema(schema, form_values_met)

  // Check that is_confidential field was added
  resolved_schema.properties
  |> dict.has_key("is_confidential")
  |> should.be_true()

  // Test when condition is not met
  let form_values_not_met =
    dict.from_list([
      #("subject", StringValue("Техническая поддержка")),
    ])

  let resolved_schema_no_match =
    conditional_resolver.resolve_conditional_schema(schema, form_values_not_met)

  // Check that is_confidential field was NOT added
  resolved_schema_no_match.properties
  |> dict.has_key("is_confidential")
  |> should.be_false()
}

/// Test that else branch is applied when condition is not met
pub fn conditional_else_branch_test() {
  let base_properties =
    dict.from_list([
      #("hasAccount", empty_property()),
    ])

  // If hasAccount == true, show login field, else show registration fields
  let if_condition =
    SchemaProperty(
      ..empty_property(),
      properties: Some(
        dict.from_list([
          #(
            "hasAccount",
            SchemaProperty(
              ..empty_property(),
              enum_values: Some([types.BooleanValue(True)]),
            ),
          ),
        ]),
      ),
    )

  let then_schema =
    SchemaProperty(
      ..empty_property(),
      properties: Some(
        dict.from_list([
          #(
            "username",
            SchemaProperty(
              ..empty_property(),
              field_type: Some(types.StringType),
              title: Some("Username"),
            ),
          ),
        ]),
      ),
    )

  let else_schema =
    SchemaProperty(
      ..empty_property(),
      properties: Some(
        dict.from_list([
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
      ),
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
    dict.from_list([
      #("hasAccount", BooleanValue(True)),
    ])

  let resolved_then =
    conditional_resolver.resolve_conditional_schema(schema, form_values_true)

  // Should have username field
  resolved_then.properties
  |> dict.has_key("username")
  |> should.be_true()

  // Should NOT have email/password fields
  resolved_then.properties
  |> dict.has_key("email")
  |> should.be_false()

  // Test when hasAccount is false (else branch)
  let form_values_false =
    dict.from_list([
      #("hasAccount", BooleanValue(False)),
    ])

  let resolved_else =
    conditional_resolver.resolve_conditional_schema(schema, form_values_false)

  // Should NOT have username field
  resolved_else.properties
  |> dict.has_key("username")
  |> should.be_false()

  // Should have email/password fields
  resolved_else.properties
  |> dict.has_key("email")
  |> should.be_true()

  resolved_else.properties
  |> dict.has_key("password")
  |> should.be_true()
}

/// Test field visibility helper function
pub fn is_field_visible_test() {
  // Set up schema with conditional field
  let base_properties =
    dict.from_list([
      #("subject", empty_property()),
      #("message", empty_property()),
      // This field is always visible
    ])

  let if_condition =
    SchemaProperty(
      ..empty_property(),
      properties: Some(
        dict.from_list([
          #(
            "subject",
            SchemaProperty(
              ..empty_property(),
              enum_values: Some([StringValue("Special")]),
            ),
          ),
        ]),
      ),
    )

  let then_schema =
    SchemaProperty(
      ..empty_property(),
      properties: Some(
        dict.from_list([
          #("special_field", empty_property()),
        ]),
      ),
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
    dict.from_list([
      #("subject", StringValue("Special")),
    ])

  let form_values_not_met =
    dict.from_list([
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
  let form_values_air = dict.from_list([#("air_bubble", BooleanValue(True))])

  let resolved_air =
    conditional_resolver.resolve_conditional_schema(
      parsed_schema,
      form_values_air,
    )

  // Should have air_bubble_size field
  resolved_air.properties
  |> dict.has_key("air_bubble_size")
  |> should.be_true()

  // Should NOT have pneumo_thickness field
  resolved_air.properties
  |> dict.has_key("pneumo_thickness")
  |> should.be_false()

  // Test when pneumoperitoneum is true
  let form_values_pneumo =
    dict.from_list([#("pneumoperitoneum", BooleanValue(True))])

  let resolved_pneumo =
    conditional_resolver.resolve_conditional_schema(
      parsed_schema,
      form_values_pneumo,
    )

  // Should have pneumo_thickness field
  resolved_pneumo.properties
  |> dict.has_key("pneumo_thickness")
  |> should.be_true()

  // Should NOT have air_bubble_size field
  resolved_pneumo.properties
  |> dict.has_key("air_bubble_size")
  |> should.be_false()

  // Test when both are true
  let form_values_both =
    dict.from_list([
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
  |> dict.has_key("air_bubble_size")
  |> should.be_true()

  resolved_both.properties
  |> dict.has_key("pneumo_thickness")
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
  let form_values_true = dict.from_list([#("flag", BooleanValue(True))])

  let resolved_true =
    conditional_resolver.resolve_conditional_schema(
      parsed_schema,
      form_values_true,
    )

  resolved_true.properties
  |> dict.has_key("extra_field")
  |> should.be_true()

  // Test that const: false doesn't match true
  let form_values_false = dict.from_list([#("flag", BooleanValue(False))])

  let resolved_false =
    conditional_resolver.resolve_conditional_schema(
      parsed_schema,
      form_values_false,
    )

  resolved_false.properties
  |> dict.has_key("extra_field")
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
    dict.from_list([
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
  dict.has_key(resolved_values_true, "flag") |> should.be_true()
  dict.has_key(resolved_values_true, "always_field") |> should.be_true()
  dict.has_key(resolved_values_true, "extra_field") |> should.be_true()

  // Switch flag=false — extra_field should be filtered out
  let values_false =
    dict.from_list([
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
  dict.has_key(resolved_values_false, "flag") |> should.be_true()
  dict.has_key(resolved_values_false, "always_field") |> should.be_true()
  dict.has_key(resolved_values_false, "extra_field") |> should.be_false()

  // model.values still contains extra_field (not deleted)
  dict.has_key(form_model_false.values, "extra_field") |> should.be_true()
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
    dict.from_list([
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
  |> dict.get("extra_field")
  |> should.equal(Ok(StringValue("my data")))

  // Step 2: flag=false — extra_field hidden but data preserved in values
  let form_model_off =
    model.FormModel(
      ..form_model,
      values: dict.insert(values, "flag", BooleanValue(False)),
      resolved_schema: conditional_resolver.resolve_conditional_schema(
        parsed_schema,
        dict.insert(values, "flag", BooleanValue(False)),
      ),
    )

  model.get_resolved_values(form_model_off)
  |> dict.has_key("extra_field")
  |> should.be_false()

  // Step 3: flag=true again — extra_field reappears with original data
  let form_model_on =
    model.FormModel(
      ..form_model_off,
      values: dict.insert(form_model_off.values, "flag", BooleanValue(True)),
      resolved_schema: conditional_resolver.resolve_conditional_schema(
        parsed_schema,
        dict.insert(form_model_off.values, "flag", BooleanValue(True)),
      ),
    )

  model.get_resolved_values(form_model_on)
  |> dict.get("extra_field")
  |> should.equal(Ok(StringValue("my data")))
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
    dict.from_list([
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
  model.field_has_errors(validated_true, "extra_field")
  |> should.be_true()

  // flag=false → no error on extra_field (field not in resolved schema)
  let values_false =
    dict.from_list([
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
  model.field_has_errors(validated_false, "extra_field")
  |> should.be_false()
}
