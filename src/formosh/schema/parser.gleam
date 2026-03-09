import formosh/schema/resolver
import formosh/schema/types.{
  type ConditionalRule, type FieldType, type JsonSchema, type NumberConstraints,
  type SchemaProperty, type StringConstraints, type Value, ArrayType,
  BooleanType, BooleanValue, ConditionalRule, CustomFormat, EmailFormat,
  IntegerType, IntegerValue, JsonSchema, NullType, NullValue, NumberConstraints,
  NumberType, NumberValue, ObjectType, SchemaProperty, StringConstraints,
  StringType, StringValue, UrlFormat, UuidFormat,
}
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

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
/// to generate forms. It automatically resolves all $ref references.
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
  use parsed_schema <- result.try(
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
    }),
  )

  // Resolve all $ref references in the schema
  parsed_schema
  |> resolver.resolve_refs()
  |> result.map_error(fn(error) {
    case error {
      resolver.ReferenceNotFound(ref) ->
        UnexpectedValue("Reference not found: " <> ref)
      resolver.CircularReference(ref) ->
        UnexpectedValue("Circular reference detected: " <> ref)
      resolver.InvalidReference(ref) ->
        UnexpectedValue("Invalid reference format: " <> ref)
    }
  })
}

/// Main schema decoder for the root JSON Schema object.
/// 
/// This decoder handles the top-level schema properties including title,
/// description, type, properties, required fields, and any root-level
/// validation constraints.
fn schema_decoder() -> Decoder(JsonSchema) {
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
  use defs <- decode.optional_field(
    "$defs",
    None,
    decode.optional(definitions_decoder()),
  )

  // Try to extract constraints from the top level
  use dynamic_data <- decode.then(decode.dynamic)

  let string_constraints = extract_string_constraints(dynamic_data)
  let number_constraints = extract_number_constraints(dynamic_data)

  // Extract conditional rules
  let conditionals = extract_conditionals(dynamic_data)

  decode.success(JsonSchema(
    title: title,
    description: description,
    field_type: field_type,
    properties: properties,
    required: required,
    defs: defs,
    conditionals: conditionals,
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

/// Decode the "$defs" object from a JSON Schema.
/// 
/// This decoder handles the definitions object which contains reusable
/// schema definitions that can be referenced via $ref.
fn definitions_decoder() -> Decoder(Dict(String, SchemaProperty)) {
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
        one_of: None,
        ref: None,
        string_constraints: None,
        number_constraints: None,
        items: None,
        properties: None,
        required: [],
        read_only: False,
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
    decode.optional(value_decoder()),
  )
  use enum_values <- decode.optional_field(
    "enum",
    None,
    decode.optional(decode.list(value_decoder())),
  )
  use ref <- decode.optional_field("$ref", None, decode.optional(decode.string))
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

  // Extract readOnly annotation
  let read_only = extract_read_only(dynamic_data)

  // Handle 'const' keyword - convert to enum with single value
  let enum_values_with_const = case enum_values {
    Some(_) -> enum_values
    None -> extract_const_value(dynamic_data)
  }

  // Extract oneOf composition keyword
  let one_of = extract_one_of(dynamic_data)

  decode.success(SchemaProperty(
    field_type: field_type,
    title: title,
    description: description,
    default: default,
    enum_values: enum_values_with_const,
    one_of: one_of,
    ref: ref,
    string_constraints: string_constraints,
    number_constraints: number_constraints,
    items: items,
    properties: properties,
    required: required,
    read_only: read_only,
  ))
}

/// Extract const value from dynamic JSON data.
///
/// This function looks for the 'const' keyword in JSON Schema and converts it
/// to an enum with a single value, which is semantically equivalent.
///
/// ## Parameters
/// - `data`: Dynamic JSON data that might contain a const value
///
/// ## Returns
/// - `Some(List(Value))` with single value if const is present
/// - `None` if no const keyword is found
fn extract_const_value(data: Dynamic) -> Option(List(Value)) {
  decode.run(data, decode.at(["const"], value_decoder()))
  |> result.map(fn(const_value) { [const_value] })
  |> option.from_result()
}

/// Extract oneOf composition keyword from dynamic JSON data.
///
/// This function looks for the 'oneOf' keyword in JSON Schema and parses
/// each sub-schema using the standard property decoder.
///
/// ## Parameters
/// - `data`: Dynamic JSON data that might contain a oneOf array
///
/// ## Returns
/// - `Some(List(SchemaProperty))` if oneOf is present
/// - `None` if no oneOf keyword is found
fn extract_one_of(data: Dynamic) -> Option(List(SchemaProperty)) {
  decode.run(data, decode.at(["oneOf"], decode.list(property_decoder())))
  |> option.from_result()
}

/// Extract string validation constraints from dynamic JSON data.
///
///
/// This function looks for string constraint fields (minLength, maxLength,
/// pattern, format) in the JSON data and builds a StringConstraints object.
///
///
/// ## Parameters
/// - `data`: Dynamic JSON data that might contain string constraints
///
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

/// Extract conditional rules from a JSON Schema.
///
/// Parses if/then/else keywords or allOf array with conditionals to create
/// conditional rules that can dynamically modify the schema based on runtime values.
///
/// Supports both:
/// - Direct if/then/else at the top level
/// - allOf array containing multiple if/then/else conditions
/// Parses if/then/else keywords or allOf array with conditionals to create
/// conditional rules that can dynamically modify the schema based on runtime values.
///
/// Supports both:
/// - Direct if/then/else at the top level
/// - allOf array containing multiple if/then/else conditions
fn extract_conditionals(data: Dynamic) -> List(ConditionalRule) {
  // First, check if there's an allOf array
  case decode.run(data, decode.at(["allOf"], decode.list(decode.dynamic))) {
    Ok(allof_items) -> extract_allof_conditionals(allof_items)
    Error(_) -> extract_single_conditional(data)
  }
}

/// Extract multiple conditional rules from an allOf array.
///
/// Iterates through each item in the allOf array and attempts to extract
/// if/then/else conditional rules.
fn extract_allof_conditionals(items: List(Dynamic)) -> List(ConditionalRule) {
  list.filter_map(items, fn(item) { extract_single_conditional_result(item) })
}

/// Extract a single conditional rule from dynamic data, returning a Result.
///
/// This is used by extract_allof_conditionals for filter_map.
fn extract_single_conditional_result(
  data: Dynamic,
) -> Result(ConditionalRule, Nil) {
  case extract_single_conditional(data) {
    [rule] -> Ok(rule)
    _ -> Error(Nil)
  }
}

/// Extract a single if/then/else conditional from dynamic data.
///
/// Returns a list with 0 or 1 conditional rules.
fn extract_single_conditional(data: Dynamic) -> List(ConditionalRule) {
  // Check if there's an "if" field at the top level
  let if_result = decode.run(data, decode.at(["if"], decode.dynamic))

  case if_result {
    Ok(if_data) -> {
      // We have an if condition, now look for then/else
      let then_result =
        decode.run(data, decode.at(["then"], decode.dynamic))
        |> result.map(fn(dyn) {
          decode.run(dyn, property_decoder())
          |> option.from_result()
        })
        |> result.unwrap(None)

      let else_result =
        decode.run(data, decode.at(["else"], decode.dynamic))
        |> result.map(fn(dyn) {
          decode.run(dyn, property_decoder())
          |> option.from_result()
        })
        |> result.unwrap(None)

      // Parse the if condition as a property schema
      case decode.run(if_data, property_decoder()) {
        Ok(if_schema) -> {
          [
            ConditionalRule(
              if_schema: if_schema,
              then_schema: then_result,
              else_schema: else_result,
            ),
          ]
        }
        Error(_) -> []
      }
    }
    Error(_) -> []
  }
}

/// Extract readOnly annotation from dynamic JSON data.
///
/// This function looks for the 'readOnly' keyword in JSON Schema which indicates
/// that the field should not be modified by the user.
///
/// ## Parameters
/// - `data`: Dynamic JSON data that might contain readOnly annotation
///
/// ## Returns
/// - `True` if readOnly is present and true
/// - `False` otherwise
fn extract_read_only(data: Dynamic) -> Bool {
  decode.run(data, decode.at(["readOnly"], decode.bool))
  |> result.unwrap(False)
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
/// array, object, null) and converts it to the appropriate Value variant.
/// It's used for parsing enum options and default values in schemas.
pub fn value_decoder() -> Decoder(Value) {
  use dynamic_value <- decode.then(decode.dynamic)

  // Try different decoders in order of preference
  case decode.run(dynamic_value, decode.string) {
    Ok(s) -> decode.success(StringValue(s))
    Error(_) ->
      case decode.run(dynamic_value, decode.int) {
        Ok(i) -> decode.success(IntegerValue(i))
        Error(_) ->
          case decode.run(dynamic_value, decode.float) {
            Ok(f) -> decode.success(NumberValue(f))
            Error(_) ->
              case decode.run(dynamic_value, decode.bool) {
                Ok(b) -> decode.success(BooleanValue(b))
                Error(_) ->
                  case decode.run(dynamic_value, decode.list(decode.dynamic)) {
                    Ok(arr) -> {
                      let decoded_items =
                        arr
                        |> list.filter_map(fn(item) {
                          case decode.run(item, value_decoder()) {
                            Ok(value) -> Ok(value)
                            Error(_) -> Error(Nil)
                          }
                        })
                      decode.success(types.ArrayValue(decoded_items))
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
                              case decode.run(value, value_decoder()) {
                                Ok(decoded_value) -> Ok(#(key, decoded_value))
                                Error(_) -> Error(Nil)
                              }
                            })
                          decode.success(types.ObjectValue(decoded_list))
                        }
                        Error(_) -> decode.success(NullValue)
                      }
                  }
              }
          }
      }
  }
}
