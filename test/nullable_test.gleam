// Nullable-field semantics.
//
// Spec: openspec/changes/add-anyof-union-support/specs/nullable-fields/spec.md
//   - "Empty nullable fields validate as satisfied"
//   - "Nullable fields render without the required marker"

import formosh/fields/field_common
import formosh/form/defaults
import formosh/form/json_utils
import formosh/form/model
import formosh/form/path.{type FieldPath, ArraySegment, PropertySegment}
import formosh/schema/types.{
  type SchemaProperty, ArrayType, ArrayValue, IntegerType, IntegerValue,
  NullValue, NumberConstraints, ObjectType, ObjectValue, SchemaProperty,
  StringType, empty_number_constraints, empty_property,
}
import formosh/schema/ui_schema
import formosh/schema/validator
import gleam/dict
import gleam/json
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

// --- Task 10: null-on-empty submission payload ---
//
// Spec: "Empty nullable fields submit null"
// (openspec/changes/add-anyof-union-support/specs/nullable-fields/spec.md)
//
// `values_to_json` and `submit_form_effect` in update.gleam are both
// private, and the latter wraps its result in a Lustre `Effect` that only a
// running app runtime can execute — there is no way to capture the actual
// submitted bytes in a gleeunit test (confirmed: no test in this suite
// imports `rsvp` or exercises `Effect(FormMsg)`). `submit_payload` below
// reproduces the exact composition wired at update.gleam:729
// (get_resolved_values |> inject_nullable_nulls |> value_to_json) through a
// real FormModel, which is the closest testable proxy for the real submit
// path.

fn schema_with(props: List(#(String, SchemaProperty))) -> types.JsonSchema {
  types.JsonSchema(..empty_schema(), properties: props)
}

fn plain_string_property() -> SchemaProperty {
  SchemaProperty(..empty_property(), field_type: Some(StringType))
}

fn nullable_string_property() -> SchemaProperty {
  SchemaProperty(
    ..empty_property(),
    field_type: Some(StringType),
    nullable: True,
  )
}

fn row_with_nullable_note_schema() -> SchemaProperty {
  SchemaProperty(
    ..empty_property(),
    field_type: Some(ObjectType),
    properties: Some([#("note", nullable_string_property())]),
  )
}

fn address_property() -> SchemaProperty {
  SchemaProperty(
    ..empty_property(),
    field_type: Some(ObjectType),
    properties: Some([#("apartment", nullable_string_property())]),
  )
}

fn rows_array_property(item_schema: SchemaProperty) -> SchemaProperty {
  SchemaProperty(
    ..empty_property(),
    field_type: Some(ArrayType),
    items: Some(item_schema),
  )
}

// A genuine 2-member anyOf union (not a nullable-scalar shorthand): branch 0
// carries a plain "label" field, branch 1 carries a nullable "count". Mirrors
// the fixture shape used in union_resolver_test.gleam — the outer node
// itself has field_type/properties: None until resolved.
fn union_row_item_schema() -> SchemaProperty {
  let member_a =
    SchemaProperty(
      ..empty_property(),
      field_type: Some(ObjectType),
      properties: Some([#("label", plain_string_property())]),
    )
  let member_b =
    SchemaProperty(
      ..empty_property(),
      field_type: Some(ObjectType),
      properties: Some([#("count", nullable_integer_property())]),
    )
  SchemaProperty(..empty_property(), any_of: Some([member_a, member_b]))
}

fn submit_payload(
  schema: types.JsonSchema,
  initial_values: dict.Dict(String, types.Value),
  selected: List(#(FieldPath, Int)),
) -> String {
  let m =
    model.init_with_full_config(
      schema,
      None,
      False,
      initial_values,
      ui_schema.empty_ui_schema(),
    )
  let m = model.FormModel(..m, selected_branches: selected)
  model.get_resolved_values(m)
  |> defaults.inject_nullable_nulls(
    m.resolved_schema.properties,
    _,
    m.selected_branches,
  )
  |> json_utils.value_to_json
  |> json.to_string
}

// Scenario: Empty Optional scalar submits null
pub fn empty_nullable_scalar_submits_null_test() {
  let schema = schema_with([#("age", nullable_integer_property())])
  submit_payload(schema, dict.new(), [])
  |> string.contains("\"age\":null")
  |> should.be_true
}

// Scenario: Filled nullable field submits its value
pub fn filled_nullable_scalar_submits_value_test() {
  let schema = schema_with([#("age", nullable_integer_property())])
  submit_payload(schema, dict.from_list([#("age", IntegerValue(42))]), [])
  |> string.contains("\"age\":42")
  |> should.be_true
}

// Scenario: Non-nullable empty field stays omitted
pub fn non_nullable_empty_field_stays_omitted_test() {
  let schema = schema_with([#("name", plain_string_property())])
  submit_payload(schema, dict.new(), [])
  |> string.contains("\"name\"")
  |> should.be_false
}

// Scenario: Nested nullable inside an array row
pub fn nullable_inside_array_row_submits_null_test() {
  let schema =
    schema_with([
      #("rows", rows_array_property(row_with_nullable_note_schema())),
    ])
  let initial = dict.from_list([#("rows", ArrayValue([ObjectValue([])]))])
  submit_payload(schema, initial, [])
  |> string.contains("\"note\":null")
  |> should.be_true
}

// Extra depth case beyond the 4 spec scenarios: the requirement text says
// "at any depth — nested objects and array rows included". This one is a
// plain nested object (no array involved), exercising inject_property's
// ObjectType-recursion branch that the array-row test above does not touch.
pub fn nullable_inside_nested_object_submits_null_test() {
  let schema = schema_with([#("address", address_property())])
  let initial = dict.from_list([#("address", ObjectValue([]))])
  submit_payload(schema, initial, [])
  |> string.contains("\"apartment\":null")
  |> should.be_true
}

// Extra correctness case: the array-row walk must resolve the row's
// *effective* property via union_resolver.resolve_effective_property (design
// D4), not the raw unresolved anyOf node (which carries `properties: None`).
// Branch 1 is stored in `selected` — only branch 1's "count" is nullable, so
// this only passes if `selected` is actually threaded through resolution;
// a bug that ignored `selected` would infer branch 0 (empty row -> no key
// overlap -> defaults to 0) and never see "count" at all.
pub fn nullable_inside_union_array_row_resolves_active_branch_test() {
  let schema =
    schema_with([#("rows", rows_array_property(union_row_item_schema()))])
  let initial = dict.from_list([#("rows", ArrayValue([ObjectValue([])]))])
  let selected = [#([PropertySegment("rows"), ArraySegment(0)], 1)]
  let payload = submit_payload(schema, initial, selected)
  payload |> string.contains("\"count\":null") |> should.be_true
  payload |> string.contains("\"label\"") |> should.be_false
}
