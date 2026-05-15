/// Integration test: the hidden_fields_test.json example schema parses and
/// exposes the expected hidden + visible field mix. Guards against the
/// example drifting out of sync with the parser.
import formosh/schema/parser
import formosh/schema/types.{type SchemaProperty, IntegerValue, StringValue}
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
    simplifile.read(
      "examples/file_schema_loader/schemas/hidden_fields_test.json",
    )

  let parse_result = parser.parse_schema(schema_json)
  parse_result |> should.be_ok()

  let assert Ok(schema) = parse_result

  // Hidden scalar with default
  let tenant = find_prop(schema.properties, "tenant_id")
  should.equal(tenant.render_hints.widget, Some(types.HiddenWidget))
  should.equal(tenant.default, Some(StringValue("acme-corp")))

  // Hidden integer with default
  let version = find_prop(schema.properties, "form_version")
  should.equal(version.render_hints.widget, Some(types.HiddenWidget))
  should.equal(version.default, Some(IntegerValue(3)))

  // Hidden without default
  let source = find_prop(schema.properties, "source")
  should.equal(source.render_hints.widget, Some(types.HiddenWidget))
  should.equal(source.default, option.None)

  // Visible field — widget unset
  let email = find_prop(schema.properties, "email")
  should.equal(email.render_hints.widget, option.None)

  // Hidden nested inside object
  let prefs = find_prop(schema.properties, "preferences")
  let assert Some(sub) = prefs.properties
  let segment = find_prop(sub, "_internal_segment")
  should.equal(segment.render_hints.widget, Some(types.HiddenWidget))

  // Hidden array with default
  let tags = find_prop(schema.properties, "tags")
  should.equal(tags.render_hints.widget, Some(types.HiddenWidget))

  // tenant_id and email are in required
  list.contains(schema.required, "tenant_id") |> should.be_true()
  list.contains(schema.required, "email") |> should.be_true()
}
