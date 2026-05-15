/// Boolean field renderer with multiple presentation options.
///
/// This module provides different ways to render boolean fields including
/// radio buttons (Yes/No), checkboxes, and toggle switches. The default
/// render function uses radio buttons for better accessibility and clarity.
import formosh/fields/field_common.{type FieldRenderCtx}
import formosh/form/model.{type FormMsg, UpdateFieldPath}
import formosh/form/path
import formosh/schema/types
import gleam/option
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// Render a boolean field as radio buttons (Yes/No).
///
/// ## Alternative Renderers
/// - `render_as_checkbox`: Single checkbox for true/false
/// - `render_as_toggle`: Toggle switch interface
pub fn render(ctx: FieldRenderCtx) -> Element(FormMsg) {
  render_as_radio(ctx)
}

/// Render boolean field as Yes/No radio button group.
///
/// Readonly state has no native HTML mapping for radio inputs, so it is
/// folded into the disabled attribute locally — same pattern as
/// `string_field.render_radio_group` and `render_select`.
fn render_as_radio(ctx: FieldRenderCtx) -> Element(FormMsg) {
  let field_name = path.get_field_name(ctx.path)
  let field_id = path.to_string(ctx.path)
  let yes_id = field_id <> "_yes"
  let no_id = field_id <> "_no"
  let is_true = field_common.extract_boolean_value(ctx.value)
  let has_value = option.is_some(ctx.value)
  let effective_disabled = ctx.is_disabled || ctx.is_readonly

  html.div(
    [
      attribute.class("formosh-field-wrapper"),
      attribute.attribute("part", "field-wrapper"),
    ],
    [
      field_common.render_label(field_name, ctx.property, ctx.is_required),
      html.div(
        [
          attribute.class("formosh-radio-group formosh-boolean"),
          attribute.attribute("part", "radio-group boolean"),
        ],
        [
          html.div(
            [
              attribute.class("formosh-radio-item"),
              attribute.attribute("part", "radio-item"),
            ],
            [
              html.input([
                attribute.type_("radio"),
                attribute.id(yes_id),
                attribute.name(field_id),
                attribute.value("true"),
                attribute.checked(has_value && is_true),
                attribute.required(ctx.is_required),
                attribute.disabled(effective_disabled),
                event.on_click(UpdateFieldPath(
                  ctx.path,
                  types.BooleanValue(True),
                )),
              ]),
              html.label([attribute.for(yes_id)], [html.text("Yes")]),
            ],
          ),
          html.div(
            [
              attribute.class("formosh-radio-item"),
              attribute.attribute("part", "radio-item"),
            ],
            [
              html.input([
                attribute.type_("radio"),
                attribute.id(no_id),
                attribute.name(field_id),
                attribute.value("false"),
                attribute.checked(has_value && !is_true),
                attribute.required(ctx.is_required),
                attribute.disabled(effective_disabled),
                event.on_click(UpdateFieldPath(
                  ctx.path,
                  types.BooleanValue(False),
                )),
              ]),
              html.label([attribute.for(no_id)], [html.text("No")]),
            ],
          ),
        ],
      ),
      field_common.render_help_text(ctx.property),
    ],
  )
}

/// Render boolean field as a single checkbox.
///
/// Alternative boolean renderer that uses a traditional checkbox input.
/// Compact but less explicit about the false state than radio buttons.
pub fn render_as_checkbox(ctx: FieldRenderCtx) -> Element(FormMsg) {
  let current_value = field_common.extract_boolean_value(ctx.value)

  let field_name = path.get_field_name(ctx.path)
  let field_id = path.to_string(ctx.path)

  html.div(
    [
      attribute.class("formosh-field-wrapper formosh-checkbox-wrapper"),
      attribute.attribute("part", "field-wrapper checkbox-wrapper"),
    ],
    [
      html.div(
        [
          attribute.class("formosh-checkbox-group"),
          attribute.attribute("part", "checkbox-group"),
        ],
        [
          html.input([
            attribute.type_("checkbox"),
            attribute.id(field_id),
            attribute.name(field_id),
            attribute.checked(current_value),
            attribute.required(ctx.is_required),
            attribute.disabled(ctx.is_disabled),
            event.on_click(UpdateFieldPath(
              ctx.path,
              types.BooleanValue(!current_value),
            )),
          ]),
          field_common.render_label(field_name, ctx.property, ctx.is_required),
        ],
      ),
      field_common.render_help_text(ctx.property),
    ],
  )
}

/// Render boolean field as a toggle switch.
///
/// Modern, mobile-friendly interface with ON/OFF states and ARIA switch role.
pub fn render_as_toggle(ctx: FieldRenderCtx) -> Element(FormMsg) {
  let current_value = field_common.extract_boolean_value(ctx.value)

  let field_name = path.get_field_name(ctx.path)

  let state_string = case current_value {
    True -> "on"
    False -> "off"
  }

  html.div(
    [
      attribute.class("formosh-field-wrapper"),
      attribute.attribute("part", "field-wrapper"),
    ],
    [
      field_common.render_label(field_name, ctx.property, ctx.is_required),
      html.div(
        [
          attribute.class("formosh-toggle-wrapper"),
          attribute.attribute("part", "toggle-wrapper"),
        ],
        [
          html.button(
            [
              attribute.type_("button"),
              attribute.class("formosh-toggle"),
              attribute.attribute("part", "toggle"),
              attribute.attribute("data-state", state_string),
              attribute.disabled(ctx.is_disabled),
              attribute.attribute("role", "switch"),
              attribute.attribute("aria-checked", case current_value {
                True -> "true"
                False -> "false"
              }),
              event.on_click(UpdateFieldPath(
                ctx.path,
                types.BooleanValue(!current_value),
              )),
            ],
            [
              html.span(
                [
                  attribute.class("formosh-toggle-slider"),
                  attribute.attribute("part", "toggle-slider"),
                ],
                [],
              ),
              html.span(
                [
                  attribute.class("formosh-toggle-text"),
                  attribute.attribute("part", "toggle-text"),
                ],
                [
                  html.text(case current_value {
                    True -> "ON"
                    False -> "OFF"
                  }),
                ],
              ),
            ],
          ),
        ],
      ),
      field_common.render_help_text(ctx.property),
    ],
  )
}
