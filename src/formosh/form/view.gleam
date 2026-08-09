// View functions for form rendering

import formosh/fields/field_common
import formosh/fields/field_dispatcher
import formosh/fields/readonly_field
import formosh/form/model.{type FormModel, type FormMsg}
import formosh/form/path
import formosh/schema/properties
import formosh/schema/types
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// Render the entire form as a Lustre element.
pub fn view(model: FormModel) -> Element(FormMsg) {
  html.div(
    [
      attribute.class("formosh-container"),
      attribute.attribute("part", "container"),
    ],
    [
      render_form_header(model),
      render_form_body(model),
      render_submission_result(model),
    ],
  )
}

fn render_form_header(model: FormModel) -> Element(FormMsg) {
  html.div(
    [
      attribute.class("formosh-header"),
      attribute.attribute("part", "header"),
    ],
    [
      case model.schema.title {
        Some(title) ->
          html.h2(
            [
              attribute.class("formosh-title"),
              attribute.attribute("part", "title"),
            ],
            [html.text(title)],
          )
        None -> element.none()
      },
      case model.schema.description {
        Some(desc) ->
          html.p(
            [
              attribute.class("formosh-description"),
              attribute.attribute("part", "description"),
            ],
            [html.text(desc)],
          )
        None -> element.none()
      },
    ],
  )
}

fn render_form_body(model: FormModel) -> Element(FormMsg) {
  let ordered_properties =
    properties.apply_order(
      model.resolved_schema.properties,
      model.ui_schema.order,
    )
  let fields =
    list.map(ordered_properties, fn(pair) {
      let #(field_name, property) = pair
      render_field(model, field_name, property)
    })

  // In read-only (review) mode there is nothing to submit or reset, so the
  // footer with its Submit/Reset buttons is omitted entirely.
  let body = case model.read_only {
    True -> fields
    False -> list.append(fields, [render_form_footer_content(model)])
  }

  html.form(
    [
      attribute.class("formosh-form"),
      attribute.attribute("part", "form"),
      // Formosh owns validation: the Submit button is already disabled
      // unless `can_submit`, so native constraint validation can never
      // approve a submit formosh blocked — it can only block one formosh
      // approved, whenever the two disagree (an unanchored JSON Schema
      // `pattern` compiled anchored into the HTML attribute, `multipleOf`
      // vs `step` rounding). That disagreement is silent and unfixable by
      // the user when the offending field sits inside a collapsed array
      // row: `inert` keeps it out of reach but does NOT bar it from
      // constraint validation, so the browser refuses the submit and has
      // nothing it can focus to explain why.
      attribute.attribute("novalidate", "true"),
      event.on_submit(fn(_) { model.FormSubmit }),
    ],
    body,
  )
}

/// Render a single top-level field by dispatching through the unified
/// dispatcher. The same dispatcher is used for nested children inside
/// arrays and objects, so widget selection stays consistent at any depth.
fn render_field(
  model: FormModel,
  field_name: String,
  property: types.SchemaProperty,
) -> Element(FormMsg) {
  let field_path = path.from_field_name(field_name)
  let ctx =
    field_common.make_field_ctx(
      model: model,
      path: field_path,
      property: property,
      is_required: model.is_required_at_path(model, field_path),
      is_disabled: model.is_field_disabled(model, field_path),
      is_readonly: property.read_only,
    )
  case model.read_only {
    True -> readonly_field.render(ctx, model)
    False -> field_dispatcher.render_field_at_path(ctx, model)
  }
}

fn render_form_footer_content(model: FormModel) -> Element(FormMsg) {
  html.div(
    [
      attribute.class("formosh-footer"),
      attribute.attribute("part", "footer"),
    ],
    [
      html.button(
        [
          attribute.type_("submit"),
          attribute.class("formosh-submit"),
          attribute.attribute("part", "submit"),
          attribute.disabled(model.is_submitting || !model.can_submit(model)),
        ],
        [
          html.text(case model.is_submitting {
            True -> "Submitting..."
            False -> "Submit"
          }),
        ],
      ),
      html.button(
        [
          attribute.type_("button"),
          attribute.class("formosh-reset"),
          attribute.attribute("part", "reset"),
          event.on_click(model.ResetForm),
          attribute.disabled(model.is_submitting),
        ],
        [html.text("Reset")],
      ),
    ],
  )
}

fn render_submission_result(model: FormModel) -> Element(FormMsg) {
  case model.submission_result {
    Some(model.SubmissionSuccess(message)) ->
      html.div(
        [
          attribute.class("formosh-success"),
          attribute.attribute("part", "success"),
        ],
        [html.text(message)],
      )
    Some(model.SubmissionError(message)) ->
      html.div(
        [
          attribute.class("formosh-error-message"),
          attribute.attribute("part", "error-message"),
        ],
        [html.text(message)],
      )
    None -> element.none()
  }
}
