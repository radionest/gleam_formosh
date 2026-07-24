import formosh/form/model.{FormSubmitted, UpdateFieldPath}
import formosh/form/path.{PropertySegment, get_at_path}
import formosh/internal/component_core as core
import formosh/schema/parser
import formosh/schema/types.{ArrayValue, StringValue}
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

fn parse(json: String) {
  let assert Ok(schema) = parser.parse_schema(json)
  schema
}

fn name_schema() {
  parse(
    "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}},\"required\":[\"name\"]}",
  )
}

fn loaded() {
  let #(model, _) = core.init(Nil)
  let #(model, _) = core.update(model, core.SchemaChanged(name_schema()))
  model
}

fn edited() {
  let #(model, _) =
    core.update(
      loaded(),
      core.FormMessage(UpdateFieldPath(
        [PropertySegment("name")],
        StringValue("Ada"),
      )),
    )
  model
}

fn form_values(model: core.Model) {
  let assert Some(form_model) = model.form_model
  form_model.values
}

pub fn schema_changed_initializes_and_validates_test() {
  let assert Some(form_model) = loaded().form_model
  // required "name" is empty → validation ran and found it
  form_model.is_valid |> should.be_false()
}

pub fn reinit_tops_arrays_to_min_items_test() {
  let schema =
    parse(
      "{\"type\":\"object\",\"properties\":{\"tags\":{\"type\":\"array\",\"minItems\":2,\"items\":{\"type\":\"string\"}}}}",
    )
  let #(model, _) = core.init(Nil)
  let #(model, _) = core.update(model, core.SchemaChanged(schema))
  let assert Some(ArrayValue(items)) =
    get_at_path(form_values(model), [PropertySegment("tags")])
  list.length(items) |> should.equal(2)
}

pub fn initial_values_change_replaces_user_edits_test() {
  let #(model, _) =
    core.update(
      edited(),
      core.InitialValuesChanged(dict.from_list([#("name", StringValue("Bob"))])),
    )
  get_at_path(form_values(model), [PropertySegment("name")])
  |> should.equal(Some(StringValue("Bob")))
}

pub fn read_only_toggle_preserves_values_test() {
  let before = edited()
  let #(after, _) = core.update(before, core.ReadOnlyChanged(True))
  form_values(after) |> should.equal(form_values(before))
  let assert Some(form_model) = after.form_model
  form_model.read_only |> should.be_true()
}

pub fn ui_schema_patch_preserves_values_test() {
  let before = edited()
  let #(after, _) = core.update(before, core.UiSchemaChanged(before.ui_schema))
  form_values(after) |> should.equal(form_values(before))
}

pub fn submit_method_without_url_does_not_reinit_test() {
  let before = edited()
  let #(after, _) = core.update(before, core.SubmitMethodChanged("PUT"))
  form_values(after) |> should.equal(form_values(before))
}

pub fn form_submitted_clears_submission_result_test() {
  let #(model, _) =
    core.update(edited(), core.FormMessage(FormSubmitted(Ok("saved"))))
  let assert Some(form_model) = model.form_model
  form_model.submission_result |> should.equal(None)
}

pub fn show_readonly_fields_change_reinitializes_test() {
  let before = edited()
  let #(after, _) = core.update(before, core.ShowReadonlyFieldsChanged(False))
  // reinit path: the user edit is rebuilt away (characterizes current semantics)
  get_at_path(form_values(after), [PropertySegment("name")])
  |> should.not_equal(Some(StringValue("Ada")))
}
