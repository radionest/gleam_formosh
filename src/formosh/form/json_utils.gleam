// JSON utility functions for form value conversion

import formosh/schema/types.{
  type Value, ArrayValue, BooleanValue, IntegerValue, NullValue, NumberValue,
  ObjectValue, StringValue,
}
import gleam/json
import gleam/list

/// Convert a Value to JSON for serialization.
pub fn value_to_json(value: Value) -> json.Json {
  case value {
    StringValue(s) -> json.string(s)
    NumberValue(n) -> json.float(n)
    IntegerValue(i) -> json.int(i)
    BooleanValue(b) -> json.bool(b)
    NullValue -> json.null()
    ArrayValue(items) -> json.array(items, value_to_json)
    ObjectValue(fields) ->
      json.object(
        fields
        |> list.map(fn(pair) {
          let #(key, val) = pair
          #(key, value_to_json(val))
        }),
      )
  }
}
