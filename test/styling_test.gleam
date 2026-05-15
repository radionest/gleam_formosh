// Smoke tests for the Shadow DOM styling surface introduced by the
// `::part()` / `data-*` refactor. Covers behavioural state attributes that
// would silently regress to plain HTML otherwise.

import formosh/fields/boolean_field
import formosh/fields/field_dispatcher
import formosh/form/model.{FormModel}
import formosh/form/path
import formosh/schema/types
import formosh/validation/error
import gleam/dict
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
    string_constraints: None,
    number_constraints: None,
  )
}

fn string_property() -> types.SchemaProperty {
  types.SchemaProperty(
    ..types.empty_property(),
    field_type: Some(types.StringType),
  )
}

fn render_with_state(
  is_touched: Bool,
  errors: List(error.ValidationError),
  is_readonly: Bool,
) -> String {
  let field_path = path.from_field_name("name")
  // `show_readonly_fields: True` is required so the dispatcher actually
  // renders the wrapper for readonly fields rather than returning
  // `element.none()`.
  let base = FormModel(..model.init(empty_schema()), show_readonly_fields: True)
  let model_with_touched = case is_touched {
    True -> model.mark_field_touched(base, field_path)
    False -> base
  }
  let model_with_errors = case errors {
    [] -> model_with_touched
    _ ->
      FormModel(
        ..model_with_touched,
        errors: dict.from_list([#(path.to_string(field_path), errors)]),
      )
  }

  field_dispatcher.render_field_at_path(
    field_path,
    string_property(),
    model_with_errors,
    False,
    False,
    is_readonly,
  )
  |> element.to_string
}

pub fn field_wrapper_no_state_attrs_when_clean_test() {
  let html = render_with_state(False, [], False)
  html |> string.contains("part=\"field\"") |> should.be_true
  html |> string.contains("data-error") |> should.be_false
  html |> string.contains("data-readonly") |> should.be_false
}

pub fn field_wrapper_has_data_error_when_touched_and_invalid_test() {
  let err =
    error.ValidationError(
      field: path.from_field_name("name"),
      message: "required",
      rule: "required",
    )
  let html = render_with_state(True, [err], False)
  html |> string.contains("part=\"field\"") |> should.be_true
  html |> string.contains("data-error=\"true\"") |> should.be_true
}

pub fn field_wrapper_hides_data_error_when_untouched_test() {
  let err =
    error.ValidationError(
      field: path.from_field_name("name"),
      message: "required",
      rule: "required",
    )
  let html = render_with_state(False, [err], False)
  html |> string.contains("data-error") |> should.be_false
}

pub fn field_wrapper_has_data_readonly_when_readonly_test() {
  let html = render_with_state(False, [], True)
  html |> string.contains("data-readonly=\"true\"") |> should.be_true
}

pub fn toggle_on_has_data_state_on_test() {
  let html =
    boolean_field.render_as_toggle(
      path.from_field_name("active"),
      types.empty_property(),
      Some(types.BooleanValue(True)),
      False,
      False,
    )
    |> element.to_string

  html |> string.contains("part=\"toggle\"") |> should.be_true
  html |> string.contains("data-state=\"on\"") |> should.be_true
  html |> string.contains("aria-checked=\"true\"") |> should.be_true
}

pub fn toggle_off_has_data_state_off_test() {
  let html =
    boolean_field.render_as_toggle(
      path.from_field_name("active"),
      types.empty_property(),
      Some(types.BooleanValue(False)),
      False,
      False,
    )
    |> element.to_string

  html |> string.contains("data-state=\"off\"") |> should.be_true
  html |> string.contains("aria-checked=\"false\"") |> should.be_true
}
