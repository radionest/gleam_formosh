import formosh/form/path.{ArraySegment, PropertySegment}
import formosh/schema/properties
import formosh/schema/types.{
  type SchemaProperty, SchemaProperty, UploadConfig, empty_hints, empty_property,
}
import formosh/schema/ui_parser
import formosh/schema/ui_resolver
import formosh/schema/ui_schema.{empty_ui_property, empty_ui_schema}
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

// ---- ui_parser ----

pub fn parse_empty_string_returns_empty_test() {
  let assert Ok(ui) = ui_parser.parse("")
  ui |> should.equal(empty_ui_schema())
}

pub fn parse_simple_widget_test() {
  let json = "{\"name\":{\"ui:widget\":\"textarea\"}}"
  let assert Ok(ui) = ui_parser.parse(json)
  let assert Ok(prop) = list.key_find(ui.properties, "name")
  prop.widget |> should.equal(Some(types.CustomWidget("textarea")))
}

pub fn parse_hidden_widget_test() {
  let json = "{\"id\":{\"ui:widget\":\"hidden\"}}"
  let assert Ok(ui) = ui_parser.parse(json)
  let assert Ok(prop) = list.key_find(ui.properties, "id")
  prop.widget |> should.equal(Some(types.HiddenWidget))
}

pub fn parse_image_upload_widget_test() {
  let json = "{\"photo\":{\"ui:widget\":\"image-upload\"}}"
  let assert Ok(ui) = ui_parser.parse(json)
  let assert Ok(prop) = list.key_find(ui.properties, "photo")
  prop.widget |> should.equal(Some(types.ImageUploadWidget))
}

pub fn parse_nested_children_test() {
  let json =
    "{\"user\":{\"ui:title\":\"User\",\"name\":{\"ui:widget\":\"textarea\"}}}"
  let assert Ok(ui) = ui_parser.parse(json)
  let assert Ok(user) = list.key_find(ui.properties, "user")
  user.title |> should.equal(Some("User"))
  let assert Ok(name) = list.key_find(user.properties, "name")
  name.widget |> should.equal(Some(types.CustomWidget("textarea")))
}

pub fn parse_items_template_test() {
  let json = "{\"items\":{\"items\":{\"side\":{\"ui:widget\":\"select\"}}}}"
  let assert Ok(ui) = ui_parser.parse(json)
  let assert Ok(arr) = list.key_find(ui.properties, "items")
  let assert Some(item_template) = arr.items
  let assert Ok(side) = list.key_find(item_template.properties, "side")
  side.widget |> should.equal(Some(types.CustomWidget("select")))
}

pub fn parse_ui_order_test() {
  let json = "{\"ui:order\":[\"email\",\"name\"]}"
  let assert Ok(ui) = ui_parser.parse(json)
  ui.order |> should.equal(Some(["email", "name"]))
}

pub fn parse_ui_options_test() {
  let json = "{\"field\":{\"ui:options\":{\"rows\":5,\"hint\":\"abc\"}}}"
  let assert Ok(ui) = ui_parser.parse(json)
  let assert Ok(prop) = list.key_find(ui.properties, "field")
  dict.get(prop.options, "rows") |> should.equal(Ok(types.IntegerValue(5)))
  dict.get(prop.options, "hint")
  |> should.equal(Ok(types.StringValue("abc")))
}

pub fn parse_text_overrides_test() {
  let json =
    "{\"field\":{\"ui:placeholder\":\"Type here\",\"ui:help\":\"H\",\"ui:title\":\"T\",\"ui:description\":\"D\"}}"
  let assert Ok(ui) = ui_parser.parse(json)
  let assert Ok(prop) = list.key_find(ui.properties, "field")
  prop.placeholder |> should.equal(Some("Type here"))
  prop.help |> should.equal(Some("H"))
  prop.title |> should.equal(Some("T"))
  prop.description |> should.equal(Some("D"))
}

pub fn parse_bool_flags_test() {
  let json =
    "{\"field\":{\"ui:autofocus\":true,\"ui:disabled\":false,\"ui:readonly\":true}}"
  let assert Ok(ui) = ui_parser.parse(json)
  let assert Ok(prop) = list.key_find(ui.properties, "field")
  prop.autofocus |> should.equal(Some(True))
  prop.disabled |> should.equal(Some(False))
  prop.readonly |> should.equal(Some(True))
}

pub fn parse_addable_removable_test() {
  let json = "{\"items\":{\"ui:addable\":false,\"ui:removable\":false}}"
  let assert Ok(ui) = ui_parser.parse(json)
  let assert Ok(prop) = list.key_find(ui.properties, "items")
  prop.addable |> should.equal(Some(False))
  prop.removable |> should.equal(Some(False))
}

pub fn parse_upload_options_test() {
  let json =
    "{\"photo\":{\"ui:widget\":\"image-upload\",\"ui:accept\":\"image/png\",\"ui:maxFileSize\":4096}}"
  let assert Ok(ui) = ui_parser.parse(json)
  let assert Ok(prop) = list.key_find(ui.properties, "photo")
  let assert Some(upload) = prop.upload
  upload.accept |> should.equal("image/png")
  upload.max_file_size |> should.equal(Some(4096))
}

pub fn parse_unknown_widget_falls_back_to_custom_test() {
  let json = "{\"x\":{\"ui:widget\":\"slider\"}}"
  let assert Ok(ui) = ui_parser.parse(json)
  let assert Ok(prop) = list.key_find(ui.properties, "x")
  prop.widget |> should.equal(Some(types.CustomWidget("slider")))
}

pub fn parse_invalid_json_is_error_test() {
  let result = ui_parser.parse("not json")
  result |> should.be_error
}

// ---- ui_resolver.lookup ----

pub fn lookup_root_returns_empty_test() {
  let ui = empty_ui_schema()
  ui_resolver.lookup(ui, []) |> should.equal(empty_ui_property())
}

pub fn lookup_top_level_property_test() {
  let assert Ok(ui) =
    ui_parser.parse("{\"name\":{\"ui:placeholder\":\"Enter\"}}")
  let prop = ui_resolver.lookup(ui, [PropertySegment("name")])
  prop.placeholder |> should.equal(Some("Enter"))
}

pub fn lookup_missing_property_returns_empty_test() {
  let ui = empty_ui_schema()
  ui_resolver.lookup(ui, [PropertySegment("missing")])
  |> should.equal(empty_ui_property())
}

pub fn lookup_nested_property_test() {
  let assert Ok(ui) =
    ui_parser.parse("{\"user\":{\"address\":{\"ui:title\":\"Address\"}}}")
  let prop =
    ui_resolver.lookup(ui, [
      PropertySegment("user"),
      PropertySegment("address"),
    ])
  prop.title |> should.equal(Some("Address"))
}

pub fn lookup_array_segment_descends_into_items_test() {
  let assert Ok(ui) =
    ui_parser.parse(
      "{\"lesions\":{\"items\":{\"side\":{\"ui:widget\":\"select\"}}}}",
    )
  let prop =
    ui_resolver.lookup(ui, [
      PropertySegment("lesions"),
      ArraySegment(0),
      PropertySegment("side"),
    ])
  prop.widget |> should.equal(Some(types.CustomWidget("select")))
}

pub fn lookup_array_index_is_ignored_test() {
  let assert Ok(ui) =
    ui_parser.parse(
      "{\"lesions\":{\"items\":{\"side\":{\"ui:widget\":\"hidden\"}}}}",
    )
  // Different indices return identical hints — items is a template
  let prop_0 =
    ui_resolver.lookup(ui, [
      PropertySegment("lesions"),
      ArraySegment(0),
      PropertySegment("side"),
    ])
  let prop_5 =
    ui_resolver.lookup(ui, [
      PropertySegment("lesions"),
      ArraySegment(5),
      PropertySegment("side"),
    ])
  prop_0 |> should.equal(prop_5)
}

pub fn lookup_deeply_nested_with_array_in_array_test() {
  let assert Ok(ui) =
    ui_parser.parse(
      "{\"outer\":{\"items\":{\"inner\":{\"items\":{\"deep\":{\"ui:widget\":\"hidden\"}}}}}}",
    )
  let prop =
    ui_resolver.lookup(ui, [
      PropertySegment("outer"),
      ArraySegment(0),
      PropertySegment("inner"),
      ArraySegment(2),
      PropertySegment("deep"),
    ])
  prop.widget |> should.equal(Some(types.HiddenWidget))
}

// ---- ui_resolver.resolve_hints ----

fn schema_prop_with_widget(widget: types.Widget) -> SchemaProperty {
  SchemaProperty(
    ..empty_property(),
    render_hints: types.RenderHints(..empty_hints(), widget: Some(widget)),
  )
}

pub fn resolve_hints_ui_schema_wins_over_x_widget_test() {
  let assert Ok(ui) = ui_parser.parse("{\"f\":{\"ui:widget\":\"textarea\"}}")
  let prop = schema_prop_with_widget(types.HiddenWidget)
  let hints = ui_resolver.resolve_hints(ui, [PropertySegment("f")], prop)
  // UiSchema's CustomWidget("textarea") wins over x-widget HiddenWidget
  hints.widget |> should.equal(Some(types.CustomWidget("textarea")))
}

pub fn resolve_hints_falls_back_to_x_widget_test() {
  // No UiSchema entry for `f`
  let ui = empty_ui_schema()
  let prop = schema_prop_with_widget(types.HiddenWidget)
  let hints = ui_resolver.resolve_hints(ui, [PropertySegment("f")], prop)
  hints.widget |> should.equal(Some(types.HiddenWidget))
}

pub fn resolve_hints_carries_placeholder_test() {
  let assert Ok(ui) = ui_parser.parse("{\"f\":{\"ui:placeholder\":\"Hello\"}}")
  let hints =
    ui_resolver.resolve_hints(ui, [PropertySegment("f")], empty_property())
  hints.placeholder |> should.equal(Some("Hello"))
}

pub fn resolve_hints_upload_from_ui_schema_test() {
  let assert Ok(ui) =
    ui_parser.parse(
      "{\"photo\":{\"ui:widget\":\"image-upload\",\"ui:accept\":\"image/jpeg\"}}",
    )
  let hints =
    ui_resolver.resolve_hints(ui, [PropertySegment("photo")], empty_property())
  let assert Some(upload) = hints.upload_config
  upload.accept |> should.equal("image/jpeg")
}

pub fn resolve_hints_upload_falls_back_to_x_extension_test() {
  // No UiSchema upload — falls back to property.render_hints.upload_config
  let ui = empty_ui_schema()
  let prop =
    SchemaProperty(
      ..empty_property(),
      render_hints: types.RenderHints(
        ..empty_hints(),
        upload_config: Some(UploadConfig(
          accept: "image/png",
          max_file_size: None,
        )),
      ),
    )
  let hints = ui_resolver.resolve_hints(ui, [PropertySegment("photo")], prop)
  let assert Some(upload) = hints.upload_config
  upload.accept |> should.equal("image/png")
}

// ---- properties.apply_order ----

pub fn apply_order_none_keeps_order_test() {
  let entries = [#("a", 1), #("b", 2), #("c", 3)]
  properties.apply_order(entries, None) |> should.equal(entries)
}

pub fn apply_order_listed_first_rest_after_test() {
  let entries = [#("name", 1), #("email", 2), #("age", 3), #("role", 4)]
  let result = properties.apply_order(entries, Some(["email", "name"]))
  let keys = list.map(result, fn(entry) { entry.0 })
  keys |> should.equal(["email", "name", "age", "role"])
}

pub fn apply_order_unknown_keys_dropped_test() {
  let entries = [#("a", 1), #("b", 2)]
  let result = properties.apply_order(entries, Some(["b", "missing", "a"]))
  let keys = list.map(result, fn(entry) { entry.0 })
  keys |> should.equal(["b", "a"])
}

pub fn apply_order_all_listed_exact_order_test() {
  let entries = [#("a", 1), #("b", 2), #("c", 3)]
  let result = properties.apply_order(entries, Some(["c", "a", "b"]))
  let keys = list.map(result, fn(entry) { entry.0 })
  keys |> should.equal(["c", "a", "b"])
}
