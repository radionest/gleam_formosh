// JSON utility functions for form value conversion

import formosh/schema/parser
import formosh/schema/types.{
  type ParseError, type Value, ArrayValue, BooleanValue, IntegerValue, NullValue,
  NumberValue, ObjectValue, StringValue,
}
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result

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

/// Parse a JSON string into a dictionary of Values.
///
/// Converts a JSON object string into a `Dict(String, Value)` suitable
/// for use as initial form values.
///
/// ## Parameters
/// - `json_string`: A valid JSON object string
///
/// ## Returns
/// - `Ok(Dict(String, Value))` if parsing succeeded
/// - `Error(ParseError)` if the JSON was invalid or not an object — the
///   same typed error every other parse boundary in the library reports,
///   so a malformed `initial-values` attribute is debuggable (#82; the
///   pre-0.11 signature collapsed every failure into `Nil`)
pub fn json_string_to_values(
  json_string: String,
) -> Result(Dict(String, Value), ParseError) {
  let decoder = decode.dict(decode.string, parser.value_decoder())
  json.parse(json_string, decoder)
  |> result.map_error(json_error_to_parse_error)
}

fn json_error_to_parse_error(err: json.DecodeError) -> ParseError {
  case err {
    json.UnableToDecode(errors) -> types.DecodingError(errors)
    json.UnexpectedEndOfInput -> types.InvalidJson("Unexpected end of input")
    json.UnexpectedByte(byte) -> types.InvalidJson("Unexpected byte: " <> byte)
    json.UnexpectedSequence(seq) ->
      types.InvalidJson("Unexpected sequence: " <> seq)
  }
}
