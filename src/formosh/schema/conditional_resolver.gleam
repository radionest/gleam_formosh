/// Conditional schema resolution for dynamic form behavior.
///
/// This module implements the logic for resolving JSON Schema conditional
/// rules (if/then/else) based on runtime form values, enabling dynamic
/// field visibility and validation.
import formosh/schema/properties
import formosh/schema/types.{
  type ConditionalRule, type JsonSchema, type SchemaProperty, type Value,
  ArrayType, BooleanValue, IntegerValue, JsonSchema, NullValue, NumberValue,
  ObjectType, ObjectValue, SchemaProperty, StringValue,
}
import gleam/list
import gleam/option.{type Option, None, Some}

/// Resolve a schema with conditional rules applied based on current form values.
///
/// This function evaluates all conditional rules in the schema and merges
/// the appropriate then/else branches into the schema properties based on
/// whether the conditions are met.
///
/// ## Parameters
/// - `base_schema`: The original schema with conditional rules
/// - `form_values`: Current form values as a single hierarchical Value
///   (always `ObjectValue` at the root)
///
/// ## Returns
/// A new JsonSchema with conditional properties merged based on evaluation
pub fn resolve_conditional_schema(
  base_schema: JsonSchema,
  form_values: Value,
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
/// values, so each array row resolves independently.
///
/// ## Parameters
/// - `base`: The property carrying its own `conditionals` (typically an
///   array's `items` schema)
/// - `item_values`: Values belonging to a single array row, as a single
///   `Value` (typically `ObjectValue` of the row's fields)
///
/// ## Returns
/// A SchemaProperty with then/else branches merged into `properties` and
/// `required` based on rule evaluation.
pub fn resolve_conditional_property(
  base: SchemaProperty,
  item_values: Value,
) -> SchemaProperty {
  list.fold(base.conditionals, base, fn(prop, rule) {
    case evaluate_condition(rule.if_schema, item_values) {
      True -> apply_then_branch_property(prop, rule)
      False -> apply_else_branch_property(prop, rule)
    }
  })
}

/// Recursively resolve conditionals at every depth of a SchemaProperty subtree.
///
/// Apply-then-descend: conditionals on the current node fire first against the
/// supplied `value` (typically the subtree's slice of form values), then the
/// merged children are walked with their corresponding sub-values from the
/// form tree.
///
/// Array items are recursed with `None` so per-row dynamic resolve stays in
/// render-time (`array_field.render_item_fields`); only static conditionals
/// inside the `items` sub-schema are pre-applied.
///
/// Implementation detail of `resolve_recursive` — kept private; the contract
/// may shift without deprecation.
///
/// Known limitations:
/// - Defaults of fields newly revealed by a conditional are not back-filled
///   into `model.values` — defaults apply at init only.
/// - Cross-level conditions (root rule inspecting a nested field) are not
///   supported by the matcher; declare conditions alongside the fields they
///   inspect.
/// - Conditionals on objects nested **inside array items** do not fire
///   recursively. `array_field.render_item_fields` calls
///   `resolve_conditional_property` once per row (shallow), so item-level
///   rules work but rules on objects/arrays inside an item do not.
fn resolve_nested_conditionals(
  property: SchemaProperty,
  value: Option(Value),
) -> SchemaProperty {
  let resolved_self = case property.conditionals, value {
    [], _ -> property
    _, Some(ObjectValue(_) as v) -> resolve_conditional_property(property, v)
    _, _ -> property
  }

  case resolved_self.field_type {
    Some(ObjectType) ->
      case resolved_self.properties {
        Some(props) -> {
          let fields_opt = case value {
            Some(ObjectValue(fs)) -> Some(fs)
            _ -> None
          }
          let new_props =
            list.map(props, fn(entry) {
              let #(name, child) = entry
              let child_value = case fields_opt {
                Some(fs) -> option.from_result(list.key_find(fs, name))
                None -> None
              }
              #(name, resolve_nested_conditionals(child, child_value))
            })
          SchemaProperty(..resolved_self, properties: Some(new_props))
        }
        None -> resolved_self
      }

    Some(ArrayType) ->
      case resolved_self.items {
        Some(items_schema) ->
          SchemaProperty(
            ..resolved_self,
            items: Some(resolve_nested_conditionals(items_schema, None)),
          )
        None -> resolved_self
      }

    _ -> resolved_self
  }
}

/// Root-level entry point: runs `resolve_conditional_schema` for root rules,
/// then descends into every top-level property with its slice of values.
///
/// The result is cached in `FormModel.resolved_schema` and used by the
/// renderer — called from `update.update` and component init.
///
/// Note on argument shape: root takes a bare `Value` (always `ObjectValue`
/// for a form), recursion uses `Option(Value)` because children may be
/// absent. Do not collapse them by calling `resolve_recursive` recursively —
/// the root-resolve step is for top-level `JsonSchema.conditionals` only and
/// must not run per subtree.
pub fn resolve_recursive(schema: JsonSchema, values: Value) -> JsonSchema {
  let root_resolved = resolve_conditional_schema(schema, values)
  let fields_opt = case values {
    ObjectValue(fs) -> Some(fs)
    _ -> None
  }
  let new_props =
    list.map(root_resolved.properties, fn(entry) {
      let #(name, prop) = entry
      let child_value = case fields_opt {
        Some(fs) -> option.from_result(list.key_find(fs, name))
        None -> None
      }
      #(name, resolve_nested_conditionals(prop, child_value))
    })
  JsonSchema(..root_resolved, properties: new_props)
}

/// Look up a top-level field in a Value.
///
/// Returns `Some(value)` for an existing key inside an `ObjectValue`,
/// `None` for a missing key, and — by design — `None` for any
/// non-`ObjectValue` input. The latter case is reachable from item-level
/// resolution: `resolve_conditional_property` may receive a scalar row
/// (e.g. a `string[]` array's element). Treating it as "no fields" makes
/// `evaluate_condition` return False and the row keeps its base schema
/// unchanged — conditionals on a scalar row are meaningless.
///
/// Lives here as a local helper instead of pulling in `formosh/form/path`
/// to avoid making the schema layer depend on the form layer.
fn lookup_field(form_values: Value, field_name: String) -> option.Option(Value) {
  case form_values {
    ObjectValue(fields) ->
      case list.key_find(fields, field_name) {
        Ok(value) -> Some(value)
        Error(_) -> None
      }
    _ -> None
  }
}

/// Evaluate if a condition schema matches the current form values.
///
/// Object conditions require every declared property to match the
/// corresponding value via `check_property_match`. Non-`ObjectValue`
/// `form_values` (see `lookup_field`) makes every lookup return `None`,
/// so the predicate is False and only the else-branch is applied.
fn evaluate_condition(condition: SchemaProperty, form_values: Value) -> Bool {
  // For object conditions, check if all properties match
  case condition.properties {
    Some(props) -> {
      list.all(props, fn(prop_pair) {
        let #(field_name, prop_schema) = prop_pair
        case lookup_field(form_values, field_name) {
          Some(field_value) -> check_property_match(prop_schema, field_value)
          None -> False
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
pub fn compare_values(val1: Value, val2: Value) -> Bool {
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
      let merged_properties =
        properties.merge(base_schema.properties, new_props)
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
        Some(existing) -> properties.merge(existing, new_props)
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
/// Delegates to `resolve_conditional_schema` and checks whether the field
/// ends up in the merged property list. This is equivalent to (and replaces)
/// the previous hand-rolled walk over each conditional's then/else branches,
/// which duplicated the merge logic and re-evaluated every rule per call.
pub fn is_field_visible(
  field_name: String,
  base_schema: JsonSchema,
  form_values: Value,
) -> Bool {
  let resolved = resolve_conditional_schema(base_schema, form_values)
  properties.has_key(resolved.properties, field_name)
}
