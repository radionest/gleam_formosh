import formosh/fields/field_common
import formosh/fields/field_dispatcher
import formosh/form/model
import formosh/form/path.{ArraySegment, PropertySegment}
import formosh/form/update
import formosh/form/view
import formosh/form/widget_msg.{ToggleCollapseCompleted, ToggleRowExpanded}
import formosh/schema/parser
import formosh/schema/properties
import formosh/schema/types
import formosh/schema/ui_parser
import gleam/dict
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import lustre/element

const schema_json = "{\"type\":\"object\",\"properties\":{\"zones\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"required\":[\"state\"],\"properties\":{\"label\":{\"type\":\"string\",\"title\":\"Зона\"},\"state\":{\"type\":\"string\",\"title\":\"Состояние\"}}}}}}"

const ui_json = "{\"zones\":{\"ui:options\":{\"collapseCompleted\":true,\"collapseCompletedLabel\":\"Сворачивать заполненные\",\"summaryFields\":[\"label\",\"state\"]}}}"

const zones = [PropertySegment("zones")]

/// Row 0 valid and filled, row 1 missing its required `state`.
fn rows() -> types.Value {
  types.ArrayValue([
    types.ObjectValue([
      #("label", types.StringValue("Диафрагма")),
      #("state", types.StringValue("absent")),
    ]),
    types.ObjectValue([#("label", types.StringValue("Печень"))]),
  ])
}

fn init(ui: String) -> model.FormModel {
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(ui_schema) = ui_parser.parse(ui)
  let m =
    model.init_with_full_config(schema, None, False, dict.new(), ui_schema)
  model.FormModel(..m, values: types.ObjectValue([#("zones", rows())]))
}

fn render(m: model.FormModel) -> String {
  let assert Some(prop) = properties.get(m.schema.properties, "zones")
  let ctx =
    field_common.make_field_ctx(
      model: m,
      path: zones,
      property: prop,
      is_required: False,
      is_disabled: False,
      is_readonly: False,
    )
  field_dispatcher.render_field_at_path(ctx, m) |> element.to_string
}

pub fn completed_row_collapses_incomplete_row_does_not_test() {
  let html = render(init(ui_json))
  // Row 0 is summarised…
  html |> string.contains("array-item-summary") |> should.be_true
  html |> string.contains("Диафрагма") |> should.be_true
  // …row 1 still shows its inputs.
  html |> string.contains("Печень") |> should.be_true
  html |> string.contains("zones.[1].state") |> should.be_true
  // …and row 0's inputs are gone.
  html |> string.contains("zones.[0].state") |> should.be_false
}

pub fn header_renders_toggle_and_progress_test() {
  let html = render(init(ui_json))
  html |> string.contains("Сворачивать заполненные") |> should.be_true
  html |> string.contains("array-progress") |> should.be_true
  html |> string.contains("1 / 2") |> should.be_true
}

pub fn toggle_stays_rendered_when_switched_off_test() {
  let #(m1, _) =
    update.update(
      init(ui_json),
      model.array_msg(ToggleCollapseCompleted(zones)),
    )
  let html = render(m1)
  // Every row expanded…
  html |> string.contains("zones.[0].state") |> should.be_true
  // …and the toggle is still there to switch back on.
  html |> string.contains("Сворачивать заполненные") |> should.be_true
}

pub fn expanded_completed_row_keeps_its_summary_test() {
  let #(m1, _) =
    update.update(
      init(ui_json),
      model.array_msg(
        ToggleRowExpanded([PropertySegment("zones"), ArraySegment(0)]),
      ),
    )
  let html = render(m1)
  // Fields are back…
  html |> string.contains("zones.[0].state") |> should.be_true
  // …and the summary control is still there to close it again.
  html |> string.contains("array-item-summary") |> should.be_true
}

pub fn option_absent_renders_exactly_as_before_test() {
  let plain = render(init("{}"))
  plain |> string.contains("array-item-summary") |> should.be_false
  plain |> string.contains("array-progress") |> should.be_false
  plain |> string.contains("array-toggle") |> should.be_false
  // Both rows fully rendered.
  plain |> string.contains("zones.[0].state") |> should.be_true
  plain |> string.contains("zones.[1].state") |> should.be_true
}

pub fn remove_control_stays_reachable_while_collapsed_test() {
  // Row 0 is collapsed; its remove button must still be rendered, which the
  // "row becomes a button" shape would have lost.
  let html = render(init(ui_json))
  html |> string.contains("array-item-summary") |> should.be_true
  html |> string.contains("remove-array-item") |> should.be_true
}

pub fn readonly_array_emits_no_collapse_affordances_test() {
  // show_readonly_fields must be True, or `ui_resolver.is_suppressed` drops the
  // field entirely and every assertion below passes vacuously.
  let m = model.FormModel(..init(ui_json), show_readonly_fields: True)
  let assert Some(prop) = properties.get(m.schema.properties, "zones")
  let ctx =
    field_common.make_field_ctx(
      model: m,
      path: zones,
      property: prop,
      is_required: False,
      is_disabled: False,
      is_readonly: True,
    )
  let html = field_dispatcher.render_field_at_path(ctx, m) |> element.to_string
  html |> string.contains("array-toggle") |> should.be_false
  html |> string.contains("array-progress") |> should.be_false
  html |> string.contains("array-item-summary") |> should.be_false
}

pub fn review_mode_ignores_the_option_test() {
  // Whole-form review mode routes through readonly_field (view.gleam:112-113),
  // so array_field is never reached and no collapse affordance can appear.
  let m = model.FormModel(..init(ui_json), read_only: True)
  let html = view.view(m) |> element.to_string
  html |> string.contains("array-toggle") |> should.be_false
  html |> string.contains("array-item-summary") |> should.be_false
  html |> string.contains("readonly-") |> should.be_true
}

// --- carried-forward requirement 1: array_rows_expanded beats is_completed ---

const add_item_schema_json = "{\"type\":\"object\",\"properties\":{\"notes\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"note\":{\"type\":\"string\",\"default\":\"x\"}}}}}}"

const add_item_ui_json = "{\"notes\":{\"ui:options\":{\"collapseCompleted\":true}}}"

pub fn freshly_added_row_renders_expanded_despite_satisfying_completed_test() {
  // Item schema has no `required` and a defaulted field: the row
  // `AddArrayItemPath` builds satisfies `is_completed` the instant it is
  // created. Without the update.gleam force-expand fix
  // (`array_rows_expanded` gains the new row's path), this row would
  // collapse the moment the user clicks "Add item" and they would never see
  // what they just added.
  let assert Ok(schema) = parser.parse_schema(add_item_schema_json)
  let assert Ok(ui_schema) = ui_parser.parse(add_item_ui_json)
  let m0 =
    model.init_with_full_config(schema, None, False, dict.new(), ui_schema)
  let #(m1, _) =
    update.update(m0, model.AddArrayItemPath([PropertySegment("notes")]))
  let assert Some(prop) = properties.get(m1.schema.properties, "notes")
  let ctx =
    field_common.make_field_ctx(
      model: m1,
      path: [PropertySegment("notes")],
      property: prop,
      is_required: False,
      is_disabled: False,
      is_readonly: False,
    )
  let html = field_dispatcher.render_field_at_path(ctx, m1) |> element.to_string
  // The row's own input is present…
  html |> string.contains("notes.[0].note") |> should.be_true
  // …and the summary control is ALSO there (row is completed, just not
  // collapsed) — both states render the summary per design D5.
  html |> string.contains("array-item-summary") |> should.be_true
}

// --- carried-forward requirement 2: array-level errors survive collapsing ---

const min_items_schema_json = "{\"type\":\"object\",\"properties\":{\"zones\":{\"type\":\"array\",\"minItems\":2,\"items\":{\"type\":\"object\",\"required\":[\"state\"],\"properties\":{\"label\":{\"type\":\"string\"},\"state\":{\"type\":\"string\"}}}}}}"

pub fn array_length_error_stays_visible_while_rows_collapse_test() {
  // One completed row against minItems: 2 — the row collapses, but the
  // array-level minItems error is filed at the array's own path, entirely
  // outside any row's scope, and must keep rendering. It also bypasses the
  // touched gate (error.is_array_length), so no explicit touch is needed.
  let assert Ok(schema) = parser.parse_schema(min_items_schema_json)
  let assert Ok(ui_schema) = ui_parser.parse(ui_json)
  let m0 =
    model.init_with_full_config(schema, None, False, dict.new(), ui_schema)
  let m1 =
    model.FormModel(
      ..m0,
      values: types.ObjectValue([
        #(
          "zones",
          types.ArrayValue([
            types.ObjectValue([
              #("label", types.StringValue("Диафрагма")),
              #("state", types.StringValue("absent")),
            ]),
          ]),
        ),
      ]),
    )
  let #(m2, _) = update.update(m1, model.ValidateForm)
  let html = render(m2)
  // The single row is completed and collapses…
  html |> string.contains("array-item-summary") |> should.be_true
  html |> string.contains("zones.[0].state") |> should.be_false
  // …but the array-level length error still renders.
  html |> string.contains("data-error") |> should.be_true
  html |> string.contains("At least 2 item(s) required") |> should.be_true
}
