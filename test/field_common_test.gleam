import formosh/fields/field_common
import formosh/form/model
import formosh/form/path.{PropertySegment}
import formosh/schema/types
import formosh/schema/ui_schema
import formosh/validation/error
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import lustre/element

pub fn render_required_marker_true_test() {
  let html = element.to_string(field_common.render_required_marker(True))
  html |> string.contains("formosh-required") |> should.be_true
  html |> string.contains("part=\"required\"") |> should.be_true
  html |> string.contains("*") |> should.be_true
}

pub fn render_help_text_has_part_attribute_test() {
  let property =
    types.SchemaProperty(
      ..types.empty_property(),
      description: Some("Enter your name"),
    )
  let html =
    field_common.render_help_text(property, types.empty_hints())
    |> element.to_string

  html |> string.contains("part=\"help\"") |> should.be_true
  html |> string.contains("Enter your name") |> should.be_true
}

pub fn render_field_errors_has_part_attributes_test() {
  let errors = [
    error.ValidationError(field: [], message: "required", rule: "required"),
  ]
  let html =
    field_common.render_field_errors(errors)
    |> element.to_string

  html |> string.contains("part=\"errors\"") |> should.be_true
  html |> string.contains("part=\"error\"") |> should.be_true
  html |> string.contains("required") |> should.be_true
}

pub fn render_required_marker_false_is_empty_test() {
  field_common.render_required_marker(False)
  |> element.to_string
  |> should.equal("")
}

pub fn render_container_label_uses_title_test() {
  let property =
    types.SchemaProperty(..types.empty_property(), title: Some("Lesions"))
  let html =
    field_common.render_container_label(
      field_name: "lesions",
      property: property,
      is_required: False,
      css_class: "array-label",
      hints: types.empty_hints(),
    )
    |> element.to_string

  html
  |> string.contains("<label class=\"array-label\">Lesions")
  |> should.be_true
  html |> string.contains("for=") |> should.be_false
}

pub fn render_container_label_formats_fallback_test() {
  let property = types.SchemaProperty(..types.empty_property(), title: None)
  let html =
    field_common.render_container_label(
      field_name: "user_data",
      property: property,
      is_required: False,
      css_class: "object-label",
      hints: types.empty_hints(),
    )
    |> element.to_string

  html
  |> string.contains("<label class=\"object-label\">User data")
  |> should.be_true
}

pub fn render_container_label_shows_required_marker_test() {
  let property =
    types.SchemaProperty(..types.empty_property(), title: Some("Lesions"))
  let html =
    field_common.render_container_label(
      field_name: "lesions",
      property: property,
      is_required: True,
      css_class: "array-label",
      hints: types.empty_hints(),
    )
    |> element.to_string

  html |> string.contains("formosh-required") |> should.be_true
}

// --- make_child_ctx fixtures and tests ---

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

fn parent_ctx_with(
  is_required: Bool,
  is_disabled: Bool,
  is_readonly: Bool,
) -> field_common.FieldRenderCtx {
  field_common.FieldRenderCtx(
    path: path.from_field_name("parent"),
    property: types.empty_property(),
    value: None,
    is_required: is_required,
    is_disabled: is_disabled,
    is_readonly: is_readonly,
    hints: types.empty_hints(),
  )
}

fn child_prop_with_readonly(read_only: Bool) -> types.SchemaProperty {
  types.SchemaProperty(..types.empty_property(), read_only: read_only)
}

// readonly parent → child readonly, even when child_prop.read_only=False.
pub fn make_child_ctx_inherits_readonly_from_parent_test() {
  let parent = parent_ctx_with(False, False, True)
  let child_path = [PropertySegment("parent"), PropertySegment("child")]
  let child =
    field_common.make_child_ctx(
      parent: parent,
      model: model.init(empty_schema()),
      path: child_path,
      property: child_prop_with_readonly(False),
      is_required: False,
    )
  child.is_readonly |> should.be_true
}

// disabled parent → child disabled (via ..parent record spread).
pub fn make_child_ctx_inherits_disabled_from_parent_test() {
  let parent = parent_ctx_with(False, True, False)
  let child_path = [PropertySegment("parent"), PropertySegment("child")]
  let child =
    field_common.make_child_ctx(
      parent: parent,
      model: model.init(empty_schema()),
      path: child_path,
      property: types.empty_property(),
      is_required: False,
    )
  child.is_disabled |> should.be_true
}

// is_required comes from the argument — parent.is_required is ignored.
pub fn make_child_ctx_required_comes_from_argument_not_parent_test() {
  let parent = parent_ctx_with(True, False, False)
  let child_path = [PropertySegment("parent"), PropertySegment("child")]
  let child =
    field_common.make_child_ctx(
      parent: parent,
      model: model.init(empty_schema()),
      path: child_path,
      property: types.empty_property(),
      is_required: False,
    )
  child.is_required |> should.be_false
}

// --- make_field_ctx / make_child_ctx + UiSchema hint merge ---

fn model_with_ui(ui: ui_schema.UiSchema) -> model.FormModel {
  let base = model.init(empty_schema())
  model.FormModel(..base, ui_schema: ui)
}

// `ui:disabled: true` OR-merges with the caller-supplied `is_disabled`.
// Even when the caller passes `is_disabled=False`, hints.disabled wins.
pub fn make_field_ctx_or_merges_disabled_from_hints_test() {
  let ui =
    ui_schema.UiSchema(
      properties: [
        #(
          "f",
          ui_schema.UiProperty(
            ..ui_schema.empty_ui_property(),
            disabled: Some(True),
          ),
        ),
      ],
      order: None,
      layout: None,
    )
  let m = model_with_ui(ui)
  let ctx =
    field_common.make_field_ctx(
      model: m,
      path: path.from_field_name("f"),
      property: types.empty_property(),
      is_required: False,
      is_disabled: False,
      is_readonly: False,
    )
  ctx.is_disabled |> should.be_true
}

// Same OR-merge logic for `is_readonly`.
pub fn make_field_ctx_or_merges_readonly_from_hints_test() {
  let ui =
    ui_schema.UiSchema(
      properties: [
        #(
          "f",
          ui_schema.UiProperty(
            ..ui_schema.empty_ui_property(),
            readonly: Some(True),
          ),
        ),
      ],
      order: None,
      layout: None,
    )
  let m = model_with_ui(ui)
  let ctx =
    field_common.make_field_ctx(
      model: m,
      path: path.from_field_name("f"),
      property: types.empty_property(),
      is_required: False,
      is_disabled: False,
      is_readonly: False,
    )
  ctx.is_readonly |> should.be_true
}

// `ui:disabled: true` on a child propagates even when the parent isn't
// disabled — the merge in make_child_ctx ORs parent's flag with the
// child's hint.
pub fn make_child_ctx_or_merges_hints_disabled_test() {
  let ui =
    ui_schema.UiSchema(
      properties: [
        #(
          "parent",
          ui_schema.UiProperty(..ui_schema.empty_ui_property(), properties: [
            #(
              "child",
              ui_schema.UiProperty(
                ..ui_schema.empty_ui_property(),
                disabled: Some(True),
              ),
            ),
          ]),
        ),
      ],
      order: None,
      layout: None,
    )
  let m = model_with_ui(ui)
  let parent = parent_ctx_with(False, False, False)
  let child_path = [PropertySegment("parent"), PropertySegment("child")]
  let child =
    field_common.make_child_ctx(
      parent: parent,
      model: m,
      path: child_path,
      property: types.empty_property(),
      is_required: False,
    )
  child.is_disabled |> should.be_true
}

// value is re-extracted from model by child_path — parent.value is dropped.
pub fn make_child_ctx_value_extracted_from_child_path_test() {
  let parent_path = path.from_field_name("parent")
  let child_path = [PropertySegment("parent"), PropertySegment("child")]
  let values =
    types.ObjectValue([
      #(
        "parent",
        types.ObjectValue([#("child", types.StringValue("child-value"))]),
      ),
    ])
  let base = model.init(empty_schema())
  let m = model.FormModel(..base, values: values)
  let parent =
    field_common.FieldRenderCtx(
      path: parent_path,
      property: types.empty_property(),
      value: Some(types.StringValue("parent-value")),
      is_required: False,
      is_disabled: False,
      is_readonly: False,
      hints: types.empty_hints(),
    )
  let child =
    field_common.make_child_ctx(
      parent: parent,
      model: m,
      path: child_path,
      property: types.empty_property(),
      is_required: False,
    )
  child.value |> should.equal(Some(types.StringValue("child-value")))
}
