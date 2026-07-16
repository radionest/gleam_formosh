/// Submit gating tests (issue #23).
///
/// `model.can_submit` stays strict — any error blocks. `is_valid_for_submit`
/// is the permissive companion that ignores errors on UI-suppressed paths.
/// `hidden_errors` returns just the suppressed-path slice of `model.errors`
/// for diagnostic formatting in `update.warn_only_hidden_blocks_effect`.
import formosh/form/model.{FormModel}
import formosh/form/path
import formosh/form/update
import formosh/schema/types
import formosh/schema/ui_schema
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
    all_of: None,
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

fn hidden_object_prop(
  properties: List(#(String, types.SchemaProperty)),
  required: List(String),
) -> types.SchemaProperty {
  types.SchemaProperty(
    ..types.empty_property(),
    field_type: Some(types.ObjectType),
    properties: Some(properties),
    required: required,
    render_hints: types.RenderHints(
      ..types.empty_hints(),
      widget: Some(types.HiddenWidget),
    ),
  )
}

fn defaulted_hidden_string_prop() -> types.SchemaProperty {
  types.SchemaProperty(
    ..hidden_string_prop(),
    default: Some(types.StringValue("auto")),
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

// Validator-driven (issue #23 case 2): a required leaf inside a hidden object
// produces a real error at `x.y` — the validator is visibility-unaware. The
// object must be *present* (an empty `{}`) for its required leaf to validate,
// which is exactly the invisible-block scenario: a hidden object supplied
// without its required child. Runs the full `validate_all_fields` pipeline
// instead of hand-injecting, pinning that a validator-produced *nested* key
// lands inside the walker's invisible set. Strict gate blocks; permissive
// gate passes; `hidden_errors` keys the suppressed leaf.
pub fn hidden_object_required_leaf_blocks_via_validator_test() {
  let inner = hidden_object_prop([#("y", string_prop())], ["y"])
  let schema = schema_with([#("x", inner)], [])
  let m =
    model.init_with_full_config(
      schema,
      None,
      False,
      dict.from_list([#("x", types.ObjectValue([]))]),
      ui_schema.empty_ui_schema(),
    )
    |> update.validate_all_fields
  model.can_submit(m) |> should.be_false()
  model.is_valid_for_submit(m) |> should.be_true()
  model.hidden_errors(m) |> dict.keys() |> should.equal(["x.y"])
}

// Validator-driven happy path: a hidden required field carrying a JSON Schema
// `default` is populated at init, so `validate_all_fields` finds nothing to
// report and submit proceeds. This is the case the diagnostic warn stays
// silent for.
pub fn hidden_required_with_default_submits_test() {
  let schema = schema_with([#("x", defaulted_hidden_string_prop())], ["x"])
  let m = model.init(schema) |> update.validate_all_fields
  model.can_submit(m) |> should.be_true()
  model.hidden_errors(m) |> dict.is_empty() |> should.be_true()
}

// Validator-driven regression: a visible required field left empty blocks
// both gates — the permissive gate must never wave through a visible error.
pub fn visible_required_blocks_via_validator_test() {
  let schema = schema_with([#("x", string_prop())], ["x"])
  let m = model.init(schema) |> update.validate_all_fields
  model.can_submit(m) |> should.be_false()
  model.is_valid_for_submit(m) |> should.be_false()
}
