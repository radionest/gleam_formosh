// Validation functions for form fields

import formosh/form/path.{type FieldPath, ArraySegment, PropertySegment}
import formosh/schema/conditional_resolver
import formosh/schema/types.{
  type SchemaProperty, type Value, ArrayValue, BooleanValue, IntegerValue,
  NullValue, NumberValue, ObjectValue, StringValue,
}
import formosh/validation/error.{type ValidationError, ValidationError}
import formosh/validation/field_requirements
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// Validate a field value against its schema property definition.
///
/// `field_path` is the canonical path used by every form layer; errors built
/// here are keyed by this path without any intermediate string round-trip.
pub fn validate_field(
  field_path: FieldPath,
  value: Option(Value),
  property: SchemaProperty,
  is_required: Bool,
) -> List(ValidationError) {
  case property.widget {
    Some("image-upload") ->
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
          ValidationError(
            field: field_path,
            message: "At least one image is required",
            rule: "required",
          ),
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
          ValidationError(
            field: field_path,
            message: "Invalid image upload value",
            rule: "type",
          ),
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
          validate_string(field_path, val, property.string_constraints)
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
) -> List(ValidationError) {
  case value {
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
                    ValidationError(
                      field: field_path,
                      message: "Must be at least "
                        <> int.to_string(min)
                        <> " characters",
                      rule: "minLength",
                    ),
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
                    ValidationError(
                      field: field_path,
                      message: "Must be at most "
                        <> int.to_string(max)
                        <> " characters",
                      rule: "maxLength",
                    ),
                  ])
                False -> errors
              }
            }
            None -> errors
          }

          let errors = case c.pattern {
            Some(_pattern) -> errors
            None -> errors
          }

          let errors = case c.format {
            Some(types.EmailFormat) ->
              case validate_email(str) {
                False ->
                  list.append(errors, [
                    ValidationError(
                      field: field_path,
                      message: "Invalid email address",
                      rule: "format",
                    ),
                  ])
                True -> errors
              }
            Some(types.UrlFormat) | Some(types.UriFormat) ->
              case validate_url(str) {
                False ->
                  list.append(errors, [
                    ValidationError(
                      field: field_path,
                      message: "Invalid URL",
                      rule: "format",
                    ),
                  ])
                True -> errors
              }
            _ -> errors
          }

          errors
        }
      }
    }
    _ -> [
      ValidationError(
        field: field_path,
        message: "Must be a string",
        rule: "type",
      ),
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
      ValidationError(
        field: field_path,
        message: "Must be a number",
        rule: "type",
      ),
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
                ValidationError(
                  field: field_path,
                  message: "Must be at least " <> float.to_string(min),
                  rule: "minimum",
                ),
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
                ValidationError(
                  field: field_path,
                  message: "Must be at most " <> float.to_string(max),
                  rule: "maximum",
                ),
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
                ValidationError(
                  field: field_path,
                  message: "Must be greater than " <> float.to_string(min),
                  rule: "exclusiveMinimum",
                ),
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
                ValidationError(
                  field: field_path,
                  message: "Must be less than " <> float.to_string(max),
                  rule: "exclusiveMaximum",
                ),
              ])
            False -> errors
          }
        }
        None -> errors
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
      ValidationError(
        field: field_path,
        message: "Must be true or false",
        rule: "type",
      ),
    ]
  }
}

fn validate_enum(
  _field_path: FieldPath,
  _value: Value,
  _allowed_values: List(types.Value),
) -> List(ValidationError) {
  []
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
        let own_errors =
          validate_field(field_path, field_value, field_prop, is_required)
        let nested = validate_nested(field_path, field_prop, field_value)
        list.append(own_errors, nested)
      })
    None -> []
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
      validate_array_items(prefix, item_subschema, av)
    }
    Some(types.ObjectType), _ ->
      case field_value {
        Some(ObjectValue(fields)) ->
          validate_object_fields(prefix, field_prop, dict.from_list(fields))
        _ -> []
      }
    _, _ -> []
  }
}
