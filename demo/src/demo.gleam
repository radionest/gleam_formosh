import formosh
import formosh/component
import gleam/dict
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lustre
import lustre/attribute
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import rsvp
import validators

const submit_url = "http://localhost:8888"

const form_element_id = "demo-formosh-form"

/// Map a schema filename to a cross-field validator kind, if any.
///
/// The kind string must match a key in the `VALIDATORS` table in
/// `validator_ffi.mjs`. Schemas not in this list render with no
/// cross-field validation.
fn validator_kind_for(filename: String) -> Option(String) {
  case filename {
    "budget_split.json" -> Some("budget_split")
    "date_range.json" -> Some("date_range")
    "password_confirm.json" -> Some("password_confirm")
    _ -> None
  }
}

pub type Model {
  Model(
    selected_schema: Option(String),
    schema_content: Option(String),
    ui_schema_content: Option(String),
    available_schemas: List(String),
    error: Option(String),
    submission_result: Option(String),
  )
}

pub type Msg {
  LoadSchema(String)
  SchemaFetched(Result(String, String))
  UiSchemaFetched(Option(String))
  FormSubmitted(dict.Dict(String, String))
  ClearSubmissionResult
}

pub fn main() {
  let _ = component.register()

  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

fn init(_) -> #(Model, effect.Effect(Msg)) {
  // Browsers can't list directories — keep the catalogue here. Pair a
  // schema with a `<basename>.ui.json` to show UiSchema-driven rendering.
  let schemas = [
    "carcinomatosis_review.json",
    "widgets_demo.json",
    "contact_form.json",
    "survey_form.json",
    "user_registration.json",
    "pattern_validation.json",
    "basic_leak_signs.json",
    "array_editable_test.json",
    "array_readonly_test.json",
    "array_readonly_test_full.json",
    "hidden_fields_test.json",
    "budget_split.json",
    "date_range.json",
    "password_confirm.json",
  ]

  #(
    Model(
      selected_schema: None,
      schema_content: None,
      ui_schema_content: None,
      available_schemas: schemas,
      error: None,
      submission_result: None,
    ),
    effect.none(),
  )
}

fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    LoadSchema(filename) -> {
      #(
        Model(
          ..model,
          selected_schema: Some(filename),
          schema_content: None,
          ui_schema_content: None,
          error: None,
        ),
        effect.batch([fetch_schema(filename), fetch_ui_schema(filename)]),
      )
    }

    SchemaFetched(result) -> {
      case result {
        Ok(content) -> {
          case formosh.from_json_string(content) {
            Ok(_) -> #(
              Model(..model, schema_content: Some(content), error: None),
              attach_validator_effect(model.selected_schema),
            )
            Error(_) -> #(
              Model(
                ..model,
                schema_content: None,
                error: Some("Invalid JSON Schema format"),
              ),
              effect.none(),
            )
          }
        }
        Error(error) -> #(
          Model(
            ..model,
            schema_content: None,
            error: Some("Failed to load schema: " <> error),
          ),
          effect.none(),
        )
      }
    }

    UiSchemaFetched(content) -> {
      #(Model(..model, ui_schema_content: content), effect.none())
    }

    FormSubmitted(values) -> {
      let result_message = case dict.get(values, "error") {
        Ok(error) -> "Error: " <> error
        Error(_) ->
          case dict.get(values, "response") {
            Ok(response) -> "Success! Server response: " <> response
            Error(_) -> "Form submitted to " <> submit_url
          }
      }

      #(Model(..model, submission_result: Some(result_message)), effect.none())
    }

    ClearSubmissionResult -> {
      #(Model(..model, submission_result: None), effect.none())
    }
  }
}

fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("container")], [
    html.h1([], [html.text("Formosh Demo")]),

    html.div([attribute.class("schema-selector")], [
      html.h2([], [html.text("Select a schema:")]),
      html.div(
        [attribute.class("schema-list")],
        list.map(model.available_schemas, fn(filename) {
          let is_selected = case model.selected_schema {
            Some(selected) -> selected == filename
            None -> False
          }

          html.button(
            [
              event.on_click(LoadSchema(filename)),
              attribute.class(case is_selected {
                True -> "schema-button selected"
                False -> "schema-button"
              }),
            ],
            [
              html.text(get_display_name(filename)),
              case is_selected {
                True -> html.span([attribute.class("badge")], [html.text(" ✓")])
                False -> element.none()
              },
            ],
          )
        }),
      ),
    ]),

    case model.error {
      Some(error) ->
        html.div([attribute.class("error-message")], [html.text(error)])
      None -> element.none()
    },

    case model.submission_result {
      Some(result) -> {
        let is_error = string.contains(result, "Error")
        html.div(
          [
            attribute.class(case is_error {
              True -> "form-status error"
              False -> "form-status success"
            }),
          ],
          [
            html.text(result),
            html.button(
              [
                event.on_click(ClearSubmissionResult),
                attribute.class("clear-button"),
              ],
              [html.text(" ×")],
            ),
          ],
        )
      }
      None -> element.none()
    },

    case model.schema_content {
      Some(schema_json) -> {
        html.div([attribute.class("form-container")], [
          html.h2([], [html.text("Generated Form:")]),
          html.div([attribute.class("info-box")], [
            html.p([], [
              html.text("Schema: " <> option.unwrap(model.selected_schema, "")),
            ]),
            case model.ui_schema_content {
              Some(_) ->
                html.p([], [html.text("UiSchema: applied (paired .ui.json)")])
              None -> element.none()
            },
            case
              model.selected_schema
              |> option.then(validator_kind_for)
            {
              Some(kind) ->
                html.p([], [
                  html.text("Cross-field validator: " <> kind <> " (active)"),
                ])
              None -> element.none()
            },
          ]),

          html.div([attribute.id("form-mount-point")], [
            element.element(
              "formosh-form",
              form_attributes(schema_json, model.ui_schema_content),
              [],
            ),
          ]),
        ])
      }
      None -> {
        case model.selected_schema {
          None ->
            html.div([attribute.class("placeholder")], [
              html.p([], [
                html.text("Select a schema to load and display the form"),
              ]),
            ])
          Some(_) ->
            html.div([attribute.class("placeholder")], [
              html.p([], [html.text("Loading schema...")]),
            ])
        }
      }
    },
  ])
}

fn form_attributes(
  schema_json: String,
  ui_schema: Option(String),
) -> List(attribute.Attribute(Msg)) {
  let base = [
    attribute.id(form_element_id),
    attribute.attribute("schema", schema_json),
    attribute.attribute("submit-url", submit_url),
    attribute.attribute("submit-method", "POST"),
    event.on("formosh-submit", decode_form_submit()),
  ]
  case ui_schema {
    Some(json) -> [attribute.attribute("ui-schema", json), ..base]
    None -> base
  }
}

/// Build an effect that attaches the right cross-field validator (or
/// detaches any previous one) once Lustre has rendered the form.
fn attach_validator_effect(filename: Option(String)) -> effect.Effect(Msg) {
  effect.from(fn(_dispatch) {
    case filename {
      None -> validators.detach_validator(form_element_id)
      Some(name) ->
        case validator_kind_for(name) {
          Some(kind) -> validators.attach_validator(form_element_id, kind)
          None -> validators.detach_validator(form_element_id)
        }
    }
  })
}

fn get_display_name(filename: String) -> String {
  filename
  |> string.replace(".json", "")
  |> string.replace("_", " ")
  |> string.replace("-", " ")
  |> string.capitalise()
}

fn fetch_schema(filename: String) -> effect.Effect(Msg) {
  let url = "./schemas/" <> filename
  let handler =
    rsvp.expect_any_response(fn(fetch_result) {
      case fetch_result {
        Ok(json_string) -> SchemaFetched(Ok(json_string.body))
        Error(error) ->
          case error {
            rsvp.HttpError(resp) -> SchemaFetched(Error(resp.body))
            rsvp.NetworkError -> SchemaFetched(Error("Network error"))
            rsvp.BadUrl(u) -> SchemaFetched(Error("BAD url " <> u))
            rsvp.BadBody -> SchemaFetched(Error("Bad body"))
            _ -> SchemaFetched(Error("Can't fetch schema at " <> url))
          }
      }
    })
  rsvp.get(url, handler)
}

// UiSchema is optional. lustre/dev returns index.html for missing files
// (SPA fallback) instead of 404, so we sniff for a leading `{` to tell a
// real JSON object from the fallback page.
fn fetch_ui_schema(filename: String) -> effect.Effect(Msg) {
  let basename = string.replace(filename, ".json", "")
  let url = "./schemas/" <> basename <> ".ui.json"
  let handler =
    rsvp.expect_any_response(fn(fetch_result) {
      case fetch_result {
        Ok(resp) ->
          case string.starts_with(string.trim(resp.body), "{") {
            True -> UiSchemaFetched(Some(resp.body))
            False -> UiSchemaFetched(None)
          }
        Error(_) -> UiSchemaFetched(None)
      }
    })
  rsvp.get(url, handler)
}

fn decode_form_submit() -> decode.Decoder(Msg) {
  use event_data <- decode.then(decode.at(["detail"], decode.dynamic))

  let status =
    decode.run(event_data, decode.at(["status"], decode.string))
    |> result.unwrap("unknown")

  let values = case status {
    "success" ->
      decode.run(event_data, decode.at(["data"], decode.string))
      |> result.map(fn(data) { dict.from_list([#("response", data)]) })
      |> result.unwrap(dict.new())
    "error" ->
      decode.run(event_data, decode.at(["error"], decode.string))
      |> result.map(fn(error) { dict.from_list([#("error", error)]) })
      |> result.unwrap(dict.new())
    _ -> dict.new()
  }

  decode.success(FormSubmitted(values))
}
