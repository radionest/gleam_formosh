// View functions for form rendering

import fields/array_field
import fields/boolean_field
import fields/number_field
import fields/object_field
import fields/string_field
import form/model.{type FormModel, type FormMsg}
import form/path
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import schema/types

/// Render the entire form as a Lustre element.
/// 
/// This is the main view function for the form, rendering a complete form
/// interface including header, body with all fields, footer with actions,
/// and any submission result messages.
/// 
/// ## Parameters
/// - `model`: The current form model containing all state and schema information
/// 
/// ## Returns
/// A Lustre Element representing the complete form interface
/// 
/// ## Structure
/// The rendered form includes:
/// - Form header with title and description
/// - Form body with all schema-defined fields
/// - Form footer with submit/reset buttons
/// - Submission result messages (success/error)
pub fn view(model: FormModel) -> Element(FormMsg) {
  html.div([attribute.class("formosh-container")], [
    render_form_header(model),
    render_form_body(model),
    render_form_footer(model),
    render_submission_result(model),
  ])
}

/// Render the form header with title and description.
/// 
/// Creates the top section of the form containing the schema title and
/// optional description text.
/// 
/// ## Parameters
/// - `model`: The form model containing schema information
/// 
/// ## Returns
/// A Lustre Element containing the form header
fn render_form_header(model: FormModel) -> Element(FormMsg) {
  html.div([attribute.class("formosh-header")], [
    html.h2([attribute.class("formosh-title")], [
      html.text(model.schema.title),
    ]),
    case model.schema.description {
      Some(desc) ->
        html.p([attribute.class("formosh-description")], [html.text(desc)])
      None -> html.text("")
    },
  ])
}

/// Render the form body containing all form fields.
/// 
/// Creates the main form element with all schema-defined fields rendered
/// according to their types and constraints. Each field is wrapped in
/// appropriate containers and includes error display.
/// 
/// ## Parameters
/// - `model`: The form model containing schema and current state
/// 
/// ## Returns
/// A Lustre Element containing the form body with all fields
fn render_form_body(model: FormModel) -> Element(FormMsg) {
  let fields =
    dict.to_list(model.resolved_schema.properties)
    |> list.map(fn(pair) {
      let #(field_name, property) = pair
      render_field(model, field_name, property)
    })

  html.form(
    [
      attribute.class("formosh-form"),
      event.on_submit(fn(_) { model.FormSubmit }),
    ],
    fields,
  )
}

/// Render a single form field based on its schema property.
/// 
/// This function determines the appropriate field renderer based on the
/// field type and renders the field with proper styling, error states,
/// and validation attributes.
/// 
/// ## Parameters
/// - `model`: The form model containing current values and state
/// - `field_name`: The name/key of the field being rendered
/// - `property`: The schema property definition for this field
/// 
/// ## Returns
/// A Lustre Element representing the complete field (label, input, errors)
/// 
/// ## Field Types Supported
/// - String fields (input, textarea, select, radio)
/// - Number/Integer fields
/// - Boolean fields (checkbox)
/// - Array fields (dynamic lists)
/// - Enum fields (select dropdown or radio buttons)
fn render_field(
  model: FormModel,
  field_name: String,
  property: types.SchemaProperty,
) -> Element(FormMsg) {
  let is_required = model.is_field_required(model, field_name)
  let is_disabled = model.is_field_disabled(model, field_name)
  let is_touched = model.is_field_touched(model, field_name)
  let has_errors = model.field_has_errors(model, field_name)
  let errors = model.get_field_errors(model, field_name)
  let value = model.get_field_value(model, field_name)

  // Create a path for root-level fields
  let field_path = path.from_field_name(field_name)

  let field_element = case property.field_type {
    Some(types.StringType) ->
      string_field.render(field_path, property, value, is_required, is_disabled)
    Some(types.NumberType) | Some(types.IntegerType) ->
      number_field.render(field_path, property, value, is_required, is_disabled)
    Some(types.BooleanType) ->
      boolean_field.render(
        field_path,
        property,
        value,
        is_required,
        is_disabled,
      )
    Some(types.ArrayType) -> {
      // Convert field value to array items
      let array_items = case value {
        Some(types.ArrayValue(items)) ->
          list.map(items, fn(item) {
            case item {
              types.ObjectValue(fields) -> dict.from_list(fields)
              _ -> dict.new()
            }
          })
        _ -> []
      }

      array_field.view(
        field_name,
        property,
        array_items,
        list.map(errors, fn(e) { e.message }),
        is_required,
      )
    }
    Some(types.ObjectType) ->
      object_field.render(field_path, property, value, is_required, is_disabled)
    _ ->
      // Handle enum or unknown types
      case property.enum_values {
        Some(_enum_vals) ->
          string_field.render_enum(
            field_path,
            property,
            value,
            is_required,
            is_disabled,
          )
        None -> html.div([], [])
      }
  }

  // Wrap field with container and error display
  html.div(
    [
      attribute.class(
        "formosh-field"
        <> case has_errors && is_touched {
          True -> " formosh-field-error"
          False -> ""
        },
      ),
    ],
    [
      field_element,
      case has_errors && is_touched {
        True -> render_field_errors(errors)
        False -> html.text("")
      },
    ],
  )
}

/// Render validation errors for a field.
/// 
/// Creates a styled error container displaying all validation error messages
/// for a field. Only called when the field has errors and has been touched.
/// 
/// ## Parameters
/// - `errors`: List of validation errors to display
/// 
/// ## Returns
/// A Lustre Element containing the formatted error messages
fn render_field_errors(errors: List(types.ValidationError)) -> Element(FormMsg) {
  html.div(
    [attribute.class("formosh-errors")],
    list.map(errors, fn(error) {
      html.div([attribute.class("formosh-error")], [
        html.text(error.message),
      ])
    }),
  )
}

/// Render the form footer with action buttons.
/// 
/// Creates the bottom section of the form containing submit and reset buttons
/// with appropriate enabled/disabled states based on form validity and submission status.
/// 
/// ## Parameters
/// - `model`: The form model to determine button states
/// 
/// ## Returns
/// A Lustre Element containing the form action buttons
fn render_form_footer(model: FormModel) -> Element(FormMsg) {
  html.div([attribute.class("formosh-footer")], [
    html.button(
      [
        attribute.type_("submit"),
        attribute.class("formosh-submit"),
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
        event.on_click(model.ResetForm),
        attribute.disabled(model.is_submitting),
      ],
      [html.text("Reset")],
    ),
  ])
}

/// Render the submission result message.
/// 
/// Displays success or error messages after form submission attempts.
/// Only renders when there is a submission result to show.
/// 
/// ## Parameters
/// - `model`: The form model containing submission result state
/// 
/// ## Returns
/// A Lustre Element containing the result message, or empty text if no result
fn render_submission_result(model: FormModel) -> Element(FormMsg) {
  case model.submission_result {
    Some(model.SubmissionSuccess(message)) ->
      html.div([attribute.class("formosh-success")], [
        html.text(message),
      ])
    Some(model.SubmissionError(message)) ->
      html.div([attribute.class("formosh-error-message")], [
        html.text(message),
      ])
    None -> html.text("")
  }
}
