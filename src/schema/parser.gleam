import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import schema/types.{
  type FieldType, type JsonSchema, type JsonValue, type NumberConstraints,
  type SchemaProperty, type StringConstraints, ArrayType, BooleanType,
  CustomFormat, EmailFormat, IntegerType, JsonBool, JsonNull, JsonNumber,
  JsonSchema, JsonString, NullType, NumberConstraints, NumberType, ObjectType,
  SchemaProperty, StringConstraints, StringType, UrlFormat, UuidFormat,
}

/// Errors that can occur during JSON Schema parsing.
/// 
/// These errors provide specific information about what went wrong
/// during the parsing process to help with debugging.
pub type ParseError {
  InvalidJson(String)
  MissingField(String)
  InvalidType(String)
  UnexpectedValue(String)
  DecodingError(List(decode.DecodeError))
}

/// Parse a JSON string into a JsonSchema.
/// 
/// This is the main entry point for converting a JSON Schema document
/// (as a string) into the internal JsonSchema type that can be used
/// to generate forms.
/// 
/// ## Parameters
/// - `json_string`: A valid JSON string containing a JSON Schema
/// 
/// ## Returns
/// - `Ok(JsonSchema)` if parsing succeeded
/// - `Error(ParseError)` if the JSON was invalid or couldn't be decoded
/// 
/// ## Example
/// ```gleam
/// let schema_json = "{\"title\": \"My Form\", \"type\": \"object\", ...}"
/// case parser.parse_schema(schema_json) {
///   Ok(schema) -> // Use the parsed schema
///   Error(ParseError.InvalidJson(msg)) -> // Handle JSON syntax error
///   Error(error) -> // Handle other parsing errors
/// }
/// ```
pub fn parse_schema(json_string: String) -> Result(JsonSchema, ParseError) {
  json_string
  |> json.parse(using: schema_decoder())
  |> result.map_error(fn(error) {
    case error {
      json.UnableToDecode(errors) -> DecodingError(errors)
      json.UnexpectedEndOfInput -> InvalidJson("Unexpected end of input")
      json.UnexpectedByte(byte) -> InvalidJson("Unexpected byte: " <> byte)
      json.UnexpectedSequence(seq) ->
        InvalidJson("Unexpected sequence: " <> seq)
    }
  })
}

/// Main schema decoder for the root JSON Schema object.
/// 
/// This decoder handles the top-level schema properties including title,
/// description, type, properties, required fields, and any root-level
/// validation constraints.
fn schema_decoder() -> Decoder(JsonSchema) {
  use title <- decode.field("title", decode.string)
  use description <- decode.optional_field(
    "description",
    None,
    decode.optional(decode.string),
  )
  use field_type <- decode.optional_field(
    "type",
    ObjectType,
    field_type_decoder(),
  )
  use properties <- decode.optional_field(
    "properties",
    dict.new(),
    properties_decoder(),
  )
  use required <- decode.optional_field(
    "required",
    [],
    decode.list(decode.string),
  )

  // Try to extract constraints from the top level
  use dynamic_data <- decode.then(decode.dynamic)

  let string_constraints = extract_string_constraints(dynamic_data)
  let number_constraints = extract_number_constraints(dynamic_data)

  decode.success(JsonSchema(
    title: title,
    description: description,
    field_type: field_type,
    properties: properties,
    required: required,
    string_constraints: string_constraints,
    number_constraints: number_constraints,
  ))
}

/// Decode a field type string into a FieldType.
/// 
/// Converts JSON Schema type strings ("string", "number", etc.) into
/// the corresponding FieldType enum values.
fn field_type_decoder() -> Decoder(FieldType) {
  decode.string
  |> decode.then(fn(type_str) {
    case type_str {
      "string" -> decode.success(StringType)
      "number" -> decode.success(NumberType)
      "integer" -> decode.success(IntegerType)
      "boolean" -> decode.success(BooleanType)
      "null" -> decode.success(NullType)
      "array" -> decode.success(ArrayType)
      "object" -> decode.success(ObjectType)
      _ -> decode.failure(StringType, "Unknown field type: " <> type_str)
    }
  })
}

/// Decode the "properties" object from a JSON Schema.
/// 
/// This decoder handles the properties object which contains all the
/// field definitions for an object-type schema.
fn properties_decoder() -> Decoder(Dict(String, SchemaProperty)) {
  decode.dict(decode.string, property_decoder())
}

/// Decode a single schema property definition.
/// 
/// This decoder handles both simple property definitions (just a type string)
/// and complex property objects with constraints, metadata, and nested structures.
fn property_decoder() -> Decoder(SchemaProperty) {
  decode.one_of(full_property_decoder(), [
    // Fallback to simple type string
    decode.string
    |> decode.map(fn(type_str) {
      SchemaProperty(
        field_type: case type_str {
          "string" -> Some(StringType)
          "number" -> Some(NumberType)
          "integer" -> Some(IntegerType)
          "boolean" -> Some(BooleanType)
          "null" -> Some(NullType)
          "array" -> Some(ArrayType)
          "object" -> Some(ObjectType)
          _ -> None
        },
        title: None,
        description: None,
        default: None,
        enum_values: None,
        string_constraints: None,
        number_constraints: None,
        items: None,
        properties: None,
        required: [],
      )
    }),
  ])
}

/// Decode a complete property object with all possible fields.
/// 
/// This decoder extracts all the possible fields from a property definition
/// including type, constraints, metadata, and nested schema information.
fn full_property_decoder() -> Decoder(SchemaProperty) {
  use dynamic_data <- decode.then(decode.dynamic)
  use field_type <- decode.optional_field(
    "type",
    None,
    decode.optional(field_type_decoder()),
  )
  use title <- decode.optional_field(
    "title",
    None,
    decode.optional(decode.string),
  )
  use description <- decode.optional_field(
    "description",
    None,
    decode.optional(decode.string),
  )
  use default <- decode.optional_field(
    "default",
    None,
    decode.optional(json_value_decoder()),
  )
  use enum_values <- decode.optional_field(
    "enum",
    None,
    decode.optional(decode.list(json_value_decoder())),
  )
  use items <- decode.optional_field(
    "items",
    None,
    decode.optional(property_decoder()),
  )
  use properties <- decode.optional_field(
    "properties",
    None,
    decode.optional(properties_decoder()),
  )
  use required <- decode.optional_field(
    "required",
    [],
    decode.list(decode.string),
  )

  // Extract constraints from the dynamic data
  let string_constraints = extract_string_constraints(dynamic_data)
  let number_constraints = extract_number_constraints(dynamic_data)

  decode.success(SchemaProperty(
    field_type: field_type,
    title: title,
    description: description,
    default: default,
    enum_values: enum_values,
    string_constraints: string_constraints,
    number_constraints: number_constraints,
    items: items,
    properties: properties,
    required: required,
  ))
}

/// Extract string validation constraints from dynamic JSON data.
/// 
/// This function looks for string constraint fields (minLength, maxLength,
/// pattern, format) in the JSON data and builds a StringConstraints object.
/// 
/// ## Parameters
/// - `data`: Dynamic JSON data that might contain string constraints
/// 
/// ## Returns
/// - `Some(StringConstraints)` if any constraints were found
/// - `None` if no string constraints are present
fn extract_string_constraints(data: Dynamic) -> Option(StringConstraints) {
  let min_length =
    decode.run(data, decode.at(["minLength"], decode.int))
    |> option.from_result()

  let max_length =
    decode.run(data, decode.at(["maxLength"], decode.int))
    |> option.from_result()

  let pattern =
    decode.run(data, decode.at(["pattern"], decode.string))
    |> option.from_result()

  let format =
    decode.run(data, decode.at(["format"], format_decoder()))
    |> option.from_result()

  case min_length, max_length, pattern, format {
    None, None, None, None -> None
    _, _, _, _ ->
      Some(StringConstraints(
        min_length: min_length,
        max_length: max_length,
        pattern: pattern,
        format: format,
      ))
  }
}

/// Extract numeric validation constraints from dynamic JSON data.
/// 
/// This function looks for numeric constraint fields (minimum, maximum,
/// exclusiveMinimum, exclusiveMaximum, multipleOf) in the JSON data and
/// builds a NumberConstraints object.
/// 
/// ## Parameters
/// - `data`: Dynamic JSON data that might contain numeric constraints
/// 
/// ## Returns
/// - `Some(NumberConstraints)` if any constraints were found
/// - `None` if no numeric constraints are present
fn extract_number_constraints(data: Dynamic) -> Option(NumberConstraints) {
  let minimum =
    decode.run(data, decode.at(["minimum"], decode.float))
    |> option.from_result()

  let maximum =
    decode.run(data, decode.at(["maximum"], decode.float))
    |> option.from_result()

  let exclusive_minimum =
    decode.run(data, decode.at(["exclusiveMinimum"], decode.float))
    |> option.from_result()

  let exclusive_maximum =
    decode.run(data, decode.at(["exclusiveMaximum"], decode.float))
    |> option.from_result()

  let multiple_of =
    decode.run(data, decode.at(["multipleOf"], decode.float))
    |> option.from_result()

  case minimum, maximum, exclusive_minimum, exclusive_maximum, multiple_of {
    None, None, None, None, None -> None
    _, _, _, _, _ ->
      Some(NumberConstraints(
        minimum: minimum,
        maximum: maximum,
        exclusive_minimum: exclusive_minimum,
        exclusive_maximum: exclusive_maximum,
        multiple_of: multiple_of,
      ))
  }
}

/// Decode a string format specifier into a StringFormat.
/// 
/// Converts JSON Schema format strings into StringFormat enum values,
/// with support for standard formats and custom format strings.
fn format_decoder() -> Decoder(types.StringFormat) {
  decode.string
  |> decode.then(fn(format_str) {
    case format_str {
      "email" -> decode.success(EmailFormat)
      "url" | "uri" -> decode.success(UrlFormat)
      "uuid" -> decode.success(UuidFormat)
      _ -> decode.success(CustomFormat(format_str))
    }
  })
}

/// Decode arbitrary JSON values for enum values and default values.
/// 
/// This decoder can handle any valid JSON value (string, number, boolean,
/// array, object, null) and converts it to the appropriate JsonValue variant.
/// It's used for parsing enum options and default values in schemas.
fn json_value_decoder() -> Decoder(JsonValue) {
  use dynamic_value <- decode.then(decode.dynamic)

  // Try different decoders in order of preference
  case decode.run(dynamic_value, decode.string) {
    Ok(s) -> decode.success(JsonString(s))
    Error(_) ->
      case decode.run(dynamic_value, decode.int) {
        Ok(i) -> decode.success(types.JsonInteger(i))
        Error(_) ->
          case decode.run(dynamic_value, decode.float) {
            Ok(f) -> decode.success(JsonNumber(f))
            Error(_) ->
              case decode.run(dynamic_value, decode.bool) {
                Ok(b) -> decode.success(JsonBool(b))
                Error(_) ->
                  case decode.run(dynamic_value, decode.list(decode.dynamic)) {
                    Ok(arr) -> {
                      let decoded_items =
                        arr
                        |> list.filter_map(fn(item) {
                          case decode.run(item, json_value_decoder()) {
                            Ok(value) -> Ok(value)
                            Error(_) -> Error(Nil)
                          }
                        })
                      decode.success(types.JsonArray(decoded_items))
                    }
                    Error(_) ->
                      case
                        decode.run(
                          dynamic_value,
                          decode.dict(decode.string, decode.dynamic),
                        )
                      {
                        Ok(obj) -> {
                          let decoded_list =
                            dict.to_list(obj)
                            |> list.filter_map(fn(pair) {
                              let #(key, value) = pair
                              case decode.run(value, json_value_decoder()) {
                                Ok(decoded_value) -> Ok(#(key, decoded_value))
                                Error(_) -> Error(Nil)
                              }
                            })
                          decode.success(types.JsonObject(decoded_list))
                        }
                        Error(_) -> decode.success(JsonNull)
                      }
                  }
              }
          }
      }
  }
}
