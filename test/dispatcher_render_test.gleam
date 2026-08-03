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
import gleam/string
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
    all_of: None,
    string_constraints: None,
    number_constraints: None,
  )
}

fn hidden_string_property() -> types.SchemaProperty {
  types.SchemaProperty(
    ..types.empty_property(),
    field_type: Some(types.StringType),
    render_hints: types.RenderHints(
      ..types.empty_hints(),
      widget: Some(types.HiddenWidget),
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

fn string_property_with_format(
  format: types.StringFormat,
) -> types.SchemaProperty {
  types.SchemaProperty(
    ..types.empty_property(),
    field_type: Some(types.StringType),
    string_constraints: Some(types.StringConstraints(
      min_length: None,
      max_length: None,
      pattern: None,
      format: Some(format),
    )),
  )
}

fn string_property_with_widget(
  name: String,
  min_length: option.Option(Int),
) -> types.SchemaProperty {
  types.SchemaProperty(
    ..types.empty_property(),
    field_type: Some(types.StringType),
    string_constraints: Some(types.StringConstraints(
      min_length: min_length,
      max_length: None,
      pattern: None,
      format: None,
    )),
    render_hints: types.RenderHints(
      ..types.empty_hints(),
      widget: Some(types.CustomWidget(name)),
    ),
  )
}

pub fn date_format_renders_date_input_test() {
  render(string_property_with_format(types.DateFormat), False)
  |> string.contains("type=\"date\"")
  |> should.be_true
}

pub fn time_format_renders_time_input_test() {
  render(string_property_with_format(types.TimeFormat), False)
  |> string.contains("type=\"time\"")
  |> should.be_true
}

pub fn date_time_format_renders_text_input_test() {
  render(string_property_with_format(types.CustomFormat("date-time")), False)
  |> string.contains("type=\"text\"")
  |> should.be_true
}

pub fn password_format_renders_password_input_test() {
  render(string_property_with_format(types.PasswordFormat), False)
  |> string.contains("type=\"password\"")
  |> should.be_true
}

// Constraint attributes must survive the widget route too, not just the
// format route — a botched threading of the type override through
// render_input could produce the right `type` while dropping the
// minlength/maxlength/pattern assembly it sits next to.
pub fn password_widget_renders_password_input_test() {
  let html = render(string_property_with_widget("password", Some(8)), False)
  should.be_true(string.contains(html, "type=\"password\""))
  should.be_true(string.contains(html, "minlength=\"8\""))
}

fn string_property_with_max_length(
  format: types.StringFormat,
  max: Int,
) -> types.SchemaProperty {
  types.SchemaProperty(
    ..types.empty_property(),
    field_type: Some(types.StringType),
    string_constraints: Some(types.StringConstraints(
      min_length: None,
      max_length: Some(max),
      pattern: None,
      format: Some(format),
    )),
  )
}

fn password_widget_with_format(
  format: types.StringFormat,
  max_length: option.Option(Int),
) -> types.SchemaProperty {
  types.SchemaProperty(
    ..types.empty_property(),
    field_type: Some(types.StringType),
    string_constraints: Some(types.StringConstraints(
      min_length: None,
      max_length: max_length,
      pattern: None,
      format: Some(format),
    )),
    render_hints: types.RenderHints(
      ..types.empty_hints(),
      widget: Some(types.CustomWidget("password")),
    ),
  )
}

// ui:widget wins over a conflicting format.
pub fn password_widget_beats_date_format_test() {
  render(password_widget_with_format(types.DateFormat, None), False)
  |> string.contains("type=\"password\"")
  |> should.be_true
}

// ui:widget is dispatched before the maxLength > 100 textarea threshold.
pub fn password_widget_beats_textarea_threshold_test() {
  let html =
    render(password_widget_with_format(types.PasswordFormat, Some(128)), False)
  should.be_true(string.contains(html, "type=\"password\""))
  should.be_false(string.contains(html, "<textarea"))
}

// Documented edge: the format-only route runs AFTER the maxLength > 100
// threshold, so a long password declared only via `format` still becomes a
// textarea. Asserted so the behaviour is a decision, not a surprise.
pub fn password_format_alone_still_hits_textarea_threshold_test() {
  render(string_property_with_max_length(types.PasswordFormat, 128), False)
  |> string.contains("<textarea")
  |> should.be_true
}
