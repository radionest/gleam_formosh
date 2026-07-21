// Nullable-field semantics.
//
// Spec: openspec/changes/add-anyof-union-support/specs/nullable-fields/spec.md
//   - "Empty nullable fields validate as satisfied"
//   - "Nullable fields render without the required marker"

import formosh/fields/field_common
import formosh/form/model
import formosh/form/path.{PropertySegment}
import formosh/schema/types.{
  type SchemaProperty, IntegerType, IntegerValue, NullValue, NumberConstraints,
  SchemaProperty, empty_number_constraints, empty_property,
}
import formosh/schema/validator
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import lustre/element

fn age_path() -> path.FieldPath {
  path.from_field_name("age")
}

fn nullable_integer_property() -> SchemaProperty {
  SchemaProperty(
    ..empty_property(),
    field_type: Some(IntegerType),
    nullable: True,
  )
}

fn nullable_integer_with_minimum(min: Float) -> SchemaProperty {
  SchemaProperty(
    ..nullable_integer_property(),
    number_constraints: Some(
      NumberConstraints(..empty_number_constraints(), minimum: Some(min)),
    ),
  )
}

// --- validate_field: empty nullable fields validate as satisfied ---

pub fn nullable_required_empty_none_has_no_errors_test() {
  let property = nullable_integer_property()
  validator.validate_field(
    age_path(),
    None,
    property,
    True,
    property.render_hints.widget,
  )
  |> should.equal([])
}

pub fn nullable_required_empty_null_value_has_no_errors_test() {
  let property = nullable_integer_property()
  validator.validate_field(
    age_path(),
    Some(NullValue),
    property,
    True,
    property.render_hints.widget,
  )
  |> should.equal([])
}

pub fn nullable_minimum_empty_reports_no_minimum_error_test() {
  let property = nullable_integer_with_minimum(0.0)
  validator.validate_field(
    age_path(),
    None,
    property,
    True,
    property.render_hints.widget,
  )
  |> should.equal([])
}

// Filled nullable field validates its value exactly like a non-nullable
// field would — the empty-nullable guard must not swallow real values.
pub fn nullable_minimum_filled_negative_reports_minimum_error_test() {
  let property = nullable_integer_with_minimum(0.0)
  let errors =
    validator.validate_field(
      age_path(),
      Some(IntegerValue(-5)),
      property,
      True,
      property.render_hints.widget,
    )

  list.map(errors, fn(e) { e.rule })
  |> should.equal(["minimum"])
}

// Regression pin: a required, non-nullable empty field must still error —
// the nullable guard must not loosen validation for ordinary fields.
pub fn non_nullable_required_empty_reports_required_error_test() {
  let property =
    SchemaProperty(..empty_property(), field_type: Some(IntegerType))
  let errors =
    validator.validate_field(
      age_path(),
      None,
      property,
      True,
      property.render_hints.widget,
    )

  list.map(errors, fn(e) { e.rule })
  |> should.equal(["required"])
}

// --- required marker suppression for nullable properties ---

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

pub fn make_field_ctx_suppresses_marker_for_nullable_required_test() {
  let ctx =
    field_common.make_field_ctx(
      model: model.init(empty_schema()),
      path: age_path(),
      property: nullable_integer_property(),
      is_required: True,
      is_disabled: False,
      is_readonly: False,
    )
  ctx.is_required |> should.be_false

  let html =
    field_common.render_label(
      field_name: "age",
      property: ctx.property,
      is_required: ctx.is_required,
      hints: ctx.hints,
    )
    |> element.to_string

  html |> string.contains("formosh-required") |> should.be_false
}

pub fn make_field_ctx_keeps_marker_for_non_nullable_required_test() {
  let property =
    SchemaProperty(..empty_property(), field_type: Some(IntegerType))
  let ctx =
    field_common.make_field_ctx(
      model: model.init(empty_schema()),
      path: age_path(),
      property: property,
      is_required: True,
      is_disabled: False,
      is_readonly: False,
    )
  ctx.is_required |> should.be_true

  let html =
    field_common.render_label(
      field_name: "age",
      property: ctx.property,
      is_required: ctx.is_required,
      hints: ctx.hints,
    )
    |> element.to_string

  html |> string.contains("formosh-required") |> should.be_true
}

pub fn make_child_ctx_suppresses_marker_for_nullable_required_test() {
  let parent =
    field_common.FieldRenderCtx(
      path: path.from_field_name("parent"),
      property: empty_property(),
      value: None,
      is_required: False,
      is_disabled: False,
      is_readonly: False,
      hints: types.empty_hints(),
    )
  let child_path = [PropertySegment("parent"), PropertySegment("age")]
  let child =
    field_common.make_child_ctx(
      parent: parent,
      model: model.init(empty_schema()),
      path: child_path,
      property: nullable_integer_property(),
      is_required: True,
    )
  child.is_required |> should.be_false
}

pub fn make_child_ctx_keeps_marker_for_non_nullable_required_test() {
  let parent =
    field_common.FieldRenderCtx(
      path: path.from_field_name("parent"),
      property: empty_property(),
      value: None,
      is_required: False,
      is_disabled: False,
      is_readonly: False,
      hints: types.empty_hints(),
    )
  let child_path = [PropertySegment("parent"), PropertySegment("age")]
  let property =
    SchemaProperty(..empty_property(), field_type: Some(IntegerType))
  let child =
    field_common.make_child_ctx(
      parent: parent,
      model: model.init(empty_schema()),
      path: child_path,
      property: property,
      is_required: True,
    )
  child.is_required |> should.be_true
}
