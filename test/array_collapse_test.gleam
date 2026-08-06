import formosh/fields/array_collapse
import formosh/form/path.{PropertySegment}
import formosh/schema/types
import formosh/schema/ui_parser
import formosh/schema/ui_resolver
import gleeunit/should

fn hints_for(ui_json: String) -> types.RenderHints {
  let assert Ok(ui) = ui_parser.parse(ui_json)
  ui_resolver.resolve_hints(
    ui,
    [PropertySegment("zones")],
    types.empty_property(),
  )
}

pub fn options_read_every_key_test() {
  let hints =
    hints_for(
      "{\"zones\":{\"ui:options\":{\"collapseCompleted\":true,\"collapseCompletedLabel\":\"Сворачивать заполненные\",\"summaryFields\":[\"zone_id\",\"label\"]}}}",
    )
  let opts = array_collapse.options(hints.options)
  opts.enabled |> should.be_true
  opts.label |> should.equal("Сворачивать заполненные")
  opts.summary_fields |> should.equal(["zone_id", "label"])
}

pub fn options_default_when_absent_test() {
  let opts = array_collapse.options(hints_for("{\"zones\":{}}").options)
  opts.enabled |> should.be_false
  opts.label |> should.equal("Collapse completed")
  opts.summary_fields |> should.equal([])
}

pub fn options_ignore_wrong_types_test() {
  let hints =
    hints_for(
      "{\"zones\":{\"ui:options\":{\"collapseCompleted\":\"yes\",\"collapseCompletedLabel\":7,\"summaryFields\":\"label\"}}}",
    )
  let opts = array_collapse.options(hints.options)
  opts.enabled |> should.be_false
  opts.label |> should.equal("Collapse completed")
  opts.summary_fields |> should.equal([])
}

pub fn options_drop_non_string_summary_entries_test() {
  let hints =
    hints_for(
      "{\"zones\":{\"ui:options\":{\"summaryFields\":[\"label\",3,\"state\"]}}}",
    )
  array_collapse.options(hints.options).summary_fields
  |> should.equal(["label", "state"])
}
