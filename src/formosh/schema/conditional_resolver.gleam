/// Conditional schema resolution for dynamic form behavior.
///
/// This module implements the logic for resolving JSON Schema conditional
/// rules (if/then/else) based on runtime form values, enabling dynamic
/// field visibility and validation.
import formosh/schema/types.{
  type ConditionalRule, type JsonSchema, type SchemaProperty, type Value,
  BooleanValue, IntegerValue, JsonSchema, NullValue, NumberValue, SchemaProperty,
  StringValue,
}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{None, Some}

/// Resolve a schema with conditional rules applied based on current form values.
///
/// This function evaluates all conditional rules in the schema and merges
/// the appropriate then/else branches into the schema properties based on
/// whether the conditions are met.
///
/// ## Parameters
/// - `base_schema`: The original schema with conditional rules
/// - `form_values`: Current form field values to evaluate conditions against
///
/// ## Returns
/// A new JsonSchema with conditional properties merged based on evaluation
pub fn resolve_conditional_schema(
  base_schema: JsonSchema,
  form_values: Dict(String, Value),
) -> JsonSchema {
  list.fold(base_schema.conditionals, base_schema, fn(schema, rule) {
    case evaluate_condition(rule.if_schema, form_values) {
      True -> apply_then_branch(schema, rule)
      False -> apply_else_branch(schema, rule)
    }
  })
}

/// Resolve an item-level schema property with its own conditional rules.
///
/// Mirrors `resolve_conditional_schema` but operates on a `SchemaProperty`
/// (used for array `items`). Conditions evaluate against the item-local
/// values dict, so each array row resolves independently.
///
/// ## Parameters
/// - `base`: The property carrying its own `conditionals` (typically an
///   array's `items` schema)
/// - `item_values`: Values belonging to a single array row
///
/// ## Returns
/// A SchemaProperty with then/else branches merged into `properties` and
/// `required` based on rule evaluation.
pub fn resolve_conditional_property(
  base: SchemaProperty,
  item_values: Dict(String, Value),
) -> SchemaProperty {
  list.fold(base.conditionals, base, fn(prop, rule) {
    case evaluate_condition(rule.if_schema, item_values) {
      True -> apply_then_branch_property(prop, rule)
      False -> apply_else_branch_property(prop, rule)
    }
  })
}

/// Evaluate if a condition schema matches the current form values.
///
/// Checks if the form values satisfy the constraints defined in the
/// condition schema (typically checking for specific property values).
fn evaluate_condition(
  condition: SchemaProperty,
  form_values: Dict(String, Value),
) -> Bool {
  // For object conditions, check if all properties match
  case condition.properties {
    Some(props) -> {
      dict.to_list(props)
      |> list.all(fn(prop_pair) {
        let #(field_name, prop_schema) = prop_pair
        case dict.get(form_values, field_name) {
          Ok(field_value) -> check_property_match(prop_schema, field_value)
          Error(_) -> False
        }
      })
    }
    None -> {
      // For non-object conditions, check enum or const values
      case condition.enum_values {
        Some(_expected_values) -> {
          // This would typically check a specific field
          // For now, returning false as we need field context
          False
        }
        None -> False
      }
    }
  }
}

/// Check if a field value matches a property schema constraint.
///
/// This is used to evaluate if conditions, checking if the actual
/// field value satisfies the constraints in the condition schema.
fn check_property_match(prop_schema: SchemaProperty, field_value: Value) -> Bool {
  // Check for const constraint (exact value match)
  case prop_schema.enum_values {
    Some([expected_value]) -> {
      // Single enum value acts as a const constraint
      compare_values(expected_value, field_value)
    }
    Some(expected_values) -> {
      // Multiple enum values - check if field value matches any
      list.any(expected_values, fn(expected) {
        compare_values(expected, field_value)
      })
    }
    None -> {
      // No specific value constraint, just type checking
      // For now, return true if types match
      True
    }
  }
}

/// Compare two values for equality.
fn compare_values(val1: Value, val2: Value) -> Bool {
  case val1, val2 {
    StringValue(s1), StringValue(s2) -> s1 == s2
    NumberValue(n1), NumberValue(n2) -> n1 == n2
    IntegerValue(i1), IntegerValue(i2) -> i1 == i2
    BooleanValue(b1), BooleanValue(b2) -> b1 == b2
    NullValue, NullValue -> True
    _, _ -> False
  }
}

/// Apply the then branch of a conditional rule to a schema.
///
/// Merges the then_schema properties into the base schema when
/// the condition is true.
fn apply_then_branch(schema: JsonSchema, rule: ConditionalRule) -> JsonSchema {
  case rule.then_schema {
    Some(then_props) -> merge_schema_properties(schema, then_props)
    None -> schema
  }
}

/// Apply the else branch of a conditional rule to a schema.
///
/// Merges the else_schema properties into the base schema when
/// the condition is false.
fn apply_else_branch(schema: JsonSchema, rule: ConditionalRule) -> JsonSchema {
  case rule.else_schema {
    Some(else_props) -> merge_schema_properties(schema, else_props)
    None -> schema
  }
}

/// Merge properties from a conditional schema into the base schema.
///
/// This adds or overrides properties from the conditional branch
/// into the main schema properties.
fn merge_schema_properties(
  base_schema: JsonSchema,
  conditional_props: SchemaProperty,
) -> JsonSchema {
  case conditional_props.properties {
    Some(new_props) -> {
      let merged_properties = dict.merge(base_schema.properties, new_props)
      let merged_required =
        list.append(base_schema.required, conditional_props.required)
        |> list.unique()
      JsonSchema(
        ..base_schema,
        properties: merged_properties,
        required: merged_required,
      )
    }
    None -> base_schema
  }
}

/// Property-level analogue of `apply_then_branch`.
fn apply_then_branch_property(
  base: SchemaProperty,
  rule: ConditionalRule,
) -> SchemaProperty {
  case rule.then_schema {
    Some(then_props) -> merge_into_property(base, then_props)
    None -> base
  }
}

/// Property-level analogue of `apply_else_branch`.
fn apply_else_branch_property(
  base: SchemaProperty,
  rule: ConditionalRule,
) -> SchemaProperty {
  case rule.else_schema {
    Some(else_props) -> merge_into_property(base, else_props)
    None -> base
  }
}

/// Merge a conditional branch's `properties`/`required` into a base property.
///
/// Mirrors `merge_schema_properties` but on `SchemaProperty`.
fn merge_into_property(
  base: SchemaProperty,
  conditional: SchemaProperty,
) -> SchemaProperty {
  case conditional.properties {
    Some(new_props) -> {
      let merged_props = case base.properties {
        Some(existing) -> dict.merge(existing, new_props)
        None -> new_props
      }
      let merged_required =
        list.append(base.required, conditional.required)
        |> list.unique()
      SchemaProperty(
        ..base,
        properties: Some(merged_props),
        required: merged_required,
      )
    }
    None -> base
  }
}

/// Check if a field should be visible based on conditional rules.
///
/// This is a helper function to determine field visibility without
/// fully resolving the schema.
pub fn is_field_visible(
  field_name: String,
  base_schema: JsonSchema,
  form_values: Dict(String, Value),
) -> Bool {
  // First check if field is in base properties
  let in_base = dict.has_key(base_schema.properties, field_name)

  // Then check if any conditional rule adds this field
  let added_by_conditional =
    list.any(base_schema.conditionals, fn(rule) {
      let condition_met = evaluate_condition(rule.if_schema, form_values)

      case condition_met {
        True -> {
          case rule.then_schema {
            Some(then_props) -> {
              case then_props.properties {
                Some(props) -> dict.has_key(props, field_name)
                None -> False
              }
            }
            None -> False
          }
        }
        False -> {
          case rule.else_schema {
            Some(else_props) -> {
              case else_props.properties {
                Some(props) -> dict.has_key(props, field_name)
                None -> False
              }
            }
            None -> False
          }
        }
      }
    })

  in_base || added_by_conditional
}
