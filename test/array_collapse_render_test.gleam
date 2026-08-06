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

/// A single valid, fully-filled row — for tests that need exactly one row
/// in the array, so there is no sibling row whose own rendering could
/// satisfy an assertion by accident.
fn single_valid_row() -> types.Value {
  types.ArrayValue([
    types.ObjectValue([
      #("label", types.StringValue("Диафрагма")),
      #("state", types.StringValue("absent")),
    ]),
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
  // …row 0 carries the collapsed-state marker, presence-only and lowercase.
  html |> string.contains("data-collapsed=\"true\"") |> should.be_true
  // …and its summary button reports the same state to assistive tech.
  html |> string.contains("aria-expanded=\"false\"") |> should.be_true
}

pub fn header_renders_toggle_and_progress_test() {
  let html = render(init(ui_json))
  html |> string.contains("Сворачивать заполненные") |> should.be_true
  // Exact element text content — pins the "no prefix word" rule. A bare
  // `contains("1 / 2")` would also pass for e.g. "Completed: 1 / 2".
  html
  |> string.contains("part=\"array-progress\">1 / 2</span>")
  |> should.be_true
}

pub fn toggle_stays_rendered_when_switched_off_test() {
  let #(m1, _) =
    update.update(
      init(ui_json),
      model.array_msg(ToggleCollapseCompleted(zones)),
    )
  let html = render(m1)
  // Every row expanded, no summaries left…
  html |> string.contains("zones.[0].state") |> should.be_true
  html |> string.contains("array-item-summary") |> should.be_false
  // …the toggle is still there to switch back on, rendered unchecked (a
  // Lustre `attribute.checked(False)` is a DOM property, not an attribute,
  // so it never appears in `element.to_string` output at all — "checked"
  // absent from the whole render is exactly "the box is unchecked").
  html |> string.contains("Сворачивать заполненные") |> should.be_true
  html |> string.contains("checked") |> should.be_false
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
  // …reporting its expanded state to assistive tech.
  html |> string.contains("aria-expanded=\"true\"") |> should.be_true
}

pub fn option_absent_renders_exactly_as_before_test() {
  let plain = render(init("{}"))
  plain |> string.contains("array-item-summary") |> should.be_false
  plain |> string.contains("array-progress") |> should.be_false
  plain |> string.contains("array-toggle") |> should.be_false
  // `data-collapsed` is presence-only (fix round 1, item 1) — it must never
  // appear at all when collapsing isn't even available.
  plain |> string.contains("data-collapsed") |> should.be_false
  // Both rows fully rendered, structurally intact: fields, per-row header,
  // and the container's own add/remove controls all present.
  plain |> string.contains("zones.[0].state") |> should.be_true
  plain |> string.contains("zones.[1].state") |> should.be_true
  plain |> string.contains("array-item-fields") |> should.be_true
  plain |> string.contains("add-array-item") |> should.be_true
  plain |> string.contains("remove-array-item") |> should.be_true
  // The per-row header renders before that row's fields, not after —
  // catches a reordering of `.array-item`'s children.
  let assert [before_first_fields, ..] =
    string.split(plain, "array-item-fields")
  before_first_fields |> string.contains("array-item-header") |> should.be_true
}

pub fn remove_control_stays_reachable_while_collapsed_test() {
  // Single row, no minItems: if the collapsed row's whole header were
  // dropped (the "row becomes a button" shape this guards against), this is
  // the ONLY row in the array, so remove-array-item would vanish entirely —
  // nothing else in the fixture can satisfy the assertion by accident, the
  // way a second (expanded) row's own header could.
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(ui_schema) = ui_parser.parse(ui_json)
  let m0 =
    model.init_with_full_config(schema, None, False, dict.new(), ui_schema)
  let m1 =
    model.FormModel(
      ..m0,
      values: types.ObjectValue([#("zones", single_valid_row())]),
    )
  let html = render(m1)
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
  // Positive: the array still renders its rows — readonly, not suppressed
  // or emptied. Without this, the three assertions above would also pass
  // vacuously if the whole array stopped rendering.
  html |> string.contains("zones.[0].state") |> should.be_true
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
      values: types.ObjectValue([#("zones", single_valid_row())]),
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

// --- fix round 1, item 6: summary fallback when summary_values is empty ---

const empty_summary_schema_json = "{\"type\":\"object\",\"properties\":{\"zones\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"affected\":{\"type\":\"boolean\"},\"note\":{\"type\":\"string\"}}}}}}"

const empty_summary_ui_json = "{\"zones\":{\"ui:options\":{\"collapseCompleted\":true,\"summaryFields\":[\"affected\"]}}}"

pub fn empty_summary_falls_back_to_row_number_test() {
  // `affected: False` makes the row `is_completed` (only ONE non-blank
  // field is required, and `BooleanValue(False)` counts as non-blank) —
  // but `summary_values` omits `false` booleans, and `note` is blank, so
  // the summary line has literally nothing to show for `summaryFields:
  // ["affected"]`. The button must still get non-empty, visible content.
  let assert Ok(schema) = parser.parse_schema(empty_summary_schema_json)
  let assert Ok(ui_schema) = ui_parser.parse(empty_summary_ui_json)
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
              #("affected", types.BooleanValue(False)),
              #("note", types.StringValue("")),
            ]),
          ]),
        ),
      ]),
    )
  let html = render(m1)
  // The row collapses (it IS completed)…
  html |> string.contains("array-item-summary") |> should.be_true
  // …and the button falls back to the row's 1-based position rather than
  // rendering empty. This is the single row in the array, so "1" is
  // unambiguous — and distinct from the "1 / 1" progress text, which never
  // puts a digit directly against a closing `</span>`.
  html
  |> string.contains("part=\"array-item-summary-value\">1</span>")
  |> should.be_true
}

// --- task 8: the array's full `::part()` surface, in one render ---

pub fn array_exposes_its_part_surface_test() {
  let html = render(init(ui_json))
  html |> string.contains("part=\"array-field\"") |> should.be_true
  html |> string.contains("part=\"array-items\"") |> should.be_true
  html |> string.contains("part=\"array-item\"") |> should.be_true
  html |> string.contains("part=\"array-item-header\"") |> should.be_true
  html |> string.contains("part=\"array-add\"") |> should.be_true
  html |> string.contains("part=\"array-toggle\"") |> should.be_true
  html |> string.contains("part=\"array-progress\"") |> should.be_true
  html |> string.contains("part=\"array-item-summary\"") |> should.be_true
  html |> string.contains("part=\"array-item-summary-value\"") |> should.be_true
  // The fixture's `summaryFields` has two entries (`label`, `state`) and row 0
  // fills both, so the separator between summary values renders too.
  html |> string.contains("part=\"array-item-summary-sep\"") |> should.be_true
}
