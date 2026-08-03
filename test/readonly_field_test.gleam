// Tests for the read-only ("review") rendering path.
//
// Exercises the whole-form switch in `view.view` when `FormModel.read_only`
// is True: scalar label→value rows, boolean Yes/No, oneOf human labels,
// nested object groups, and arrays of flat objects rendered as tables — plus
// the regression guard that edit mode still renders inputs.

import formosh/form/model.{FormModel}
import formosh/form/view
import formosh/schema/parser
import formosh/schema/types
import formosh/schema/ui_parser
import gleam/list
import gleam/string
import gleeunit/should
import lustre/element

fn sample_schema() -> types.JsonSchema {
  let json =
    "{
      \"type\": \"object\",
      \"title\": \"Patient\",
      \"properties\": {
        \"name\": { \"type\": \"string\", \"title\": \"Full name\" },
        \"active\": { \"type\": \"boolean\", \"title\": \"Active\" },
        \"severity\": {
          \"type\": \"string\",
          \"title\": \"Severity\",
          \"oneOf\": [
            { \"const\": \"lo\", \"title\": \"Low\" },
            { \"const\": \"hi\", \"title\": \"High\" }
          ]
        },
        \"address\": {
          \"type\": \"object\",
          \"title\": \"Address\",
          \"properties\": {
            \"city\": { \"type\": \"string\", \"title\": \"City\" }
          }
        },
        \"lesions\": {
          \"type\": \"array\",
          \"title\": \"Lesions\",
          \"items\": {
            \"type\": \"object\",
            \"properties\": {
              \"side\": { \"type\": \"string\", \"title\": \"Side\" },
              \"size\": { \"type\": \"integer\", \"title\": \"Size\" }
            }
          }
        }
      }
    }"
  let assert Ok(schema) = parser.parse_schema(json)
  schema
}

fn sample_values() -> types.Value {
  types.ObjectValue([
    #("name", types.StringValue("Jane Doe")),
    #("active", types.BooleanValue(True)),
    #("severity", types.StringValue("hi")),
    #("address", types.ObjectValue([#("city", types.StringValue("Berlin"))])),
    #(
      "lesions",
      types.ArrayValue([
        types.ObjectValue([
          #("side", types.StringValue("left")),
          #("size", types.IntegerValue(3)),
        ]),
        types.ObjectValue([
          #("side", types.StringValue("right")),
          #("size", types.IntegerValue(5)),
        ]),
      ]),
    ),
  ])
}

fn render(read_only: Bool) -> String {
  FormModel(
    ..model.init(sample_schema()),
    values: sample_values(),
    read_only: read_only,
  )
  |> view.view
  |> element.to_string
}

pub fn readonly_view_renders_scalar_rows_test() {
  let html = render(True)
  html |> string.contains("part=\"readonly-value\"") |> should.be_true
  html |> string.contains("Jane Doe") |> should.be_true
}

pub fn readonly_view_renders_boolean_as_yes_test() {
  render(True) |> string.contains("Yes") |> should.be_true
}

pub fn readonly_view_renders_oneof_label_not_code_test() {
  // Stored value is the code "hi"; the summary must show the oneOf title.
  render(True) |> string.contains("High") |> should.be_true
}

pub fn readonly_view_renders_object_group_test() {
  let html = render(True)
  html |> string.contains("part=\"readonly-group\"") |> should.be_true
  html |> string.contains("Berlin") |> should.be_true
}

pub fn readonly_view_renders_array_of_objects_as_table_test() {
  let html = render(True)
  html |> string.contains("part=\"readonly-table\"") |> should.be_true
  html |> string.contains("part=\"readonly-th\"") |> should.be_true
  html |> string.contains("left") |> should.be_true
  html |> string.contains("right") |> should.be_true
}

pub fn readonly_table_hides_uischema_hidden_columns_test() {
  // A column hidden via the parallel UiSchema (`ui:widget: "hidden"`, not the
  // deprecated x-widget) must be dropped from the read-only table — header
  // and every cell — just like every other field honours hidden widgets.
  let ui_json =
    "{ \"lesions\": { \"items\": { \"size\": { \"ui:widget\": \"hidden\" } } } }"
  let assert Ok(ui) = ui_parser.parse(ui_json)
  let html =
    FormModel(
      ..model.init(sample_schema()),
      ui_schema: ui,
      values: sample_values(),
      read_only: True,
    )
    |> view.view
    |> element.to_string
  html |> string.contains("part=\"readonly-table\"") |> should.be_true
  html |> string.contains("Side") |> should.be_true
  html |> string.contains("Size") |> should.be_false
}

pub fn readonly_view_hides_submit_and_inputs_test() {
  let html = render(True)
  // No footer (Submit/Reset) and no editable inputs in review mode.
  html |> string.contains("formosh-submit") |> should.be_false
  html |> string.contains("part=\"input\"") |> should.be_false
}

pub fn readonly_view_renders_integer_oneof_label_test() {
  // Non-string oneOf consts must resolve to their title too (int key parity).
  let json =
    "{ \"type\": \"object\", \"properties\": { \"grade\": { \"type\": \"integer\", \"title\": \"Grade\", \"oneOf\": [ { \"const\": 1, \"title\": \"First\" }, { \"const\": 2, \"title\": \"Second\" } ] } } }"
  let assert Ok(schema) = parser.parse_schema(json)
  let html =
    FormModel(
      ..model.init(schema),
      values: types.ObjectValue([#("grade", types.IntegerValue(2))]),
      read_only: True,
    )
    |> view.view
    |> element.to_string
  html |> string.contains("Second") |> should.be_true
}

pub fn readonly_table_falls_back_to_groups_for_conditional_items_test() {
  // Item-level conditionals can't be a fixed-column table; the array falls back
  // to per-row groups, which resolve the then-branch field for each row.
  let json =
    "{ \"type\": \"object\", \"properties\": { \"rows\": { \"type\": \"array\", \"items\": { \"type\": \"object\", \"properties\": { \"kind\": { \"type\": \"string\" } }, \"allOf\": [ { \"if\": { \"properties\": { \"kind\": { \"const\": \"x\" } } }, \"then\": { \"properties\": { \"extra\": { \"type\": \"string\", \"title\": \"Extra\" } } } } ] } } } }"
  let assert Ok(schema) = parser.parse_schema(json)
  let html =
    FormModel(
      ..model.init(schema),
      values: types.ObjectValue([
        #(
          "rows",
          types.ArrayValue([
            types.ObjectValue([
              #("kind", types.StringValue("x")),
              #("extra", types.StringValue("shown")),
            ]),
          ]),
        ),
      ]),
      read_only: True,
    )
    |> view.view
    |> element.to_string
  html |> string.contains("part=\"readonly-table\"") |> should.be_false
  html |> string.contains("shown") |> should.be_true
}

pub fn edit_view_still_renders_inputs_test() {
  // Regression guard: the read_only switch must not affect edit mode.
  let html = render(False)
  html |> string.contains("part=\"readonly-value\"") |> should.be_false
  html |> string.contains("formosh-submit") |> should.be_true
}

// --- Password masking (review mode) ---
//
// Two independent routes flag a field as a password: schema `format:
// "password"` and `ui:widget: "password"`. Both must be masked wherever a
// leaf value renders in review mode — the plain scalar row, a table cell,
// and a scalar array item.

fn password_schema() -> types.JsonSchema {
  let json =
    "{
      \"type\": \"object\",
      \"properties\": {
        \"email\": { \"type\": \"string\", \"title\": \"Email\" },
        \"secret\": {
          \"type\": \"string\",
          \"format\": \"password\",
          \"title\": \"Password\"
        },
        \"long_secret\": {
          \"type\": \"string\",
          \"format\": \"password\",
          \"title\": \"Long password\"
        },
        \"blank_secret\": {
          \"type\": \"string\",
          \"format\": \"password\",
          \"title\": \"Unset password\"
        }
      }
    }"
  let assert Ok(schema) = parser.parse_schema(json)
  schema
}

fn password_values() -> types.Value {
  types.ObjectValue([
    #("email", types.StringValue("a@b.com")),
    #("secret", types.StringValue("hunter2")),
    #(
      "long_secret",
      types.StringValue("0123456789012345678901234567890123456789"),
    ),
    #("blank_secret", types.StringValue("")),
  ])
}

fn render_password_review() -> String {
  let m =
    FormModel(
      ..model.init(password_schema()),
      values: password_values(),
      read_only: True,
    )
  view.view(m) |> element.to_string
}

fn count_occurrences(haystack: String, needle: String) -> Int {
  let parts = string.split(haystack, needle)
  list.length(parts) - 1
}

pub fn password_is_masked_in_review_test() {
  let html = render_password_review()
  should.be_true(string.contains(html, "••••••••"))
  should.be_false(string.contains(html, "hunter2"))
}

// A length-proportional mask would leak the password length, so a 7-char and
// a 40-char value must render identically.
pub fn password_mask_does_not_track_length_test() {
  let html = render_password_review()
  should.be_false(string.contains(html, "0123456789"))
  should.equal(count_occurrences(html, "••••••••"), 2)
}

pub fn empty_password_renders_dash_not_mask_test() {
  render_password_review()
  |> string.contains("—")
  |> should.be_true
}

pub fn non_password_values_are_untouched_test() {
  render_password_review()
  |> string.contains("a@b.com")
  |> should.be_true
}

fn widget_password_schema() -> types.JsonSchema {
  let json =
    "{
      \"type\": \"object\",
      \"properties\": {
        \"email\": { \"type\": \"string\", \"title\": \"Email\" },
        \"secret_widget\": {
          \"type\": \"string\",
          \"title\": \"Widget password\"
        }
      }
    }"
  let assert Ok(schema) = parser.parse_schema(json)
  schema
}

// `secret_widget` carries no `format` at all — only a genuine `UiSchema`
// `ui:widget: "password"` entry marks it. This exercises the
// `UiSchema -> ui_resolver.resolve_hints -> CustomWidget("password")` chain
// end to end, distinct from every other widget test in this suite (which
// seeds `render_hints.widget`, the deprecated x-widget lane, directly).
pub fn widget_route_password_is_masked_in_review_test() {
  let ui_json = "{ \"secret_widget\": { \"ui:widget\": \"password\" } }"
  let assert Ok(ui) = ui_parser.parse(ui_json)
  let html =
    FormModel(
      ..model.init(widget_password_schema()),
      ui_schema: ui,
      values: types.ObjectValue([
        #("email", types.StringValue("a@b.com")),
        #("secret_widget", types.StringValue("hunter2")),
      ]),
      read_only: True,
    )
    |> view.view
    |> element.to_string
  html |> string.contains("••••••••") |> should.be_true
  html |> string.contains("hunter2") |> should.be_false
  html |> string.contains("a@b.com") |> should.be_true
}

fn password_table_schema() -> types.JsonSchema {
  let json =
    "{
      \"type\": \"object\",
      \"properties\": {
        \"accounts\": {
          \"type\": \"array\",
          \"title\": \"Accounts\",
          \"items\": {
            \"type\": \"object\",
            \"properties\": {
              \"username\": { \"type\": \"string\", \"title\": \"Username\" },
              \"secret\": {
                \"type\": \"string\",
                \"format\": \"password\",
                \"title\": \"Password\"
              }
            }
          }
        }
      }
    }"
  let assert Ok(schema) = parser.parse_schema(json)
  schema
}

pub fn password_column_is_masked_in_readonly_table_test() {
  let html =
    FormModel(
      ..model.init(password_table_schema()),
      values: types.ObjectValue([
        #(
          "accounts",
          types.ArrayValue([
            types.ObjectValue([
              #("username", types.StringValue("alice")),
              #("secret", types.StringValue("hunter2")),
            ]),
          ]),
        ),
      ]),
      read_only: True,
    )
    |> view.view
    |> element.to_string
  html |> string.contains("part=\"readonly-table\"") |> should.be_true
  html |> string.contains("••••••••") |> should.be_true
  html |> string.contains("hunter2") |> should.be_false
  // Sibling non-password column must still show its real value — proves the
  // password column alone is masked, not the whole row/table.
  html |> string.contains("alice") |> should.be_true
}

fn password_array_items_schema() -> types.JsonSchema {
  let json =
    "{
      \"type\": \"object\",
      \"properties\": {
        \"nickname\": { \"type\": \"string\", \"title\": \"Nickname\" },
        \"recovery_codes\": {
          \"type\": \"array\",
          \"title\": \"Recovery codes\",
          \"items\": { \"type\": \"string\", \"format\": \"password\" }
        }
      }
    }"
  let assert Ok(schema) = parser.parse_schema(json)
  schema
}

// --- Regression guard: empty-string dash vs. oneOf label (non-password) ---
//
// Masking an unset password requires treating `Some(StringValue(""))` as
// "show the dash" ahead of the oneOf label lookup (see
// `empty_password_renders_dash_not_mask_test` above). That must stay scoped
// to password fields — a plain (non-password) oneOf branch whose `const` is
// the empty string should still show its title, exactly as it did before
// password masking existed.
pub fn readonly_view_renders_empty_const_oneof_label_test() {
  let json =
    "{
      \"type\": \"object\",
      \"properties\": {
        \"status\": {
          \"type\": \"string\",
          \"title\": \"Status\",
          \"oneOf\": [
            { \"const\": \"\", \"title\": \"None selected\" },
            { \"const\": \"done\", \"title\": \"Done\" }
          ]
        }
      }
    }"
  let assert Ok(schema) = parser.parse_schema(json)
  let html =
    FormModel(
      ..model.init(schema),
      values: types.ObjectValue([#("status", types.StringValue(""))]),
      read_only: True,
    )
    |> view.view
    |> element.to_string
  html |> string.contains("None selected") |> should.be_true
}

pub fn password_array_items_are_masked_test() {
  let html =
    FormModel(
      ..model.init(password_array_items_schema()),
      values: types.ObjectValue([
        #("nickname", types.StringValue("bob")),
        #(
          "recovery_codes",
          types.ArrayValue([
            types.StringValue("hunter2"),
            types.StringValue("swordfish"),
          ]),
        ),
      ]),
      read_only: True,
    )
    |> view.view
    |> element.to_string
  html |> string.contains("••••••••") |> should.be_true
  html |> string.contains("hunter2") |> should.be_false
  html |> string.contains("swordfish") |> should.be_false
  // Sibling non-password field must still show its real value.
  html |> string.contains("bob") |> should.be_true
}
