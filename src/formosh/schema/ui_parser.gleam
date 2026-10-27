/// UiSchema parser — JSON string → `UiSchema` tree.
///
/// Accepts react-jsonschema-form-style JSON: `ui:*` keys carry settings for
/// the current node, `items` is a reserved key for the array-element
/// template, `$`-prefixed keys are ignored, every other key is a child
/// property name. A child that is not a JSON object is skipped rather than
/// failing the whole document (`parse_with_warning` names the skips).
/// Errors surface as `types.ParseError` (the same type used
/// by the JSON Schema parser) so callers can handle both kinds of input
/// uniformly.
import formosh/ffi/dynamic_object
import formosh/schema/parser
import formosh/schema/types.{
  type ParseError, type UploadConfig, type Value, type Widget, CustomWidget,
  DecodingError, HiddenWidget, ImageUploadWidget, InvalidJson, SwipeReviewWidget,
  UnexpectedValue, UploadConfig,
}
import formosh/schema/ui_schema.{
  type LayoutNode, type UiProperty, type UiSchema, GroupNode, LeafNode, RowNode,
  UiProperty, UiSchema, empty_ui_schema,
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
///
/// A child that is not a JSON object is skipped (its key ignored) instead of
/// failing the whole document (#144); use `parse_with_warning` to hear about
/// the skips.
pub fn parse(json_string: String) -> Result(UiSchema, ParseError) {
  parse_with_warning(json_string).0
}

/// `parse` plus a diagnostic naming every child skipped for not being a
/// JSON object (`None` for a clean document). `parse` stays pure and
/// silent; the web component's `ui-schema` attribute emits the warning via
/// `console.warn` — mirroring `parser.parse_schema_with_warning`.
pub fn parse_with_warning(
  json_string: String,
) -> #(Result(UiSchema, ParseError), Option(String)) {
  case string.trim(json_string) {
    "" | "null" -> #(Ok(empty_ui_schema()), None)
    _ ->
      case json.parse(json_string, decode.dynamic) {
        Error(err) -> #(Error(json_error_to_parse_error(err)), None)
        Ok(dyn) -> {
          let #(result, skipped) = parse_ui_schema(dyn)
          #(result, skipped_warning(skipped))
        }
      }
  }
}

fn skipped_warning(skipped: List(String)) -> Option(String) {
  case skipped {
    [] -> None
    _ ->
      Some(
        "formosh: ui-schema: skipped children that are not JSON objects "
        <> "(keys ignored; every child, `items` included, must be an object): "
        <> string.join(skipped, ", "),
      )
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

fn parse_ui_schema(
  dyn: Dynamic,
) -> #(Result(UiSchema, ParseError), List(String)) {
  case dynamic_object.entries(dyn) {
    Error(_) -> #(
      Error(UnexpectedValue("UiSchema root must be a JSON object")),
      [],
    )
    Ok(entries) -> {
      let order = extract_order(entries)
      // Root has no `items` template (form root is always an object), so
      // every non-`ui:*`, non-`$` key — including a property literally
      // named "items" — is treated as a top-level child.
      case extract_layout(entries), parse_children(entries, as_root: True) {
        Error(err), _ -> #(Error(err), [])
        Ok(_layout), #(Error(err), skipped) -> #(Error(err), skipped)
        Ok(layout), #(Ok(children), skipped) -> #(
          Ok(UiSchema(properties: children, order: order, layout: layout)),
          skipped,
        )
      }
    }
  }
}

fn parse_ui_property(
  dyn: Dynamic,
) -> #(Result(UiProperty, ParseError), List(String)) {
  case dynamic_object.entries(dyn) {
    Error(_) -> #(
      Error(UnexpectedValue("UiProperty must be a JSON object")),
      [],
    )
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
      let orderable = extract_bool(entries, "ui:orderable")
      let upload = extract_upload(entries, widget)
      // Inside a UiProperty, `items` is reserved for the array-element
      // template — any property called "items" in the data schema would
      // collide with that, but the JSON Schema reserves the same name, so
      // it's a non-issue in practice.
      let #(items, items_skipped) = extract_items(entries)
      case
        extract_layout(entries),
        items,
        parse_children(entries, as_root: False)
      {
        Error(err), _, _ -> #(Error(err), [])
        Ok(_layout), Error(err), _ -> #(Error(err), [])
        Ok(_layout), Ok(_items), #(Error(err), skipped) -> #(
          Error(err),
          skipped,
        )
        Ok(layout), Ok(items), #(Ok(children), skipped) -> #(
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
            orderable: orderable,
            upload: upload,
            properties: children,
            items: items,
            layout: layout,
          )),
          list.append(items_skipped, skipped),
        )
      }
    }
  }
}

/// Returns the parsed children plus the names skipped for not being JSON
/// objects. Object children still parse fallibly — a malformed `ui:layout`
/// or `items` inside an otherwise well-formed child remains a hard error.
fn parse_children(
  entries: List(#(String, Dynamic)),
  as_root as_root: Bool,
) -> #(Result(List(#(String, UiProperty)), ParseError), List(String)) {
  let #(objects, non_objects) =
    list.filter(entries, fn(entry) {
      let key = entry.0
      !is_ui_key(key)
      && !string.starts_with(key, "$")
      && { as_root || key != "items" }
    })
    |> list.partition(fn(entry) {
      result.is_ok(dynamic_object.entries(entry.1))
    })
  let skipped = list.map(non_objects, fn(entry) { entry.0 })
  let parsed =
    objects
    |> list.try_map(fn(entry) {
      let #(name, dyn) = entry
      let #(result, nested_skipped) = parse_ui_property(dyn)
      case result {
        Ok(prop) -> Ok(#(name, prop, nested_skipped))
        Error(err) -> Error(err)
      }
    })
  case parsed {
    Error(err) -> #(Error(err), skipped)
    Ok(named) -> #(
      Ok(list.map(named, fn(triple) { #(triple.0, triple.1) })),
      list.append(skipped, list.flat_map(named, fn(triple) { triple.2 })),
    )
  }
}

/// Returns the parsed `items` template plus the names skipped for not being
/// JSON objects (a non-object template reports as `"items"`).
fn extract_items(
  entries: List(#(String, Dynamic)),
) -> #(Result(Option(UiProperty), ParseError), List(String)) {
  case list.key_find(entries, "items") {
    Error(_) -> #(Ok(None), [])
    Ok(dyn) ->
      case dynamic_object.entries(dyn) {
        Error(_) -> #(Ok(None), ["items"])
        Ok(_) -> {
          let #(result, skipped) = parse_ui_property(dyn)
          case result {
            Ok(prop) -> #(Ok(Some(prop)), skipped)
            Error(err) -> #(Error(err), skipped)
          }
        }
      }
  }
}

fn extract_layout(
  entries: List(#(String, Dynamic)),
) -> Result(Option(List(LayoutNode)), ParseError) {
  case list.key_find(entries, "ui:layout") {
    Error(_) -> Ok(None)
    Ok(dyn) -> {
      use nodes <- result.map(parse_layout_elements(dyn, "ui:layout"))
      Some(nodes)
    }
  }
}

fn parse_layout_elements(
  dyn: Dynamic,
  what: String,
) -> Result(List(LayoutNode), ParseError) {
  case decode.run(dyn, decode.list(decode.dynamic)) {
    Error(_) -> Error(UnexpectedValue(what <> " must be a JSON array"))
    Ok(items) -> list.try_map(items, parse_layout_node)
  }
}

fn parse_layout_node(dyn: Dynamic) -> Result(LayoutNode, ParseError) {
  case decode.run(dyn, decode.string) {
    Ok(name) -> parse_layout_leaf(name)
    Error(_) -> parse_layout_container(dyn)
  }
}

fn parse_layout_leaf(name: String) -> Result(LayoutNode, ParseError) {
  case string.contains(name, ".") {
    True ->
      Error(UnexpectedValue(
        "ui:layout leaf \""
        <> name
        <> "\" contains '.', which is reserved for path addressing",
      ))
    False -> Ok(LeafNode(name))
  }
}

fn parse_layout_container(dyn: Dynamic) -> Result(LayoutNode, ParseError) {
  case dynamic_object.entries(dyn) {
    Error(_) ->
      Error(UnexpectedValue(
        "ui:layout element must be a string or a layout node object",
      ))
    Ok(entries) -> {
      use elements <- result.try(case list.key_find(entries, "elements") {
        Error(_) ->
          Error(UnexpectedValue("ui:layout node is missing \"elements\""))
        Ok(elements_dyn) ->
          parse_layout_elements(elements_dyn, "ui:layout \"elements\"")
      })
      case extract_string(entries, "type") {
        Some("Row") -> Ok(RowNode(elements))
        Some("Group") ->
          Ok(GroupNode(extract_string(entries, "label"), elements))
        Some(other) ->
          Error(UnexpectedValue("unknown ui:layout node type: " <> other))
        None -> Error(UnexpectedValue("ui:layout node is missing \"type\""))
      }
    }
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
        "swipe-review" -> SwipeReviewWidget
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
/// Gated on `widget == Some(ImageUploadWidget)`, with `accept` defaulting
/// to `"image/*"` there. Authors who write `ui:maxFileSize: ...`
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
