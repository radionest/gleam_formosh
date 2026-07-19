// Validation functions for form fields

import formosh/form/path.{type FieldPath, ArraySegment, PropertySegment}
import formosh/schema/conditional_resolver
import formosh/schema/types.{
  type SchemaProperty, type Value, type Widget, ArrayValue, BooleanValue,
  IntegerValue, NullValue, NumberValue, ObjectValue, StringValue,
}
import formosh/validation/error.{type ValidationError}
import formosh/validation/field_requirements
import formosh/validation/messages
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/regexp
import gleam/string

/// Validate a field value against its schema property definition.
///
/// `field_path` is the canonical path used by every form layer; errors
/// built here are keyed by this path without any intermediate string
/// round-trip. `effective_widget` is the merged widget choice (UiSchema +
/// x-widget fallback) supplied by the caller — `validator` itself doesn't
/// know about `UiSchema`.
pub fn validate_field(
  field_path: FieldPath,
  value: Option(Value),
  property: SchemaProperty,
  is_required: Bool,
  effective_widget: Option(Widget),
) -> List(ValidationError) {
  case effective_widget {
    Some(types.ImageUploadWidget) ->
      validate_image_upload(field_path, value, is_required)
    _ -> validate_standard_field(field_path, value, property, is_required)
  }
}

/// Validate an image-upload field.
fn validate_image_upload(
  field_path: FieldPath,
  value: Option(Value),
  is_required: Bool,
) -> List(ValidationError) {
  case value {
    None | Some(NullValue) | Some(ArrayValue([])) ->
      case is_required {
        True -> [
          error.from_failure(field_path, messages.ImageRequired),
        ]
        False -> []
      }
    Some(ArrayValue(items)) -> {
      let invalid =
        list.any(items, fn(item) {
          case item {
            StringValue(_) -> False
            _ -> True
          }
        })
      case invalid {
        True -> [
          error.from_failure(field_path, messages.InvalidImageUpload),
        ]
        False -> []
      }
    }
    _ -> []
  }
}

/// Standard field validation (non-widget fields).
fn validate_standard_field(
  field_path: FieldPath,
  value: Option(Value),
  property: SchemaProperty,
  is_required: Bool,
) -> List(ValidationError) {
  let required_errors = case
    field_requirements.check_required_value(field_path, value, is_required)
  {
    Ok(_) -> []
    Error(validation_error) -> [validation_error]
  }

  case value {
    None | Some(NullValue) -> required_errors
    Some(val) -> {
      let type_errors = case property.field_type {
        Some(types.StringType) ->
          validate_string(
            field_path,
            val,
            property.string_constraints,
            is_required,
          )
        Some(types.NumberType) | Some(types.IntegerType) ->
          validate_number(field_path, val, property.number_constraints)
        Some(types.BooleanType) -> validate_boolean(field_path, val)
        _ -> []
      }

      let enum_errors = case property.enum_values {
        Some(allowed_values) -> validate_enum(field_path, val, allowed_values)
        None -> []
      }

      list.flatten([required_errors, type_errors, enum_errors])
    }
  }
}

fn validate_string(
  field_path: FieldPath,
  value: Value,
  constraints: Option(types.StringConstraints),
  is_required: Bool,
) -> List(ValidationError) {
  case value {
    // An empty value on an optional field is the user clearing the input —
    // not "the value is too short" or "doesn't match a format". Skip every
    // string-constraint check so min_length, format, and pattern behave
    // consistently when the field is cleared. Required fields still report
    // the missing value via the required-rule (set in validate_standard_field).
    StringValue("") if !is_required -> []
    StringValue(str) -> {
      case constraints {
        None -> []
        Some(c) -> {
          let errors = []

          let errors = case c.min_length {
            Some(min) -> {
              case string.length(str) < min {
                True ->
                  list.append(errors, [
                    error.from_failure(field_path, messages.MinLength(min)),
                  ])
                False -> errors
              }
            }
            None -> errors
          }

          let errors = case c.max_length {
            Some(max) -> {
              case string.length(str) > max {
                True ->
                  list.append(errors, [
                    error.from_failure(field_path, messages.MaxLength(max)),
                  ])
                False -> errors
              }
            }
            None -> errors
          }

          let errors = case c.format {
            Some(types.EmailFormat) ->
              case validate_email(str) {
                False ->
                  list.append(errors, [
                    error.from_failure(field_path, messages.InvalidEmail),
                  ])
                True -> errors
              }
            Some(types.UrlFormat) | Some(types.UriFormat) ->
              case validate_url(str) {
                False ->
                  list.append(errors, [
                    error.from_failure(field_path, messages.InvalidUrl),
                  ])
                True -> errors
              }
            _ -> errors
          }

          // JSON Schema `pattern` is a partial-match check (draft 2020-12
          // §6.3.3). `regexp.check` matches the spec semantics. A syntactically
          // invalid pattern is a schema-author bug — log it once and skip the
          // check so the form keeps working for the end user.
          let errors = case c.pattern {
            Some(pat) ->
              case regexp.from_string(pat) {
                Ok(re) ->
                  case regexp.check(re, str) {
                    True -> errors
                    False ->
                      list.append(errors, [
                        error.from_failure(field_path, messages.PatternMismatch),
                      ])
                  }
                Error(_) -> {
                  io.println_error(
                    "formosh: invalid regex pattern in JSON Schema: " <> pat,
                  )
                  errors
                }
              }
            None -> errors
          }

          errors
        }
      }
    }
    _ -> [
      error.from_failure(field_path, messages.InvalidType("string")),
    ]
  }
}

fn validate_number(
  field_path: FieldPath,
  value: Value,
  constraints: Option(types.NumberConstraints),
) -> List(ValidationError) {
  case value {
    NumberValue(num) ->
      validate_number_constraints(field_path, num, constraints)
    IntegerValue(num) ->
      validate_number_constraints(field_path, int.to_float(num), constraints)
    _ -> [
      error.from_failure(field_path, messages.InvalidType("number")),
    ]
  }
}

fn validate_number_constraints(
  field_path: FieldPath,
  value: Float,
  constraints: Option(types.NumberConstraints),
) -> List(ValidationError) {
  case constraints {
    None -> []
    Some(c) -> {
      let errors = []

      let errors = case c.minimum {
        Some(min) -> {
          case value <. min {
            True ->
              list.append(errors, [
                error.from_failure(field_path, messages.Minimum(min)),
              ])
            False -> errors
          }
        }
        None -> errors
      }

      let errors = case c.maximum {
        Some(max) -> {
          case value >. max {
            True ->
              list.append(errors, [
                error.from_failure(field_path, messages.Maximum(max)),
              ])
            False -> errors
          }
        }
        None -> errors
      }

      let errors = case c.exclusive_minimum {
        Some(min) -> {
          case value <=. min {
            True ->
              list.append(errors, [
                error.from_failure(field_path, messages.ExclusiveMinimum(min)),
              ])
            False -> errors
          }
        }
        None -> errors
      }

      let errors = case c.exclusive_maximum {
        Some(max) -> {
          case value >=. max {
            True ->
              list.append(errors, [
                error.from_failure(field_path, messages.ExclusiveMaximum(max)),
              ])
            False -> errors
          }
        }
        None -> errors
      }

      // Tolerant multipleOf (Ajv `multipleOfPrecision: 8` / rjsf default):
      // browsers step number inputs in decimal arithmetic, so exact float
      // division would reject values the stepper itself produces (19.99 at
      // step 0.01). Quotients within 1e-8 of an integer pass. Non-positive
      // multipleOf violates the spec (> 0 required) — skipped as a schema bug.
      let errors = case c.multiple_of {
        Some(multiple) if multiple >. 0.0 -> {
          let ratio = value /. multiple
          let nearest = int.to_float(float.round(ratio))
          case float.loosely_equals(ratio, nearest, tolerating: 1.0e-8) {
            True -> errors
            False ->
              list.append(errors, [
                error.from_failure(field_path, messages.MultipleOf(multiple)),
              ])
          }
        }
        _ -> errors
      }

      errors
    }
  }
}

fn validate_boolean(
  field_path: FieldPath,
  value: Value,
) -> List(ValidationError) {
  case value {
    BooleanValue(_) -> []
    _ -> [
      error.from_failure(field_path, messages.InvalidBoolean),
    ]
  }
}

fn validate_enum(
  field_path: FieldPath,
  value: Value,
  allowed_values: List(types.Value),
) -> List(ValidationError) {
  case
    list.any(allowed_values, fn(allowed) {
      conditional_resolver.compare_values(allowed, value)
    })
  {
    True -> []
    False -> [
      error.from_failure(field_path, messages.InvalidEnum),
    ]
  }
}

fn validate_email(email: String) -> Bool {
  string.contains(email, "@") && string.contains(email, ".")
}

fn validate_url(url: String) -> Bool {
  string.starts_with(url, "http://") || string.starts_with(url, "https://")
}

/// Validate all fields of a single array item.
///
/// `array_path` is the path to the array itself (e.g. `[lesions]` for a
/// top-level array, or `[outer, [2], inner]` for nested arrays). Item-level
/// `if/then/else` and `allOf` rules are resolved against the row's own
/// values, then every field of the resolved schema is validated. Errors
/// carry the path `[..array_path, ArraySegment(index), PropertySegment(field)]`.
pub fn validate_array_item(
  array_path: FieldPath,
  index: Int,
  item_schema: SchemaProperty,
  item_values: Dict(String, Value),
) -> List(ValidationError) {
  validate_resolved_props(item_schema, item_values, fn(field_name) {
    list.append(array_path, [ArraySegment(index), PropertySegment(field_name)])
  })
}

/// Validate every row of an array against item-level conditional rules.
pub fn validate_array_items(
  array_path: FieldPath,
  item_schema: SchemaProperty,
  array_value: Value,
) -> List(ValidationError) {
  case array_value {
    ArrayValue(items) ->
      list.index_map(items, fn(item, index) {
        let item_values = case item {
          ObjectValue(fields) -> dict.from_list(fields)
          _ -> dict.new()
        }
        validate_array_item(array_path, index, item_schema, item_values)
      })
      |> list.flatten
    _ -> []
  }
}

/// Validate every field of a nested object against its schema.
pub fn validate_object_fields(
  object_path: FieldPath,
  schema_prop: SchemaProperty,
  values: Dict(String, Value),
) -> List(ValidationError) {
  validate_resolved_props(schema_prop, values, fn(field_name) {
    list.append(object_path, [PropertySegment(field_name)])
  })
}

/// Shared core for `validate_array_item` / `validate_object_fields`.
fn validate_resolved_props(
  schema_prop: SchemaProperty,
  values: Dict(String, Value),
  key_for: fn(String) -> FieldPath,
) -> List(ValidationError) {
  // `resolve_conditional_property` now operates on a `Value` tree. Wrap
  // the local Dict into the equivalent `ObjectValue`; broader Dict→Value
  // migration through this validator is left for a follow-up.
  let resolved =
    conditional_resolver.resolve_conditional_property(
      schema_prop,
      ObjectValue(dict.to_list(values)),
    )

  case resolved.properties {
    Some(props) ->
      list.flat_map(props, fn(entry) {
        let #(field_name, field_prop) = entry
        let field_value = dict.get(values, field_name) |> option.from_result
        let is_required = list.contains(resolved.required, field_name)
        let field_path = key_for(field_name)
        // Nested validation only sees x-widget here — UiSchema lookup for
        // nested image-upload fields lives in callers that have access to
        // the model. Nested image-upload widgets are not yet supported
        // (see CLAUDE.md), so this fallback is sufficient.
        let own_errors =
          validate_field(
            field_path,
            field_value,
            field_prop,
            is_required,
            field_prop.render_hints.widget,
          )
        let nested = validate_nested(field_path, field_prop, field_value)
        list.append(own_errors, nested)
      })
    None -> []
  }
}

/// Validate an array's length against its `minItems`/`maxItems` constraints.
///
/// Mirrors JSON Schema semantics: the check only applies when the value
/// actually is an array. Absent values are the `required` rule's territory.
/// The error is keyed at the array's own path (the container node).
fn validate_array_length(
  field_path: FieldPath,
  constraints: Option(types.ArrayConstraints),
  value: Option(Value),
) -> List(ValidationError) {
  case constraints, value {
    Some(c), Some(ArrayValue(items)) -> {
      let count = list.length(items)
      let min_errors = case c.min_items {
        Some(min) ->
          case count < min {
            True -> [error.from_failure(field_path, messages.MinItems(min))]
            False -> []
          }
        None -> []
      }
      let max_errors = case c.max_items {
        Some(max) ->
          case count > max {
            True -> [error.from_failure(field_path, messages.MaxItems(max))]
            False -> []
          }
        None -> []
      }
      list.append(min_errors, max_errors)
    }
    _, _ -> []
  }
}

/// Recurse into nested object/array structures and collect their errors.
pub fn validate_nested(
  prefix: FieldPath,
  field_prop: SchemaProperty,
  field_value: Option(Value),
) -> List(ValidationError) {
  case field_prop.field_type, field_prop.items {
    Some(types.ArrayType), Some(item_subschema) -> {
      let av = option.unwrap(field_value, NullValue)
      list.append(
        validate_array_length(prefix, field_prop.array_constraints, field_value),
        validate_array_items(prefix, item_subschema, av),
      )
    }
    Some(types.ArrayType), None ->
      validate_array_length(prefix, field_prop.array_constraints, field_value)
    Some(types.ObjectType), _ ->
      case field_value {
        Some(ObjectValue(fields)) ->
          validate_object_fields(prefix, field_prop, dict.from_list(fields))
        _ -> []
      }
    _, _ -> []
  }
}
