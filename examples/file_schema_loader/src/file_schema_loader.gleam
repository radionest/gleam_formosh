import gleam/result
import formosh
import gleam/list
import gleam/option.{type Option}
import gleam/string
import lustre
import lustre/attribute
import lustre/effect
import lustre/element
import lustre/element/html
import lustre/event

pub type Model {
  Model(
    selected_schema: Option(String),
    schema_content: Option(String),
    form_html: Option(String),
    available_schemas: List(String),
    error: Option(String),
  )
}

pub type Msg {
  LoadSchema(String)
  SchemaFetched(String, Result(String, String))
}

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

fn init(_) -> #(Model, effect.Effect(Msg)) {
  let schemas = ["contact_form.json"]
  #(
    Model(
      selected_schema: option.None,
      schema_content: option.None,
      form_html: option.None,
      available_schemas: schemas,
      error: option.None,
    ),
    effect.none(),
  )
}

fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    LoadSchema(filename) -> {
      // Start HTTP fetch for schema file
      #(
        Model(
          ..model,
          selected_schema: option.Some(filename),
          error: option.Some("Loading schema..."),
        ),
        fetch_schema_effect(filename),
      )
    }
    
    SchemaFetched(filename, result) -> {
      case result {
        Ok(content) -> {
          echo "Get content"
          case formosh.from_json_string(content) {
            Ok(_form_app) -> {
              #(
                Model(
                  ..model,
                  selected_schema: option.Some(filename),
                  schema_content: option.Some(content),
                  form_html: option.Some(generate_form_preview(content)),
                  error: option.None,
                ),
                effect.none(),
              )
            }
            Error(_) -> {
              #(
                Model(
                  ..model,
                  selected_schema: option.Some(filename),
                  schema_content: option.None,
                  form_html: option.None,
                  error: option.Some("Error parsing JSON schema"),
                ),
                effect.none(),
              )
            }
          }
        }
        Error(err) -> {
          echo "Get error "<>err
          #(
            Model(
              ..model,
              selected_schema: option.Some(filename),
              schema_content: option.None,
              form_html: option.None,
              error: option.Some("Error loading schema: " <> err),
            ),
            effect.none(),
          )
        }
        _ -> {
          echo "Else"
          #(model, effect.none())
        }
      }
    }
  }
}

fn view(model: Model) -> element.Element(Msg) {
  html.div([attribute.class("container")], [
    html.h1([], [html.text("JSON Schema File Loader")]),
    
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
    
    case model.error {
      option.Some(error) -> {
        html.div([attribute.class("error-message")], [
          html.text(error),
        ])
      }
      option.None -> element.none()
    },
    
    case model.form_html {
      option.Some(form_info) -> {
        html.div([attribute.class("form-container")], [
          html.h2([], [html.text("Schema Information:")]),
          html.div([attribute.class("info-box")], [
            html.p([], [html.text("File: " <> option.unwrap(model.selected_schema, ""))]),
          ]),
          html.div([attribute.class("schema-preview")], [
            html.pre([], [html.text(form_info)]),
          ]),
          html.div([attribute.class("action-box")], [
            html.p([], [
              html.text("To see the full interactive form, run "),
              html.code([], [html.text("gleam run")]),
              html.text(" in the project root."),
            ]),
          ]),
        ])
      }
      option.None -> {
        case model.selected_schema {
          option.None -> {
            html.div([attribute.class("placeholder")], [
              html.p([], [html.text("Select a schema to load")]),
            ])
          }
          option.Some(_) -> element.none()
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

fn generate_form_preview(json_content: String) -> String {
  case formosh.from_json_string(json_content) {
    Ok(_) -> {
      "Schema successfully parsed and can be used for form generation.\n\n"
      <> "First 500 characters of JSON schema:\n\n"
      <> string.slice(json_content, 0, 500)
    }
    Error(_) -> "Error parsing schema"
  }
}

// Effect to fetch schema from static folder via HTTP
fn fetch_schema_effect(filename: String) -> effect.Effect(Msg) {
  use dispatch <- effect.from
  let url = "./schemas/" <> filename

  fetch_json(url, fn(result) {
    case string.starts_with(result,"Error:"){
      True -> {    
            echo "ERROR"
            dispatch(SchemaFetched(filename, Error(result)))
            }
      False ->  dispatch(SchemaFetched(filename, Ok(result)))
    }
    
  })
}

// External function to call JavaScript fetch
@external(javascript, "./fetch_schema.mjs", "fetchSchema")
fn fetch_json(url: String, callback: fn(String) -> Nil) -> Nil