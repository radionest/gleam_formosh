import formosh
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import lustre
import lustre/attribute
import lustre/effect
import lustre/element
import lustre/element/html
import lustre/event
import simplifile

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
  NoOp
}

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

fn init(_) -> #(Model, effect.Effect(Msg)) {
  let schemas = list_schema_files()
  #(
    Model(
      selected_schema: None,
      schema_content: None,
      form_html: None,
      available_schemas: schemas,
      error: None,
    ),
    effect.none(),
}

fn list_schema_files() -> List(String) {
  case simplifile.read_directory("example/schemas") {
    Ok(files) -> {
      files
      |> list.filter(fn(file) { string.ends_with(file, ".json") })
      |> list.sort(string.compare)
    }
    Error(_) -> []
  }
}

fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    LoadSchema(filename) -> {
      let path = "example/schemas/" <> filename
      case simplifile.read(path) {
        Ok(content) -> {
          case formosh.from_json_string(content) {
            Ok(_form_app) -> {
              #(
                Model(
                  ..model,
                  selected_schema: Some(filename),
                  schema_content: Some(content),
                  form_html: Some(generate_form_preview(content)),
                  error: None,
                ),
                effect.none(),
              )
            }
            Error(_) -> {
              #(
                Model(
                  ..model,
                  selected_schema: Some(filename),
                  schema_content: None,
                  form_html: None,
                  error: Some("Ошибка парсинга JSON схемы"),
                ),
                effect.none(),
              )
            }
          }
        }
        Error(_) -> {
          #(
            Model(
              ..model,
              selected_schema: Some(filename),
              schema_content: None,
              form_html: None,
              error: Some("Ошибка чтения файла"),
            ),
            effect.none(),
          )
        }
      }
    }
    NoOp -> #(model, effect.none())
  }
}


fn view(model: Model) -> element.Element(Msg) {
  html.div([attribute.class("container")], [
    html.h1([], [html.text("Загрузчик JSON Schema из файлов")]),
    
    html.div([attribute.class("schema-selector")], [
      html.h2([], [html.text("Выберите схему:")]),
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
      Some(error) -> {
        html.div([attribute.class("error-message")], [
          html.text(error),
        ])
      }
      None -> element.none()
    },
    
    case model.form_html {
      Some(form_info) -> {
        html.div([attribute.class("form-container")], [
          html.h2([], [html.text("Информация о схеме:")]),
          html.div([attribute.class("info-box")], [
            html.p([], [html.text("Файл: " <> option.unwrap(model.selected_schema, ""))]),
          ]),
          html.div([attribute.class("schema-preview")], [
            html.pre([], [html.text(form_info)]),
          ]),
          html.div([attribute.class("action-box")], [
            html.p([], [
              html.text("Для полного интерактивного примера, используйте "),
              html.code([], [html.text("gleam run")]),
              html.text(" в корне проекта."),
            ]),
          ]),
        ])
      }
      None -> {
        case model.selected_schema {
          None -> {
            html.div([attribute.class("placeholder")], [
              html.p([], [html.text("Выберите схему для загрузки")]),
            ])
          }
          Some(_) -> element.none()
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
  let preview = case formosh.from_json_string(json_content) {
    Ok(_) -> {
      "Схема успешно распознана и может быть использована для генерации формы.\n\n"
      <> "Первые 500 символов JSON схемы:\n\n"
      <> string.slice(json_content, 0, 500)
    }
    Error(_) -> "Ошибка при анализе схемы"
  }
  preview
}