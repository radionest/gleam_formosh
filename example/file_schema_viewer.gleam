import formosh
import gleam/json
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
    available_schemas: List(String),
    schema_info: Option(SchemaInfo),
    error: Option(String),
  )
}

pub type SchemaInfo {
  SchemaInfo(
    filename: String,
    title: String,
    description: String,
    properties: List(String),
    required: List(String),
  )
}

pub type Msg {
  LoadSchema(String)
  OpenInNewTab(String)
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
      available_schemas: schemas,
      schema_info: None,
      error: None,
    ),
    effect.none(),
  )
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
          case parse_schema_info(content) {
            Ok(info) -> {
              #(
                Model(
                  ..model,
                  selected_schema: Some(filename),
                  schema_info: Some(SchemaInfo(..info, filename: filename)),
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
                  schema_info: None,
                  error: Some("Не удалось распарсить схему"),
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
              schema_info: None,
              error: Some("Не удалось прочитать файл"),
            ),
            effect.none(),
          )
        }
      }
    }
    
    OpenInNewTab(filename) -> {
      #(model, effect.none())
    }
  }
}

fn parse_schema_info(content: String) -> Result(SchemaInfo, String) {
  case json.decode(content, fn(value) {
    use title <- result.try(
      json.field("title", json.string)(value)
      |> result.replace_error("No title")
    )
    use description <- result.try(
      json.field("description", json.string)(value)
      |> result.or(Ok(""))
    )
    use properties <- result.try(
      json.field("properties", fn(props) {
        json.object(props)
        |> result.map(fn(obj) { list.map(obj, fn(pair) { pair.0 }) })
      })(value)
      |> result.or(Ok([]))
    )
    use required <- result.try(
      json.field("required", json.list(json.string))(value)
      |> result.or(Ok([]))
    )
    
    Ok(SchemaInfo(
      filename: "",
      title: title,
      description: description,
      properties: properties,
      required: required,
    ))
  }) {
    Ok(info) -> Ok(info)
    Error(_) -> Error("Failed to parse schema")
  }
}

fn view(model: Model) -> element.Element(Msg) {
  html.div([attribute.class("container")], [
    html.h1([], [html.text("JSON Schema Viewer с изоляцией")]),
    
    html.div([attribute.class("layout")], [
      html.div([attribute.class("sidebar")], [
        html.h2([], [html.text("Доступные схемы:")]),
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
              [html.text(get_display_name(filename))],
            )
          }),
        ),
      ]),
      
      html.div([attribute.class("content")], [
        case model.error {
          Some(error) -> {
            html.div([attribute.class("error-message")], [
              html.text(error),
            ])
          }
          None -> element.none()
        },
        
        case model.schema_info {
          Some(info) -> {
            html.div([attribute.class("schema-details")], [
              html.h2([], [html.text(info.title)]),
              
              case info.description {
                "" -> element.none()
                desc -> html.p([attribute.class("description")], [html.text(desc)])
              },
              
              html.div([attribute.class("info-grid")], [
                html.div([attribute.class("info-card")], [
                  html.h3([], [html.text("Поля (" <> string.inspect(list.length(info.properties)) <> ")")]),
                  html.ul(
                    [],
                    list.map(info.properties, fn(prop) {
                      let is_required = list.contains(info.required, prop)
                      html.li([], [
                        html.text(prop),
                        case is_required {
                          True -> html.span([attribute.class("badge required")], [html.text("обязательное")])
                          False -> element.none()
                        },
                      ])
                    }),
                  ),
                ]),
                
                html.div([attribute.class("info-card")], [
                  html.h3([], [html.text("Детали")]),
                  html.ul([], [
                    html.li([], [html.text("Файл: " <> info.filename)]),
                    html.li([], [html.text("Обязательных полей: " <> string.inspect(list.length(info.required)))]),
                    html.li([], [html.text("Всего полей: " <> string.inspect(list.length(info.properties)))]),
                  ]),
                ]),
              ]),
              
              html.div([attribute.class("actions")], [
                html.a(
                  [
                    attribute.href("/example/index.html?schema=" <> info.filename),
                    attribute.target("_blank"),
                    attribute.class("button primary"),
                  ],
                  [html.text("Открыть форму в новой вкладке")],
                ),
              ]),
            ])
          }
          None -> {
            case model.selected_schema {
              None -> {
                html.div([attribute.class("placeholder")], [
                  html.p([], [html.text("Выберите схему для просмотра")]),
                ])
              }
              Some(_) -> element.none()
            }
          }
        },
      ]),
    ]),
  ])
}

fn get_display_name(filename: String) -> String {
  filename
  |> string.replace(".json", "")
  |> string.replace("_", " ")
  |> string.replace("-", " ")
  |> string.capitalise()
}