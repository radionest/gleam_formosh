/// Submit gating tests (issue #23).
///
/// `model.can_submit` stays strict — any error blocks. `is_valid_for_submit`
/// is the permissive companion that ignores errors on UI-suppressed paths.
/// `hidden_errors` returns just the suppressed-path slice of `model.errors`
/// for diagnostic formatting in `update.warn_if_only_hidden_blocks`.
import formosh/form/model.{FormModel}
import formosh/form/path
import formosh/schema/types
import formosh/validation/error
import gleam/dict
import gleam/option.{None, Some}
import gleeunit/should

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

fn schema_with(
  props: List(#(String, types.SchemaProperty)),
  required: List(String),
) -> types.JsonSchema {
  types.JsonSchema(..empty_schema(), properties: props, required: required)
}

fn hidden_string_prop() -> types.SchemaProperty {
  types.SchemaProperty(
    ..types.empty_property(),
    field_type: Some(types.StringType),
    render_hints: types.RenderHints(
      ..types.empty_hints(),
      widget: Some(types.HiddenWidget),
    ),
  )
}

fn string_prop() -> types.SchemaProperty {
  types.SchemaProperty(
    ..types.empty_property(),
    field_type: Some(types.StringType),
  )
}

fn required_error(field_name: String) -> error.ValidationError {
  error.ValidationError(
    field: path.from_field_name(field_name),
    message: "Field is required",
    rule: "required",
  )
}

fn with_error(model: model.FormModel, field_name: String) -> model.FormModel {
  model.add_error_at_path(
    model,
    path.from_field_name(field_name),
    required_error(field_name),
  )
}

// Sanity: a clean model passes both gates.
pub fn clean_model_passes_both_gates_test() {
  let schema = schema_with([#("x", string_prop())], ["x"])
  let m = model.init(schema)
  model.can_submit(m) |> should.be_true()
  model.is_valid_for_submit(m) |> should.be_true()
  model.hidden_errors(m) |> dict.is_empty() |> should.be_true()
}

// Visible-path errors block both gates (regression: permissive must still
// block on visible errors).
pub fn visible_error_blocks_both_gates_test() {
  let schema = schema_with([#("x", string_prop())], ["x"])
  let m = model.init(schema) |> with_error("x")
  model.can_submit(m) |> should.be_false()
  model.is_valid_for_submit(m) |> should.be_false()
}

// Hidden-path errors block the strict gate but pass the permissive one.
// `hidden_errors` returns the slice that's hidden.
pub fn hidden_only_error_passes_permissive_but_blocks_strict_test() {
  let schema = schema_with([#("x", hidden_string_prop())], ["x"])
  let m = model.init(schema) |> with_error("x")
  model.can_submit(m) |> should.be_false()
  model.is_valid_for_submit(m) |> should.be_true()
  model.hidden_errors(m) |> dict.keys() |> should.equal(["x"])
}

// Mixed visible + hidden errors → permissive blocks (visible error still
// stands), strict blocks too. `hidden_errors` returns only the hidden slice.
pub fn mixed_errors_block_both_gates_test() {
  let schema =
    schema_with([#("a", hidden_string_prop()), #("b", string_prop())], [
      "a", "b",
    ])
  let m = model.init(schema) |> with_error("a") |> with_error("b")
  model.can_submit(m) |> should.be_false()
  model.is_valid_for_submit(m) |> should.be_false()
  let hidden = model.hidden_errors(m)
  hidden |> dict.keys() |> should.equal(["a"])
}

// `is_valid_for_submit` returns False while a submit is in flight even when
// no errors exist — mirrors `can_submit`'s same guard.
pub fn in_flight_submit_blocks_permissive_test() {
  let schema = schema_with([#("x", string_prop())], [])
  let m = FormModel(..model.init(schema), is_submitting: True)
  model.can_submit(m) |> should.be_false()
  model.is_valid_for_submit(m) |> should.be_false()
}
