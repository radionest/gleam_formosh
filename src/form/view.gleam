// View functions for form rendering

import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import form/model.{type FormModel, type FormMsg}
import fields/string_field
import fields/number_field
import fields/boolean_field
import fields/array_field
import schema/types

// Render the entire form
pub fn view(model: FormModel) -> Element(FormMsg) {
  html.div([attribute.class("formosh-container")], [
    render_form_header(model),
    render_form_body(model),
    render_form_footer(model),
    render_submission_result(model),
  ])
}

// Render form header
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

// Render form body with all fields
fn render_form_body(model: FormModel) -> Element(FormMsg) {
  let fields =
    dict.to_list(model.schema.properties)
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

// Render a single field based on its type
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

  let field_element = case property.field_type {
    Some(types.StringType) ->
      string_field.render(
        field_name,
        property,
        value,
        is_required,
        is_disabled,
      )
    Some(types.NumberType) | Some(types.IntegerType) ->
      number_field.render(
        field_name,
        property,
        value,
        is_required,
        is_disabled,
      )
    Some(types.BooleanType) ->
      boolean_field.render(
        field_name,
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
              types.JsonObject(fields) ->
                list.fold(fields, dict.new(), fn(acc, field_pair) {
                  let #(key, val) = field_pair
                  dict.insert(acc, key, json_value_to_field_value(val))
                })
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
      // Objects not yet implemented
      html.div([attribute.class("formosh-field-unsupported")], [
        html.text("Object field type not yet supported: " <> field_name)
      ])
    _ ->
      // Handle enum or unknown types
      case property.enum_values {
        Some(_enum_vals) ->
          string_field.render_enum(
            field_name,
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

// Render field errors
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

// Render form footer with submit button
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

// Render submission result message
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

// Helper function to convert JsonValue to FieldValue
fn json_value_to_field_value(value: types.JsonValue) -> types.FieldValue {
  case value {
    types.JsonString(s) -> types.StringValue(s)
    types.JsonNumber(n) -> types.NumberValue(n)
    types.JsonBool(b) -> types.BooleanValue(b)
    types.JsonNull -> types.NullValue
    types.JsonArray(items) -> types.ArrayValue(items)
    types.JsonObject(fields) -> types.ObjectValue(fields)
  }
}