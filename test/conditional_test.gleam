/// Tests for JSON Schema conditional logic (if/then/else)
import gleam/dict
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import schema/conditional_resolver
import schema/types.{
  BooleanValue, ConditionalRule, JsonSchema, JsonString, SchemaProperty,
  StringValue, empty_property,
}

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
              enum_values: Some([JsonString("Общий вопрос")]),
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
      title: "Test Form",
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
              enum_values: Some([types.JsonBool(True)]),
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
      title: "Test Form",
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
              enum_values: Some([JsonString("Special")]),
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
      title: "Test Form",
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
