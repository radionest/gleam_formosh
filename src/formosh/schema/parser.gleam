import formosh/ffi/dynamic_object
import formosh/schema/composer
import formosh/schema/resolver
import formosh/schema/types.{
  type ArrayConstraints, type ConditionalRule, type FieldType, type JsonSchema,
  type NumberConstraints, type ParseError, type SchemaProperty,
  type StringConstraints, type Value, ArrayConstraints, ArrayType, BooleanType,
  BooleanValue, ConditionalRule, CustomFormat, DateFormat, DecodingError,
  EmailFormat, IntegerType, IntegerValue, InvalidJson, JsonSchema, NullType,
  NullValue, NumberConstraints, NumberType, NumberValue, ObjectType,
  PasswordFormat, SchemaProperty, StringConstraints, StringType, StringValue,
  TimeFormat, UnexpectedValue, UrlFormat, UuidFormat, empty_property,
}
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

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
  use #(root, defs) <- result.try(
    json_string
    |> json.parse(using: root_decoder())
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

  use resolved <- result.try(
    resolver.resolve_property(root, defs)
    |> result.map_error(fn(error) {
      case error {
        resolver.ReferenceNotFound(ref) ->
          UnexpectedValue("Reference not found: " <> ref)
        resolver.CircularReference(ref) ->
          UnexpectedValue("Circular reference detected: " <> ref)
        resolver.InvalidReference(ref) ->
          UnexpectedValue("Invalid reference format: " <> ref)
      }
    }),
  )

  use flattened <- result.try(composer.flatten_property(resolved))
  Ok(to_json_schema(flattened, defs))
}

/// Decode the document root as a `SchemaProperty` plus its `$defs`.
///
/// The root is a schema like any other node — parsing it through the full
/// property decoder keeps type absence representable (`Option(FieldType)`)
/// until composition has run; `to_json_schema` applies the object default
/// afterwards (issue #70). Uses `full_property_decoder` directly, NOT
/// `property_decoder`: the bare-string shorthand fallback must not make a
/// non-object document (e.g. `"hello"`) parse as an empty schema.
fn root_decoder() -> Decoder(
  #(SchemaProperty, Option(Dict(String, SchemaProperty))),
) {
  use root <- decode.then(full_property_decoder())
  use defs <- decode.optional_field(
    "$defs",
    None,
    decode.optional(definitions_decoder()),
  )
  decode.success(#(root, defs))
}

/// Materialize the public root type from the flattened root property.
/// The `ObjectType` default lands here — after composition — so a type
/// supplied only by an allOf member survives. Fields `JsonSchema` cannot
/// hold (items, enum, default, oneOf, array constraints, readOnly,
/// addable/removable, render hints) are dropped: the root of a form is
/// structurally an object unless the composition says otherwise (D6).
fn to_json_schema(
  root: SchemaProperty,
  defs: Option(Dict(String, SchemaProperty)),
) -> JsonSchema {
  JsonSchema(
    title: root.title,
    description: root.description,
    field_type: option.unwrap(root.field_type, ObjectType),
    properties: option.unwrap(root.properties, []),
    required: root.required,
    defs: defs,
    conditionals: root.conditionals,
    all_of: None,
    string_constraints: root.string_constraints,
    number_constraints: root.number_constraints,
  )
}

/// Single source of truth for a JSON Schema `type` string → FieldType.
///
/// `Error(Nil)` signals an unknown type name; callers decide whether that is
/// a hard parse failure (scalar / root form) or a soft `None` (the bare-string
/// property fallback).
fn field_type_from_string(type_str: String) -> Result(FieldType, Nil) {
  case type_str {
    "string" -> Ok(StringType)
    "number" -> Ok(NumberType)
    "integer" -> Ok(IntegerType)
    "boolean" -> Ok(BooleanType)
    "null" -> Ok(NullType)
    "array" -> Ok(ArrayType)
    "object" -> Ok(ObjectType)
    _ -> Error(Nil)
  }
}

/// Decode a JSON Schema `type` into a FieldType.
///
/// Accepts both the scalar form (`"type": "string"`) and the array/union form
/// (`"type": ["string", "null"]`). For the array form the first **known**
/// non-`"null"` member wins, so `["string","null"]`, `["null","string"]` and
/// the pure union `["string","number"]` all resolve to `StringType`: a
/// nullable union collapses to its base type, and a multi-type union is
/// deliberately reduced to its first known type rather than failing — keeping
/// the *whole* schema parseable was the bug this fixes. An array with only
/// `"null"` (or no known type) resolves to `NullType` so it never aborts the
/// parse.
fn field_type_decoder() -> Decoder(FieldType) {
  decode.one_of(scalar_field_type_decoder(), [array_field_type_decoder()])
}

fn scalar_field_type_decoder() -> Decoder(FieldType) {
  decode.string
  |> decode.then(fn(type_str) {
    case field_type_from_string(type_str) {
      Ok(field_type) -> decode.success(field_type)
      Error(_) -> decode.failure(StringType, "Unknown field type: " <> type_str)
    }
  })
}

fn array_field_type_decoder() -> Decoder(FieldType) {
  decode.list(decode.string)
  |> decode.then(fn(type_strs) {
    let known_types =
      type_strs
      |> list.filter(fn(t) { t != "null" })
      |> list.filter_map(field_type_from_string)
    case known_types {
      [first, ..] -> decode.success(first)
      [] -> decode.success(NullType)
    }
  })
}

/// Decode the "properties" object from a JSON Schema.
///
/// Preserves the original key order from the source JSON by reading the
/// underlying JS object entries (insertion order is guaranteed by ES2020+
/// for string keys) instead of going through `decode.dict`, which builds
/// a hash-based structure that loses ordering.
///
/// If decoding any individual property fails, the whole `properties` block
/// fails fast — matching the prior `decode.dict` behaviour rather than
/// silently dropping malformed entries.
fn properties_decoder() -> Decoder(List(#(String, SchemaProperty))) {
  use dynamic_data <- decode.then(decode.dynamic)
  case dynamic_object.entries(dynamic_data) {
    Error(_) -> decode.failure([], "Expected 'properties' to be a JSON object")
    Ok(entries) -> {
      let try_decode_entry = fn(entry: #(String, Dynamic)) {
        let #(key, value) = entry
        decode.run(value, property_decoder())
        |> result.map(fn(prop) { #(key, prop) })
        |> result.map_error(fn(_) { key })
      }
      case list.try_map(entries, try_decode_entry) {
        Ok(pairs) -> decode.success(pairs)
        Error(key) ->
          decode.failure([], "Invalid schema property at key '" <> key <> "'")
      }
    }
  }
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
        ..empty_property(),
        field_type: field_type_from_string(type_str) |> option.from_result(),
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
  let array_constraints = extract_array_constraints(dynamic_data)

  // Extract readOnly annotation
  let read_only = extract_read_only(dynamic_data)

  // Extract nullable: true when a `type` array contains "null" (the array
  // form of field_type_decoder picks a base type and discards this bit)
  let nullable = extract_nullable(dynamic_data)

  // Extract x-addable / x-removable (default True: structure-mutation allowed)
  let addable = extract_addable(dynamic_data)
  let removable = extract_removable(dynamic_data)

  // Handle 'const' keyword - convert to enum with single value
  let enum_values_with_const = case enum_values {
    Some(_) -> enum_values
    None -> extract_const_value(dynamic_data)
  }

  // Extract oneOf composition keyword
  let one_of = extract_one_of(dynamic_data)

  // Extract anyOf composition keyword — raw members (including null-typed
  // ones) flow through; the composer drops nulls and sets `nullable`
  let any_of = extract_any_of(dynamic_data)

  // Extract allOf composition members — a malformed member fails the parse
  let all_of = extract_all_of(dynamic_data)

  // Extract presentation hints from x- extensions
  let render_hints = extract_render_hints(dynamic_data)

  // Extract property-level direct conditional rule (if/then/else). Rules
  // declared inside allOf members ride on the member schemas and are
  // lifted to this node by composer.flatten_property.
  let conditionals = extract_single_conditional(dynamic_data)

  case all_of {
    Error(_) -> decode.failure(empty_property(), "allOf")
    Ok(all_of) ->
      decode.success(SchemaProperty(
        field_type: field_type,
        title: title,
        description: description,
        default: default,
        enum_values: enum_values_with_const,
        one_of: one_of,
        any_of: any_of,
        all_of: all_of,
        ref: ref,
        string_constraints: string_constraints,
        number_constraints: number_constraints,
        array_constraints: array_constraints,
        items: items,
        properties: properties,
        required: required,
        read_only: read_only,
        nullable: nullable,
        addable: addable,
        removable: removable,
        render_hints: render_hints,
        conditionals: conditionals,
      ))
  }
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

/// Extract anyOf members. Lenient at member level (unlike strict allOf):
/// boolean and malformed members are skipped, the rest still parse. Null
/// members are KEPT here — the composer drops them and sets `nullable`.
fn extract_any_of(data: Dynamic) -> Option(List(SchemaProperty)) {
  decode.run(data, decode.at(["anyOf"], decode.list(decode.dynamic)))
  |> option.from_result()
  |> option.map(fn(members) {
    list.filter_map(members, fn(m) {
      decode.run(m, property_decoder()) |> result.replace_error(Nil)
    })
  })
  |> option.then(fn(members) {
    case members {
      [] -> None
      _ -> Some(members)
    }
  })
}

/// Extract allOf composition members from dynamic JSON data.
///
/// Every member is parsed as an ordinary sub-schema: plain keywords ride on
/// the member record, a member's own if/then/else lands in the member's
/// `conditionals`, and a nested allOf recurses into the member's `all_of`.
/// Members are merged into the parent by `composer.flatten_property` after
/// $ref resolution. Strict, unlike `extract_one_of`: a `true` member is the
/// spec no-op and is skipped, while `false` or a malformed member fails the
/// parse — silently dropping members would weaken validation.
fn extract_all_of(data: Dynamic) -> Result(Option(List(SchemaProperty)), Nil) {
  case decode.run(data, decode.at(["allOf"], decode.dynamic)) {
    Error(_) -> Ok(None)
    Ok(members) ->
      decode.run(members, decode.list(all_of_member_decoder()))
      |> result.map(fn(members) { Some(option.values(members)) })
      |> result.replace_error(Nil)
  }
}

/// Decode a single allOf member. `true` is the JSON Schema no-op — decoded
/// to `None` and dropped by `extract_all_of`; `false` (nothing validates)
/// and non-schema values fail the decode.
fn all_of_member_decoder() -> Decoder(Option(SchemaProperty)) {
  decode.one_of(property_decoder() |> decode.map(Some), [
    decode.bool
    |> decode.then(fn(is_permissive) {
      case is_permissive {
        True -> decode.success(None)
        False -> decode.failure(None, "allOf member")
      }
    }),
  ])
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

/// Extract array validation constraints (minItems / maxItems) from
/// dynamic JSON data.
///
/// ## Returns
/// - `Some(ArrayConstraints)` if any constraint was found
/// - `None` if neither keyword is present
fn extract_array_constraints(data: Dynamic) -> Option(ArrayConstraints) {
  let min_items =
    decode.run(data, decode.at(["minItems"], decode.int))
    |> option.from_result()

  let max_items =
    decode.run(data, decode.at(["maxItems"], decode.int))
    |> option.from_result()

  case min_items, max_items {
    None, None -> None
    // minItems > maxItems is unsatisfiable; normalize so minItems wins —
    // otherwise the reconcile pass tops the array up past maxItems and
    // wedges the form (both buttons hidden, submit permanently blocked).
    Some(min), Some(max) if min > max ->
      Some(ArrayConstraints(min_items: Some(min), max_items: Some(min)))
    _, _ -> Some(ArrayConstraints(min_items: min_items, max_items: max_items))
  }
}

/// Extract a single DIRECT if/then/else conditional from dynamic data.
///
/// Returns a list with 0 or 1 conditional rules. Rules declared inside
/// allOf members ride on the member schemas (see `extract_all_of`) and are
/// lifted to the parent by `composer.flatten_property` — including when a
/// direct rule and allOf coexist on the same node.
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

/// Extract nullable from a `type` array containing `"null"`.
///
/// `array_field_type_decoder` resolves the array form down to a single
/// `FieldType` and discards whether `"null"` was among the members; this
/// re-reads the raw `type` array to recover that bit. A scalar `type`
/// string never signals nullable.
fn extract_nullable(data: Dynamic) -> Bool {
  decode.run(data, decode.at(["type"], decode.list(decode.string)))
  |> result.map(fn(type_strs) { list.contains(type_strs, "null") })
  |> result.unwrap(False)
}

/// Extract x-addable structural flag for arrays.
/// Absent or non-bool -> True (default: add control shown).
///
/// **Deprecated since v0.7** — use `ui:addable` in UiSchema. Scheduled for
/// removal in v0.9.
fn extract_addable(data: Dynamic) -> Bool {
  decode.run(data, decode.at(["x-addable"], decode.bool))
  |> result.unwrap(True)
}

/// Extract x-removable structural flag for arrays.
/// Absent or non-bool -> True (default: remove control shown).
///
/// **Deprecated since v0.7** — use `ui:removable` in UiSchema. Scheduled
/// for removal in v0.9.
fn extract_removable(data: Dynamic) -> Bool {
  decode.run(data, decode.at(["x-removable"], decode.bool))
  |> result.unwrap(True)
}

/// Decode an `x-widget` string into a typed Widget variant.
/// Falls back to `CustomWidget(raw)` so unknown widgets parse round-trip.
fn widget_decoder() -> Decoder(types.Widget) {
  decode.string
  |> decode.then(fn(raw) {
    case raw {
      "image-upload" -> decode.success(types.ImageUploadWidget)
      "hidden" -> decode.success(types.HiddenWidget)
      "swipe-review" -> decode.success(types.SwipeReviewWidget)
      _ -> decode.success(types.CustomWidget(raw))
    }
  })
}

/// Extract x-widget custom widget override from dynamic JSON data.
///
/// **Deprecated since v0.7** — use `ui:widget` in UiSchema. Scheduled for
/// removal in v0.9.
fn extract_widget(data: Dynamic) -> Option(types.Widget) {
  decode.run(data, decode.at(["x-widget"], widget_decoder()))
  |> option.from_result()
}

/// Extract upload configuration from x- extension fields.
/// Only emits config when widget is ImageUploadWidget.
///
/// **Deprecated since v0.7** — use `ui:accept` / `ui:maxFileSize` in
/// UiSchema. Scheduled for removal in v0.9.
fn extract_upload_config(
  data: Dynamic,
  widget: Option(types.Widget),
) -> Option(types.UploadConfig) {
  case widget {
    Some(types.ImageUploadWidget) -> {
      let accept =
        decode.run(data, decode.at(["x-accept"], decode.string))
        |> option.from_result()
      let max_file_size =
        decode.run(data, decode.at(["x-max-file-size"], decode.int))
        |> option.from_result()
      Some(types.UploadConfig(
        accept: option.unwrap(accept, "image/*"),
        max_file_size: max_file_size,
      ))
    }
    _ -> None
  }
}

/// Build a `RenderHints` from the JSON Schema node's deprecated `x-`
/// extensions. UiSchema is the primary source for hints; this path only
/// fills `widget` and `upload_config` from `x-widget` / `x-accept` /
/// `x-max-file-size` for backwards compatibility — all other fields stay
/// at their `empty_hints()` defaults and are populated (if at all) by
/// `ui_resolver.resolve_hints`.
///
/// **Deprecated since v0.7.** Scheduled for removal in v0.9.
fn extract_render_hints(data: Dynamic) -> types.RenderHints {
  let widget = extract_widget(data)
  let upload_config = extract_upload_config(data, widget)
  types.RenderHints(
    ..types.empty_hints(),
    widget: widget,
    upload_config: upload_config,
  )
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
      "date" -> decode.success(DateFormat)
      "time" -> decode.success(TimeFormat)
      "password" -> decode.success(PasswordFormat)
      // "date-time" is deliberately NOT wired: RFC 3339 requires a UTC
      // offset, <input type="datetime-local"> forbids one, and a browser
      // given a non-conforming value renders blank rather than erroring.
      // See openspec design.md D2 before "completing the set" here.
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
