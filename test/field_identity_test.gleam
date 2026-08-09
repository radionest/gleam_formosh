// Asserts the per-field DOM identity attributes on the part="field" wrapper.
// Without these, a stylesheet cannot target one specific field, which is the
// prerequisite for any CSS-driven layout.

import formosh/fields/field_common
import formosh/fields/field_dispatcher
import formosh/form/model
import formosh/form/path.{ArraySegment, PropertySegment}
import formosh/schema/types
import formosh/validation/error.{ValidationError}
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import lustre/element

fn string_property() -> types.SchemaProperty {
  types.SchemaProperty(
    ..types.empty_property(),
    field_type: Some(types.StringType),
  )
}

fn schema_with(props: List(#(String, types.SchemaProperty))) -> types.JsonSchema {
  types.JsonSchema(
    title: None,
    description: None,
    field_type: types.ObjectType,
    properties: props,
    required: [],
    defs: None,
    conditionals: [],
    all_of: None,
    string_constraints: None,
    number_constraints: None,
  )
}

fn render_at(
  field_path: path.FieldPath,
  property: types.SchemaProperty,
) -> String {
  let m = model.init(schema_with([#("email", string_property())]))
  let ctx =
    field_common.make_field_ctx(
      model: m,
      path: field_path,
      property: property,
      is_required: False,
      is_disabled: False,
      is_readonly: False,
    )
  field_dispatcher.render_field_at_path(ctx, m) |> element.to_string
}

pub fn field_wrapper_carries_data_name_test() {
  let html = render_at([PropertySegment("email")], string_property())
  html |> string.contains("data-name=\"email\"") |> should.be_true
}

pub fn field_wrapper_carries_data_path_test() {
  let html = render_at([PropertySegment("email")], string_property())
  html |> string.contains("data-path=\"email\"") |> should.be_true
}

pub fn nested_array_field_path_is_canonical_test() {
  let html =
    render_at(
      [PropertySegment("zones"), ArraySegment(0), PropertySegment("affected")],
      string_property(),
    )
  html |> string.contains("data-name=\"affected\"") |> should.be_true
  html |> string.contains("data-path=\"zones.[0].affected\"") |> should.be_true
}

pub fn sibling_rows_are_distinguishable_test() {
  let row0 =
    render_at(
      [PropertySegment("zones"), ArraySegment(0), PropertySegment("label")],
      string_property(),
    )
  let row1 =
    render_at(
      [PropertySegment("zones"), ArraySegment(1), PropertySegment("label")],
      string_property(),
    )
  row0 |> string.contains("data-path=\"zones.[0].label\"") |> should.be_true
  row1 |> string.contains("data-path=\"zones.[1].label\"") |> should.be_true
}

pub fn hidden_field_emits_no_identity_test() {
  let hidden =
    types.SchemaProperty(
      ..string_property(),
      render_hints: types.RenderHints(
        ..types.empty_hints(),
        widget: Some(types.HiddenWidget),
      ),
    )
  let html = render_at([PropertySegment("secret")], hidden)
  html |> string.contains("data-name=") |> should.be_false
}

/// Task 1's spec scenario: a field with a validation error carries
/// `data-error="true"` AND `data-name` AND `data-path` on the SAME wrapper —
/// not merely all three strings appearing somewhere in the document. The
/// wrapper is the outermost (and, for a plain scalar field, only) element
/// `render_field_at_path` returns, so the first `>` in the output closes
/// its own opening tag; slicing there isolates exactly its attribute run.
pub fn field_wrapper_error_name_path_cooccur_test() {
  let field_path = [PropertySegment("email")]
  let m =
    model.init(schema_with([#("email", string_property())]))
    |> model.add_error_at_path(
      field_path,
      ValidationError(field: field_path, message: "bad", rule: "custom"),
    )
    |> model.mark_field_touched(field_path)
  let ctx =
    field_common.make_field_ctx(
      model: m,
      path: field_path,
      property: string_property(),
      is_required: False,
      is_disabled: False,
      is_readonly: False,
    )
  let html = field_dispatcher.render_field_at_path(ctx, m) |> element.to_string

  let assert Ok(#(opening_tag, _)) = string.split_once(html, ">")
  opening_tag |> string.contains("data-error=\"true\"") |> should.be_true
  opening_tag |> string.contains("data-name=\"email\"") |> should.be_true
  opening_tag |> string.contains("data-path=\"email\"") |> should.be_true
}
