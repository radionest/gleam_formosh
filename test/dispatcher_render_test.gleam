// Render-level tests for field_dispatcher visibility suppression.
//
// Closes the previous gap: parser/validator tests proved x-widget: "hidden"
// is parsed and validated, but no test asserted that the dispatcher actually
// drops the element from the DOM. Without that, the suppression guard could
// regress (e.g. moved into render_widget where wrap_with_errors would still
// emit an empty <div>) and pass all other suites.

import formosh/fields/field_common
import formosh/fields/field_dispatcher
import formosh/form/model.{FormModel}
import formosh/form/path
import formosh/schema/types
import gleam/option.{None, Some}
import gleeunit/should
import lustre/element

fn empty_schema() -> types.JsonSchema {
  types.JsonSchema(
    title: None,
    description: None,
    field_type: types.ObjectType,
    properties: [],
    required: [],
    defs: None,
    conditionals: [],
    string_constraints: None,
    number_constraints: None,
  )
}

fn hidden_string_property() -> types.SchemaProperty {
  types.SchemaProperty(
    ..types.empty_property(),
    field_type: Some(types.StringType),
    render_hints: types.RenderHints(
      widget: Some(types.HiddenWidget),
      upload_config: None,
    ),
  )
}

fn visible_string_property() -> types.SchemaProperty {
  types.SchemaProperty(
    ..types.empty_property(),
    field_type: Some(types.StringType),
  )
}

fn render(property: types.SchemaProperty, is_readonly: Bool) -> String {
  let field_path = path.from_field_name("name")
  let m = model.init(empty_schema())
  let ctx =
    field_common.make_field_ctx(
      model: m,
      path: field_path,
      property: property,
      is_required: False,
      is_disabled: False,
      is_readonly: is_readonly,
    )
  field_dispatcher.render_field_at_path(ctx, m)
  |> element.to_string
}

// The whole point of x-widget: "hidden" — the wrapper div must NOT appear.
// If it did, layout/spacing tests downstream would silently fail and the
// "<input type=hidden>"-like contract would be broken.
pub fn hidden_widget_renders_to_empty_string_test() {
  render(hidden_string_property(), False) |> should.equal("")
}

// `show_readonly_fields: False` (the default) is irrelevant for hidden —
// hidden suppression is unconditional, not piggybacked on the readonly flag.
pub fn hidden_widget_suppressed_even_when_readonly_flag_set_test() {
  render(hidden_string_property(), True) |> should.equal("")
}

// Regression smoke: visible fields still render with the formosh-field
// wrapper. Catches "guard always returns element.none()" type regressions.
pub fn visible_widget_renders_wrapper_test() {
  let html = render(visible_string_property(), False)
  case html {
    "" -> should.fail()
    _ -> Nil
  }
}

// readOnly + show_readonly_fields=False (init default) — orthogonal suppression
// path, kept here so a future change to readonly handling can't accidentally
// merge the two cases.
pub fn readonly_suppressed_renders_to_empty_string_test() {
  render(visible_string_property(), True) |> should.equal("")
}

// Same property with show_readonly_fields=True — readonly is rendered as a
// disabled input wrapped by formosh-field.
pub fn readonly_visible_renders_wrapper_when_show_flag_enabled_test() {
  let base = FormModel(..model.init(empty_schema()), show_readonly_fields: True)
  let field_path = path.from_field_name("name")
  let ctx =
    field_common.make_field_ctx(
      model: base,
      path: field_path,
      property: visible_string_property(),
      is_required: False,
      is_disabled: False,
      is_readonly: True,
    )
  let html =
    field_dispatcher.render_field_at_path(ctx, base) |> element.to_string
  case html {
    "" -> should.fail()
    _ -> Nil
  }
}
