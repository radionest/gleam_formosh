/// Visibility walker tests (issue #23).
///
/// The walker maps `JsonSchema` + `UiSchema` + current values into the set of
/// canonical path keys whose fields are suppressed from the UI. These keys
/// are used by `model.is_valid_for_submit` / `model.hidden_errors` to decide
/// whether a blocked submit is caused only by errors a user cannot see.
import formosh/form/visibility
import formosh/schema/types
import formosh/schema/ui_schema
import gleam/option.{None, Some}
import gleam/set
import gleeunit/should

fn schema_with(
  props: List(#(String, types.SchemaProperty)),
  required: List(String),
) -> types.JsonSchema {
  types.JsonSchema(
    title: None,
    description: None,
    field_type: types.ObjectType,
    properties: props,
    required: required,
    defs: None,
    conditionals: [],
    string_constraints: None,
    number_constraints: None,
  )
}

fn hidden_widget_hints() -> types.RenderHints {
  types.RenderHints(..types.empty_hints(), widget: Some(types.HiddenWidget))
}

fn string_prop() -> types.SchemaProperty {
  types.SchemaProperty(
    ..types.empty_property(),
    field_type: Some(types.StringType),
  )
}

fn hidden_string_prop() -> types.SchemaProperty {
  types.SchemaProperty(..string_prop(), render_hints: hidden_widget_hints())
}

fn object_prop(
  properties: List(#(String, types.SchemaProperty)),
  required: List(String),
) -> types.SchemaProperty {
  types.SchemaProperty(
    ..types.empty_property(),
    field_type: Some(types.ObjectType),
    properties: Some(properties),
    required: required,
  )
}

fn array_prop(items: types.SchemaProperty) -> types.SchemaProperty {
  types.SchemaProperty(
    ..types.empty_property(),
    field_type: Some(types.ArrayType),
    items: Some(items),
  )
}

fn readonly_string_prop() -> types.SchemaProperty {
  types.SchemaProperty(..string_prop(), read_only: True)
}

// Top-level scalar with `x-widget: "hidden"` → its canonical key is the only
// member of the invisible set. Mirrors issue #23 case 1.
pub fn top_level_hidden_test() {
  let schema = schema_with([#("x", hidden_string_prop())], ["x"])
  let result =
    visibility.invisible_paths(
      schema,
      ui_schema.empty_ui_schema(),
      types.ObjectValue([]),
      False,
    )
  result |> should.equal(set.from_list(["x"]))
}

// Hidden object pulls every declared child into the invisible set, even
// when the value tree doesn't have the child yet — required-error keys
// land on the child path regardless of value presence. Mirrors case 2.
pub fn hidden_object_pulls_children_test() {
  let inner = object_prop([#("y", string_prop()), #("z", string_prop())], ["y"])
  let hidden_inner =
    types.SchemaProperty(..inner, render_hints: hidden_widget_hints())
  let schema = schema_with([#("x", hidden_inner)], [])
  let result =
    visibility.invisible_paths(
      schema,
      ui_schema.empty_ui_schema(),
      types.ObjectValue([]),
      False,
    )
  result |> should.equal(set.from_list(["x", "x.y", "x.z"]))
}

// readOnly + show_readonly_fields=False suppresses the field analogously to
// hidden. Mirrors issue #23 case 3.
pub fn readonly_suppressed_when_show_false_test() {
  let schema = schema_with([#("x", readonly_string_prop())], ["x"])
  let result =
    visibility.invisible_paths(
      schema,
      ui_schema.empty_ui_schema(),
      types.ObjectValue([]),
      False,
    )
  result |> should.equal(set.from_list(["x"]))
}

// Flip show_readonly_fields → readOnly is visible again, set is empty.
pub fn readonly_visible_when_show_true_test() {
  let schema = schema_with([#("x", readonly_string_prop())], ["x"])
  let result =
    visibility.invisible_paths(
      schema,
      ui_schema.empty_ui_schema(),
      types.ObjectValue([]),
      True,
    )
  result |> should.equal(set.new())
}

// Hidden array enumerates every present row plus the row's required leaves
// — the validator can produce errors for any of those keys, and they should
// all be reported as invisible.
pub fn hidden_array_with_items_test() {
  let item_schema = object_prop([#("name", string_prop())], ["name"])
  let hidden_array =
    types.SchemaProperty(
      ..array_prop(item_schema),
      render_hints: hidden_widget_hints(),
    )
  let schema = schema_with([#("items", hidden_array)], [])
  let values =
    types.ObjectValue([
      #(
        "items",
        types.ArrayValue([types.ObjectValue([]), types.ObjectValue([])]),
      ),
    ])
  let result =
    visibility.invisible_paths(
      schema,
      ui_schema.empty_ui_schema(),
      values,
      False,
    )
  result
  |> should.equal(
    set.from_list([
      "items", "items.[0]", "items.[0].name", "items.[1]", "items.[1].name",
    ]),
  )
}

// readOnly OR-merges from parent to child (mirrors `make_child_ctx`): a
// readOnly object suppresses every descendant when show_readonly_fields is
// off, even when the child itself does not declare readOnly.
pub fn readonly_object_pulls_children_test() {
  let inner = object_prop([#("name", string_prop())], ["name"])
  let readonly_inner = types.SchemaProperty(..inner, read_only: True)
  let schema = schema_with([#("x", readonly_inner)], [])
  let result =
    visibility.invisible_paths(
      schema,
      ui_schema.empty_ui_schema(),
      types.ObjectValue([]),
      False,
    )
  result |> should.equal(set.from_list(["x", "x.name"]))
}

// UiSchema's `ui:widget: "hidden"` is the primary suppression channel
// (the `x-widget` extension is deprecated fallback). Verifies the walker
// reads the merged widget from `ui_resolver.resolve_hints`, not the raw
// schema's `render_hints` field.
pub fn ui_schema_hidden_widget_test() {
  let plain = string_prop()
  let schema = schema_with([#("x", plain)], ["x"])
  let ui =
    ui_schema.UiSchema(
      properties: [
        #(
          "x",
          ui_schema.UiProperty(
            ..ui_schema.empty_ui_property(),
            widget: Some(types.HiddenWidget),
          ),
        ),
      ],
      order: None,
    )
  let result =
    visibility.invisible_paths(schema, ui, types.ObjectValue([]), False)
  result |> should.equal(set.from_list(["x"]))
}

// Visible siblings of a hidden field are not in the invisible set —
// regression guard for the walker accidentally hiding too much.
pub fn visible_sibling_not_invisible_test() {
  let schema =
    schema_with([#("a", hidden_string_prop()), #("b", string_prop())], ["a"])
  let result =
    visibility.invisible_paths(
      schema,
      ui_schema.empty_ui_schema(),
      types.ObjectValue([]),
      False,
    )
  result |> should.equal(set.from_list(["a"]))
}
