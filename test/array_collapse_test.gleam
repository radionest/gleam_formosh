import formosh/fields/array_collapse
import formosh/form/model
import formosh/form/path.{ArraySegment, PropertySegment}
import formosh/form/update
import formosh/schema/parser
import formosh/schema/properties
import formosh/schema/types
import formosh/schema/ui_parser
import formosh/schema/ui_resolver
import formosh/schema/ui_schema
import formosh/validation/cross_validator
import formosh/validation/error
import gleam/dict
import gleam/list
import gleam/option.{None}
import gleam/set
import gleeunit/should
import simplifile

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

const row_schema_json = "{\"type\":\"object\",\"properties\":{\"zones\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"required\":[\"state\"],\"properties\":{\"label\":{\"type\":\"string\"},\"state\":{\"type\":\"string\"},\"note\":{\"type\":\"string\"}}}}}}"

const zones_path = [PropertySegment("zones")]

fn model_with(rows: List(types.Value)) -> model.FormModel {
  let assert Ok(schema) = parser.parse_schema(row_schema_json)
  let m =
    model.init_with_full_config(
      schema,
      None,
      False,
      dict.new(),
      ui_schema.empty_ui_schema(),
    )
  model.FormModel(
    ..m,
    values: types.ObjectValue([#("zones", types.ArrayValue(rows))]),
  )
}

fn item_schema(m: model.FormModel) -> types.SchemaProperty {
  let assert option.Some(prop) = properties.get(m.schema.properties, "zones")
  let assert option.Some(items) = prop.items
  items
}

fn completed(m: model.FormModel, rows: List(types.Value), index: Int) -> Bool {
  let incomplete =
    array_collapse.incomplete_rows(
      zones_path,
      item_schema(m),
      rows,
      m.selected_branches,
    )
  let assert Ok(item) = list.drop(rows, index) |> list.first
  array_collapse.is_completed(m, zones_path, index, item, incomplete)
}

pub fn empty_row_is_not_completed_test() {
  let rows = [types.ObjectValue([])]
  completed(model_with(rows), rows, 0) |> should.be_false
}

pub fn row_missing_required_field_is_not_completed_test() {
  let rows = [types.ObjectValue([#("label", types.StringValue("a"))])]
  completed(model_with(rows), rows, 0) |> should.be_false
}

pub fn filled_valid_row_is_completed_test() {
  let rows = [
    types.ObjectValue([
      #("label", types.StringValue("a")),
      #("state", types.StringValue("absent")),
    ]),
  ]
  completed(model_with(rows), rows, 0) |> should.be_true
}

pub fn all_optional_empty_row_is_not_completed_test() {
  // No `required` at all: schema validation is clean, so only the non-empty
  // conjunct keeps this row open.
  let assert Ok(schema) =
    parser.parse_schema(
      "{\"type\":\"object\",\"properties\":{\"zones\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"note\":{\"type\":\"string\"}}}}}}",
    )
  let rows = [types.ObjectValue([#("note", types.StringValue(""))])]
  let m =
    model.FormModel(
      ..model.init_with_full_config(
        schema,
        None,
        False,
        dict.new(),
        ui_schema.empty_ui_schema(),
      ),
      values: types.ObjectValue([#("zones", types.ArrayValue(rows))]),
    )
  completed(m, rows, 0) |> should.be_false
}

pub fn only_invalid_rows_are_reported_incomplete_test() {
  let rows = [
    types.ObjectValue([#("state", types.StringValue("absent"))]),
    types.ObjectValue([#("label", types.StringValue("b"))]),
  ]
  let m = model_with(rows)
  array_collapse.incomplete_rows(
    zones_path,
    item_schema(m),
    rows,
    m.selected_branches,
  )
  |> set.contains(1)
  |> should.be_true
}

pub fn cross_validator_error_keeps_its_row_open_test() {
  let rows = [
    types.ObjectValue([
      #("label", types.StringValue("a")),
      #("state", types.StringValue("absent")),
    ]),
  ]
  let m0 = model_with(rows)
  let flag_row_zero =
    cross_validator.pure(fn(_m) {
      [
        error.ValidationError(
          field: [
            PropertySegment("zones"),
            ArraySegment(0),
            PropertySegment("state"),
          ],
          message: "not allowed here",
          rule: "custom",
        ),
      ]
    })
  let m1 =
    model.FormModel(
      ..m0,
      validator: option.Some(flag_row_zero),
      touched_fields: [
        [PropertySegment("zones"), ArraySegment(0), PropertySegment("state")],
      ],
    )
  let #(m2, _) = update.update(m1, model.ValidateForm)
  // The schema is satisfied, so validate_array_items is silent…
  array_collapse.incomplete_rows(
    zones_path,
    item_schema(m2),
    rows,
    m2.selected_branches,
  )
  |> set.contains(0)
  |> should.be_false
  // …but the recorded cross-field error still keeps the row open.
  completed(m2, rows, 0) |> should.be_false
}

pub fn no_completed_row_has_errors_beneath_it_test() {
  let rows = [
    types.ObjectValue([#("state", types.StringValue("absent"))]),
    types.ObjectValue([#("label", types.StringValue("b"))]),
  ]
  let m0 = model_with(rows)
  let #(m1, _) = update.update(m0, model.ValidateForm)
  // Non-vacuity guard: row 0 must actually be completed, or the `True`
  // branch below never runs and the loop proves nothing.
  completed(m1, rows, 0) |> should.be_true
  let incomplete =
    array_collapse.incomplete_rows(
      zones_path,
      item_schema(m1),
      rows,
      m1.selected_branches,
    )
  list.index_map(rows, fn(item, index) {
    case array_collapse.is_completed(m1, zones_path, index, item, incomplete) {
      True ->
        model.has_errors_under_path(m1, [
          PropertySegment("zones"),
          ArraySegment(index),
        ])
        |> should.be_false
      False -> Nil
    }
  })
  Nil
}

pub fn conditional_subtree_keeps_row_open_test() {
  let assert Ok(json) =
    simplifile.read("demo/schemas/carcinomatosis_radiology.json")
  let assert Ok(schema) = parser.parse_schema(json)
  let m0 =
    model.init_with_full_config(
      schema,
      None,
      False,
      dict.new(),
      ui_schema.empty_ui_schema(),
    )
  // `affected: true` lifts a `lesions` array with minItems 1 into the row; its
  // auto-created element is missing `form`/`contour`, so the row stays open.
  let #(m1, _) =
    update.update(
      m0,
      model.UpdateFieldPath(
        [PropertySegment("zones"), ArraySegment(0), PropertySegment("affected")],
        types.BooleanValue(True),
      ),
    )
  let assert option.Some(types.ArrayValue(rows)) =
    model.get_value_at_path(m1, zones_path)
  let assert option.Some(zones_prop) =
    properties.get(m1.schema.properties, "zones")
  let assert option.Some(items) = zones_prop.items
  let incomplete =
    array_collapse.incomplete_rows(
      zones_path,
      items,
      rows,
      m1.selected_branches,
    )
  set.contains(incomplete, 0) |> should.be_true
}

const summary_schema_json = "{\"type\":\"object\",\"properties\":{\"zones\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"zone_id\":{\"type\":\"integer\",\"title\":\"№ зоны\"},\"label\":{\"type\":\"string\",\"title\":\"Зона\"},\"state\":{\"type\":\"string\",\"title\":\"Состояние\",\"oneOf\":[{\"const\":\"present\",\"title\":\"Есть\"},{\"const\":\"absent\",\"title\":\"Нет\"}]},\"affected\":{\"type\":\"boolean\",\"title\":\"Поражение\"},\"secret\":{\"type\":\"string\",\"format\":\"password\",\"title\":\"Код\"},\"lesions\":{\"type\":\"array\",\"title\":\"Очаги\",\"items\":{\"type\":\"object\"}},\"tags\":{\"title\":\"Метки\",\"items\":{\"type\":\"string\"}},\"contact\":{\"type\":\"object\",\"title\":\"Контакт\",\"properties\":{\"phone\":{\"type\":\"string\"}}}}}}}}"

fn summary_of_with_ui(
  ui: ui_schema.UiSchema,
  row: types.Value,
  fields: List(String),
) -> List(String) {
  let assert Ok(schema) = parser.parse_schema(summary_schema_json)
  let assert option.Some(prop) = properties.get(schema.properties, "zones")
  let assert option.Some(items) = prop.items
  array_collapse.summary_values(
    ui,
    [PropertySegment("zones"), ArraySegment(0)],
    items,
    row,
    [],
    fields,
  )
}

fn summary_of(row: types.Value, fields: List(String)) -> List(String) {
  summary_of_with_ui(ui_schema.empty_ui_schema(), row, fields)
}

pub fn summary_honours_explicit_order_test() {
  let row =
    types.ObjectValue([
      #("label", types.StringValue("Диафрагма")),
      #("zone_id", types.IntegerValue(4)),
    ])
  summary_of(row, ["zone_id", "label"])
  |> should.equal(["4", "Диафрагма"])
}

pub fn summary_maps_one_of_code_to_title_test() {
  let row = types.ObjectValue([#("state", types.StringValue("present"))])
  summary_of(row, ["state"]) |> should.equal(["Есть"])
}

pub fn summary_omits_empty_values_test() {
  let row =
    types.ObjectValue([
      #("label", types.StringValue("")),
      #("state", types.NullValue),
      #("zone_id", types.IntegerValue(4)),
    ])
  summary_of(row, ["label", "state", "zone_id"]) |> should.equal(["4"])
}

pub fn summary_omits_absent_and_unknown_fields_test() {
  let row = types.ObjectValue([#("zone_id", types.IntegerValue(4))])
  summary_of(row, ["nope", "label", "zone_id"]) |> should.equal(["4"])
}

pub fn summary_true_boolean_shows_title_test() {
  let row = types.ObjectValue([#("affected", types.BooleanValue(True))])
  summary_of(row, ["affected"]) |> should.equal(["Поражение"])
}

pub fn summary_false_boolean_is_omitted_test() {
  let row = types.ObjectValue([#("affected", types.BooleanValue(False))])
  summary_of(row, ["affected"]) |> should.equal([])
}

pub fn summary_array_shows_title_and_count_test() {
  let row =
    types.ObjectValue([
      #(
        "lesions",
        types.ArrayValue([types.ObjectValue([]), types.ObjectValue([])]),
      ),
    ])
  summary_of(row, ["lesions"]) |> should.equal(["Очаги: 2"])
}

pub fn summary_empty_array_is_omitted_test() {
  let row = types.ObjectValue([#("lesions", types.ArrayValue([]))])
  summary_of(row, ["lesions"]) |> should.equal([])
}

pub fn summary_default_is_scalar_fields_in_schema_order_test() {
  let row =
    types.ObjectValue([
      #("label", types.StringValue("Диафрагма")),
      #("zone_id", types.IntegerValue(4)),
      #("affected", types.BooleanValue(True)),
      #("lesions", types.ArrayValue([types.ObjectValue([])])),
    ])
  // Row order is label, zone_id — schema order is zone_id, label. Asserting
  // schema order here also catches an implementation that iterates the row's
  // own value order instead of the resolved schema's properties.
  // Default also omits `lesions` — the default set is scalar fields only.
  summary_of(row, []) |> should.equal(["4", "Диафрагма", "Поражение"])
}

// --- password-field-masking delta ---

pub fn summary_masks_password_field_test() {
  let row = types.ObjectValue([#("secret", types.StringValue("hunter2"))])
  summary_of(row, ["secret"]) |> should.equal(["••••••••"])
}

pub fn summary_omits_empty_password_field_test() {
  let row = types.ObjectValue([#("secret", types.StringValue(""))])
  summary_of(row, ["secret"]) |> should.equal([])
}

pub fn summary_masks_password_field_holding_array_value_test() {
  // A password-masked field whose stored value is an ArrayValue (reachable
  // e.g. through mismatched `initial-values`) must still mask rather than
  // fall into the array-count arm, which would disclose the length.
  let row =
    types.ObjectValue([
      #(
        "secret",
        types.ArrayValue([
          types.StringValue("a"),
          types.StringValue("b"),
          types.StringValue("c"),
        ]),
      ),
    ])
  summary_of(row, ["secret"]) |> should.equal(["••••••••"])
}

// --- ui-schema hint resolution (fix round 1, item 1) ---

pub fn summary_ui_widget_password_masks_non_format_field_test() {
  let assert Ok(ui) =
    ui_parser.parse(
      "{\"zones\":{\"items\":{\"label\":{\"ui:widget\":\"password\"}}}}",
    )
  let row = types.ObjectValue([#("label", types.StringValue("hunter2"))])
  summary_of_with_ui(ui, row, ["label"]) |> should.equal(["••••••••"])
}

pub fn summary_ui_title_overrides_schema_title_test() {
  let assert Ok(ui) =
    ui_parser.parse(
      "{\"zones\":{\"items\":{\"affected\":{\"ui:title\":\"Задействовано\"}}}}",
    )
  let row = types.ObjectValue([#("affected", types.BooleanValue(True))])
  summary_of_with_ui(ui, row, ["affected"]) |> should.equal(["Задействовано"])
}

// --- untyped-property default-set exclusion (fix round 1, item 3) ---

pub fn summary_untyped_array_property_excluded_from_default_test() {
  let row =
    types.ObjectValue([
      #("zone_id", types.IntegerValue(4)),
      #(
        "tags",
        types.ArrayValue([types.StringValue("a"), types.StringValue("b")]),
      ),
    ])
  // `tags` declares no `type`, so `scalar_names` alone cannot exclude it —
  // the default set additionally checks the row's own value shape.
  summary_of(row, []) |> should.equal(["4"])
}

pub fn summary_untyped_array_property_shows_count_when_explicit_test() {
  let row =
    types.ObjectValue([
      #(
        "tags",
        types.ArrayValue([types.StringValue("a"), types.StringValue("b")]),
      ),
    ])
  summary_of(row, ["tags"]) |> should.equal(["Метки: 2"])
}

// --- ObjectValue omission deviation, guarded (fix round 1, item 5) ---

pub fn summary_object_value_contributes_nothing_test() {
  // Deliberate deviation from the design table (flagged at review): an
  // ObjectValue field is omitted outright rather than routed through
  // `display_value`, which would render the unset dash. See the task-6
  // report / PR description.
  let row =
    types.ObjectValue([
      #("contact", types.ObjectValue([#("phone", types.StringValue("123"))])),
    ])
  summary_of(row, ["contact"]) |> should.equal([])
}

pub fn summary_object_typed_property_excluded_from_default_test() {
  let row =
    types.ObjectValue([
      #("zone_id", types.IntegerValue(4)),
      #("contact", types.ObjectValue([#("phone", types.StringValue("123"))])),
    ])
  summary_of(row, []) |> should.equal(["4"])
}

// --- password decision hoisted above the value-shape case (fix round 2) ---

pub fn summary_masks_password_field_holding_true_boolean_test() {
  let row = types.ObjectValue([#("secret", types.BooleanValue(True))])
  summary_of(row, ["secret"]) |> should.equal(["••••••••"])
}

pub fn summary_masks_password_field_holding_false_boolean_test() {
  // `False` must mask exactly like `True` — omitting one and masking the
  // other would leak the stored bit through presence/absence alone.
  let row = types.ObjectValue([#("secret", types.BooleanValue(False))])
  summary_of(row, ["secret"]) |> should.equal(["••••••••"])
}

pub fn summary_ui_widget_password_masks_boolean_value_test() {
  let assert Ok(ui) =
    ui_parser.parse(
      "{\"zones\":{\"items\":{\"label\":{\"ui:widget\":\"password\"}}}}",
    )
  let row = types.ObjectValue([#("label", types.BooleanValue(True))])
  summary_of_with_ui(ui, row, ["label"]) |> should.equal(["••••••••"])
}

pub fn summary_omits_null_password_field_test() {
  let row = types.ObjectValue([#("secret", types.NullValue)])
  summary_of(row, ["secret"]) |> should.equal([])
}

pub fn summary_omits_empty_array_password_field_test() {
  let row = types.ObjectValue([#("secret", types.ArrayValue([]))])
  summary_of(row, ["secret"]) |> should.equal([])
}
