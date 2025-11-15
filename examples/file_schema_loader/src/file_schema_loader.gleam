import formosh
import formosh/component
import gleam/dict
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import lustre
import lustre/attribute
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import rsvp

pub type Model {
  Model(
    selected_schema: Option(String),
    schema_content: Option(String),
    available_schemas: List(String),
    error: Option(String),
    submission_result: Option(String),
  )
}

pub type Msg {
  LoadSchema(String)
  SchemaFetched(Result(String, String))
  FormSubmitted(dict.Dict(String, String))
  FormChanged(dict.Dict(String, String))
  ClearSubmissionResult
}

pub fn main() {
  // Register the formosh web component
  let _ = component.register()

  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

fn init(_) -> #(Model, effect.Effect(Msg)) {
  // List of available schema files
  // In browser environment, we can't read directory, so we hardcode the list
  let schemas = [
    "contact_form.json",
    "survey_form.json",
    "user_registration.json",
    "basic_leak_signs.json",
  ]

  #(
    Model(
      selected_schema: option.None,
      schema_content: option.None,
      available_schemas: schemas,
      error: option.None,
      submission_result: option.None,
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
          selected_schema: option.Some(filename),
          error: option.None,
        ),
        fetch_schema(filename),
      )
    }

    SchemaFetched(result) -> {
      case result {
        Ok(content) -> {
          // Validate that it's a valid JSON schema
          case formosh.from_json_string(content) {
            Ok(_) -> {
              #(
                Model(
                  ..model,
                  schema_content: option.Some(content),
                  error: option.None,
                ),
                effect.none(),
              )
            }
            Error(_) -> {
              #(
                Model(
                  ..model,
                  schema_content: option.None,
                  error: option.Some("Invalid JSON Schema format"),
                ),
                effect.none(),
              )
            }
          }
        }
        Error(error) -> {
          #(
            Model(
              ..model,
              schema_content: option.None,
              error: option.Some("Failed to load schema: " <> error),
            ),
            effect.none(),
          )
        }
      }
    }

    FormSubmitted(values) -> {
      // Handle form submission
      let result_message = case dict.get(values, "error") {
        Ok(error) -> "Error: " <> error
        Error(_) ->
          case dict.get(values, "response") {
            Ok(response) -> "Success! Server response: " <> response
            Error(_) -> "Form submitted to http://localhost:8888"
          }
      }

      #(
        Model(..model, submission_result: option.Some(result_message)),
        effect.none(),
      )
    }

    FormChanged(values) -> {
      // Handle form changes (could be used for validation feedback)
      let _ = values
      #(model, effect.none())
    }

    ClearSubmissionResult -> {
      #(Model(..model, submission_result: option.None), effect.none())
    }
  }
}

fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("container")], [
    html.h1([], [html.text("JSON Schema File Loader")]),

    // Schema selector
    html.div([attribute.class("schema-selector")], [
      html.h2([], [html.text("Select a schema:")]),
      html.div(
        [attribute.class("schema-list")],
        list.map(model.available_schemas, fn(filename) {
          let is_selected = case model.selected_schema {
            option.Some(selected) -> selected == filename
            option.None -> False
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

    // Error message
    case model.error {
      option.Some(error) -> {
        html.div([attribute.class("error-message")], [
          html.text(error),
        ])
      }
      option.None -> element.none()
    },

    // Submission result with styling
    case model.submission_result {
      option.Some(result) -> {
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
      option.None -> element.none()
    },

    // Form display using web component
    case model.schema_content {
      option.Some(schema_json) -> {
        html.div([attribute.class("form-container")], [
          html.h2([], [html.text("Generated Form:")]),
          html.div([attribute.class("info-box")], [
            html.p([], [
              html.text("Schema: " <> option.unwrap(model.selected_schema, "")),
            ]),
          ]),

          // Render the formosh web component
          html.div([attribute.id("form-mount-point")], [
            element.element(
              "formosh-form",
              [
                attribute.attribute("schema", schema_json),
                attribute.attribute("submit-url", "http://localhost:8888"),
                attribute.attribute("submit-method", "POST"),
                // Listen for form events
                event.on("formosh-submit", decode_form_submit()),
                event.on("formosh-change", decode_form_change()),
              ],
              [],
            ),
          ]),
        ])
      }
      option.None -> {
        case model.selected_schema {
          option.None -> {
            html.div([attribute.class("placeholder")], [
              html.p([], [
                html.text("Select a schema to load and display the form"),
              ]),
            ])
          }
          option.Some(_) -> {
            html.div([attribute.class("placeholder")], [
              html.p([], [html.text("Loading schema...")]),
            ])
          }
        }
      }
    },
  ])
}

fn get_display_name(filename: String) -> String {
  filename
  |> string.replace(".json", "")
  |> string.replace("_", " ")
  |> string.replace("-", " ")
  |> string.capitalise()
}

// Effect to fetch schema content via HTTP
fn fetch_schema(filename: String) -> effect.Effect(Msg) {
  let url = "./schemas/" <> filename
  let handler =
    rsvp.expect_any_response(fn(fetch_result) {
      case fetch_result {
        Ok(json_string) -> SchemaFetched(Ok(json_string.body))
        Error(error) -> {
          case error {
            rsvp.HttpError(resp) -> SchemaFetched(Error(resp.body))
            rsvp.NetworkError -> SchemaFetched(Error("Network error"))
            rsvp.BadUrl(u) -> SchemaFetched(Error("BAD url " <> u))
            rsvp.BadBody -> SchemaFetched(Error("Bad body"))
            _ -> SchemaFetched(Error("Can't fetch schema at " <> url))
          }
        }
      }
    })
  rsvp.get(url, handler)
}

// Decoders for form events
fn decode_form_submit() -> decode.Decoder(Msg) {
  use event_data <- decode.then(decode.at(["detail"], decode.dynamic))

  // Try to extract status and data/error from the event
  let status =
    decode.run(event_data, decode.at(["status"], decode.string))
    |> result.unwrap("unknown")

  let values = case status {
    "success" -> {
      // Extract server response data
      decode.run(event_data, decode.at(["data"], decode.string))
      |> result.map(fn(data) { dict.from_list([#("response", data)]) })
      |> result.unwrap(dict.new())
    }
    "error" -> {
      // Extract error message
      decode.run(event_data, decode.at(["error"], decode.string))
      |> result.map(fn(error) { dict.from_list([#("error", error)]) })
      |> result.unwrap(dict.new())
    }
    _ -> dict.new()
  }

  decode.success(FormSubmitted(values))
}

fn decode_form_change() -> decode.Decoder(Msg) {
  decode.at(["detail", "values"], decode.dynamic)
  |> decode.map(fn(_values) {
    // TODO: Properly decode the form values
    FormChanged(dict.new())
  })
}
