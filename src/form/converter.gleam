//// JSON/FieldValue conversion utilities for the Formosh form library.
//// 
//// This module provides bidirectional conversion between JsonValue and FieldValue types,
//// supporting both safe and unsafe conversion patterns used throughout the codebase.

import gleam/option.{type Option, Some}
import schema/types.{
  type FieldValue, type JsonValue, ArrayValue, BooleanValue, IntegerValue,
  JsonArray, JsonBool, JsonInteger, JsonNull, JsonNumber, JsonObject, JsonString,
  NullValue, NumberValue, ObjectValue, StringValue,
}

/// Convert JsonValue to FieldValue with error handling.
/// Returns Some(FieldValue) on successful conversion, None if conversion fails.
pub fn json_to_field_value(json: JsonValue) -> Option(FieldValue) {
  case json {
    JsonString(s) -> Some(StringValue(s))
    JsonNumber(n) -> Some(NumberValue(n))
    JsonInteger(i) -> Some(IntegerValue(i))
    JsonBool(b) -> Some(BooleanValue(b))
    JsonArray(items) -> Some(ArrayValue(items))
    JsonObject(fields) -> Some(ObjectValue(fields))
    JsonNull -> Some(NullValue)
  }
}

/// Convert JsonValue to FieldValue with fallback to NullValue.
/// This never fails - returns NullValue if conversion cannot be completed.
pub fn json_to_field_value_safe(json: JsonValue) -> FieldValue {
  json_to_field_value(json) |> option.unwrap(NullValue)
}

/// Convert FieldValue to JsonValue.
/// This conversion is always safe since FieldValue is a subset of JsonValue.
pub fn field_value_to_json_value(value: FieldValue) -> JsonValue {
  case value {
    StringValue(s) -> JsonString(s)
    NumberValue(n) -> JsonNumber(n)
    IntegerValue(i) -> JsonInteger(i)
    BooleanValue(b) -> JsonBool(b)
    ArrayValue(items) -> JsonArray(items)
    ObjectValue(fields) -> JsonObject(fields)
    NullValue -> JsonNull
  }
}
