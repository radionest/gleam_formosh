/// Integration test: the hidden_fields_test example — a schema plus its
/// `.ui.json` UiSchema — parses and exposes the expected hidden + visible
/// field mix. Guards against the example drifting out of sync with the
/// parsers.
import formosh/form/path
import formosh/schema/parser
import formosh/schema/types.{type SchemaProperty, IntegerValue, StringValue}
import formosh/schema/ui_parser
import formosh/schema/ui_resolver
import gleam/list
import gleam/option.{Some}
import gleeunit/should
import simplifile

fn find_prop(
  properties: List(#(String, SchemaProperty)),
  name: String,
) -> SchemaProperty {
  let assert Ok(prop) = list.key_find(properties, name)
  prop
}

pub fn hidden_fields_example_schema_parses_test() {
  let assert Ok(schema_json) =
    simplifile.read("demo/schemas/hidden_fields_test.json")

  let parse_result = parser.parse_schema(schema_json)
  parse_result |> should.be_ok()

  let assert Ok(schema) = parse_result

  let assert Ok(ui_json) =
    simplifile.read("demo/schemas/hidden_fields_test.ui.json")
  let assert Ok(ui) = ui_parser.parse(ui_json)
  let widget_at = fn(names: List(String)) {
    ui_resolver.lookup(ui, list.map(names, path.PropertySegment)).widget
  }

  // Hidden scalar with default
  let tenant = find_prop(schema.properties, "tenant_id")
  widget_at(["tenant_id"]) |> should.equal(Some(types.HiddenWidget))
  should.equal(tenant.default, Some(StringValue("acme-corp")))

  // Hidden integer with default
  let version = find_prop(schema.properties, "form_version")
  widget_at(["form_version"]) |> should.equal(Some(types.HiddenWidget))
  should.equal(version.default, Some(IntegerValue(3)))

  // Hidden without default
  let source = find_prop(schema.properties, "source")
  widget_at(["source"]) |> should.equal(Some(types.HiddenWidget))
  should.equal(source.default, option.None)

  // Visible field — widget unset
  let _ = find_prop(schema.properties, "email")
  widget_at(["email"]) |> should.equal(option.None)

  // Hidden nested inside object
  let prefs = find_prop(schema.properties, "preferences")
  let assert Some(sub) = prefs.properties
  let _ = find_prop(sub, "_internal_segment")
  widget_at(["preferences", "_internal_segment"])
  |> should.equal(Some(types.HiddenWidget))

  // Hidden array with default
  let _ = find_prop(schema.properties, "tags")
  widget_at(["tags"]) |> should.equal(Some(types.HiddenWidget))

  // tenant_id and email are in required
  list.contains(schema.required, "tenant_id") |> should.be_true()
  list.contains(schema.required, "email") |> should.be_true()
}
