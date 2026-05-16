/// UiSchema parser — JSON string → `UiSchema` tree.
///
/// Accepts react-jsonschema-form-style JSON: `ui:*` keys carry settings for
/// the current node, `items` is a reserved key for the array-element
/// template, every other key is a child property name. Errors surface as
/// `parser.ParseError` (the same type used by the JSON Schema parser) so
/// callers can handle both kinds of input uniformly.
import formosh/ffi/dynamic_object
import formosh/schema/parser.{
  type ParseError, DecodingError, InvalidJson, UnexpectedValue,
}
import formosh/schema/types.{
  type UploadConfig, type Value, type Widget, CustomWidget, HiddenWidget,
  ImageUploadWidget, UploadConfig,
}
import formosh/schema/ui_schema.{
  type UiProperty, type UiSchema, UiProperty, UiSchema, empty_ui_schema,
}
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// Parse a JSON string into a `UiSchema` tree.
///
/// An empty string or `null` JSON value parses to `empty_ui_schema()` — so
/// callers can pass through whatever the user supplied without guarding.
pub fn parse(json_string: String) -> Result(UiSchema, ParseError) {
  case string.trim(json_string) {
    "" | "null" -> Ok(empty_ui_schema())
    _ -> {
      use dyn <- result.try(
        json.parse(json_string, decode.dynamic)
        |> result.map_error(json_error_to_parse_error),
      )
      parse_ui_schema(dyn)
    }
  }
}

fn json_error_to_parse_error(err: json.DecodeError) -> ParseError {
  case err {
    json.UnableToDecode(errors) -> DecodingError(errors)
    json.UnexpectedEndOfInput -> InvalidJson("Unexpected end of input")
    json.UnexpectedByte(byte) -> InvalidJson("Unexpected byte: " <> byte)
    json.UnexpectedSequence(seq) -> InvalidJson("Unexpected sequence: " <> seq)
  }
}

fn parse_ui_schema(dyn: Dynamic) -> Result(UiSchema, ParseError) {
  case dynamic_object.entries(dyn) {
    Error(_) -> Error(UnexpectedValue("UiSchema root must be a JSON object"))
    Ok(entries) -> {
      let order = extract_order(entries)
      // Root has no `items` template (form root is always an object), so
      // every non-`ui:*` key — including a property literally named
      // "items" — is treated as a top-level child.
      use children <- result.try(parse_children(entries, as_root: True))
      Ok(UiSchema(properties: children, order: order))
    }
  }
}

fn parse_ui_property(dyn: Dynamic) -> Result(UiProperty, ParseError) {
  case dynamic_object.entries(dyn) {
    Error(_) -> Error(UnexpectedValue("UiProperty must be a JSON object"))
    Ok(entries) -> {
      let widget = extract_widget(entries)
      let options = extract_options(entries)
      let order = extract_order(entries)
      let placeholder = extract_string(entries, "ui:placeholder")
      let help = extract_string(entries, "ui:help")
      let autofocus = extract_bool(entries, "ui:autofocus")
      let disabled = extract_bool(entries, "ui:disabled")
      let readonly = extract_bool(entries, "ui:readonly")
      let title = extract_string(entries, "ui:title")
      let description = extract_string(entries, "ui:description")
      let addable = extract_bool(entries, "ui:addable")
      let removable = extract_bool(entries, "ui:removable")
      let upload = extract_upload(entries, widget)
      use items <- result.try(extract_items(entries))
      // Inside a UiProperty, `items` is reserved for the array-element
      // template — any property called "items" in the data schema would
      // collide with that, but the JSON Schema reserves the same name, so
      // it's a non-issue in practice.
      use children <- result.try(parse_children(entries, as_root: False))
      Ok(UiProperty(
        widget: widget,
        options: options,
        order: order,
        placeholder: placeholder,
        help: help,
        autofocus: autofocus,
        disabled: disabled,
        readonly: readonly,
        title: title,
        description: description,
        addable: addable,
        removable: removable,
        upload: upload,
        properties: children,
        items: items,
      ))
    }
  }
}

fn parse_children(
  entries: List(#(String, Dynamic)),
  as_root as_root: Bool,
) -> Result(List(#(String, UiProperty)), ParseError) {
  list.filter(entries, fn(entry) {
    let key = entry.0
    !is_ui_key(key) && { as_root || key != "items" }
  })
  |> list.try_map(fn(entry) {
    let #(name, dyn) = entry
    use prop <- result.map(parse_ui_property(dyn))
    #(name, prop)
  })
}

fn extract_items(
  entries: List(#(String, Dynamic)),
) -> Result(Option(UiProperty), ParseError) {
  case list.key_find(entries, "items") {
    Ok(dyn) -> {
      use prop <- result.map(parse_ui_property(dyn))
      Some(prop)
    }
    Error(_) -> Ok(None)
  }
}

fn extract_string(
  entries: List(#(String, Dynamic)),
  key: String,
) -> Option(String) {
  case list.key_find(entries, key) {
    Ok(dyn) ->
      decode.run(dyn, decode.string)
      |> option.from_result()
    Error(_) -> None
  }
}

fn extract_bool(entries: List(#(String, Dynamic)), key: String) -> Option(Bool) {
  case list.key_find(entries, key) {
    Ok(dyn) ->
      decode.run(dyn, decode.bool)
      |> option.from_result()
    Error(_) -> None
  }
}

fn extract_order(entries: List(#(String, Dynamic))) -> Option(List(String)) {
  case list.key_find(entries, "ui:order") {
    Ok(dyn) ->
      decode.run(dyn, decode.list(decode.string))
      |> option.from_result()
    Error(_) -> None
  }
}

fn extract_widget(entries: List(#(String, Dynamic))) -> Option(Widget) {
  case extract_string(entries, "ui:widget") {
    Some(raw) ->
      Some(case raw {
        "image-upload" -> ImageUploadWidget
        "hidden" -> HiddenWidget
        _ -> CustomWidget(raw)
      })
    None -> None
  }
}

fn extract_options(entries: List(#(String, Dynamic))) -> Dict(String, Value) {
  case list.key_find(entries, "ui:options") {
    Ok(dyn) ->
      case dynamic_object.entries(dyn) {
        Ok(option_entries) -> decode_options(option_entries)
        Error(_) -> dict.new()
      }
    Error(_) -> dict.new()
  }
}

fn decode_options(entries: List(#(String, Dynamic))) -> Dict(String, Value) {
  list.fold(entries, dict.new(), fn(acc, entry) {
    let #(key, dyn) = entry
    case decode.run(dyn, parser.value_decoder()) {
      Ok(value) -> dict.insert(acc, key, value)
      Error(_) -> acc
    }
  })
}

/// Extract `UploadConfig` from `ui:accept` / `ui:maxFileSize` entries.
///
/// Gated on `widget == Some(ImageUploadWidget)` — mirrors
/// `parser.extract_upload_config`. Authors who write `ui:maxFileSize: ...`
/// without `ui:widget: "image-upload"` get `None` (no silent
/// `accept: "image/*"` fallback). If you genuinely need a non-image
/// upload, set the widget explicitly and override `ui:accept`.
fn extract_upload(
  entries: List(#(String, Dynamic)),
  widget: Option(Widget),
) -> Option(UploadConfig) {
  case widget {
    Some(ImageUploadWidget) -> {
      let accept = extract_string(entries, "ui:accept")
      let max_file_size = case list.key_find(entries, "ui:maxFileSize") {
        Ok(dyn) ->
          decode.run(dyn, decode.int)
          |> option.from_result()
        Error(_) -> None
      }
      Some(UploadConfig(
        accept: option.unwrap(accept, "image/*"),
        max_file_size: max_file_size,
      ))
    }
    _ -> None
  }
}

fn is_ui_key(key: String) -> Bool {
  string.starts_with(key, "ui:")
}
