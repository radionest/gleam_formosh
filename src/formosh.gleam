// Main module for Formosh - JSON Schema based form generator

import gleam/io
import lustre
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import form/model.{type FormModel, type FormMsg}
import form/update
import form/view
import schema/types.{type JsonSchema}
import schema/parser

// Initialize a form from a JsonSchema
pub fn from_schema(schema: JsonSchema) -> FormApp {
  create_form(schema)
}

// Form application type
pub type FormApp {
  FormApp(
    init: fn(Nil) -> #(FormModel, Effect(FormMsg)),
    update: fn(FormModel, FormMsg) -> #(FormModel, Effect(FormMsg)),
    view: fn(FormModel) -> Element(FormMsg),
  )
}

// Create a form application from a schema
fn create_form(schema: JsonSchema) -> FormApp {
  FormApp(
    init: fn(_) { #(model.init(schema), effect.none()) },
    update: update.update,
    view: view.view,
  )
}

// Create a Lustre application from a form
pub fn to_lustre_app(form_app: FormApp) -> lustre.App(Nil, FormModel, FormMsg) {
  lustre.application(form_app.init, form_app.update, form_app.view)
}

// Initialize a form from a JSON string
pub fn from_json_string(json_string: String) -> Result(FormApp, parser.ParseError) {
  case parser.parse_schema(json_string) {
    Ok(schema) -> Ok(from_schema(schema))
    Error(err) -> Error(err)
  }
}

// Main function to run example
pub fn main() {
  // Parse the example JSON schema
  let form_result = case parser.parse_schema(example_schema) {
    Ok(schema) -> {
      io.println("Successfully parsed JSON schema: " <> schema.title)
      Ok(from_schema(schema))
    }
    Error(err) -> {
      io.println("Failed to parse JSON schema")
      case err {
        parser.InvalidJson(msg) -> io.println("Invalid JSON: " <> msg)
        parser.MissingField(field) -> io.println("Missing field: " <> field)
        parser.InvalidType(msg) -> io.println("Invalid type: " <> msg)
        parser.UnexpectedValue(msg) -> io.println("Unexpected value: " <> msg)
        parser.DecodingError(_) -> io.println("JSON decoding error")
      }
      Error(err)
    }
  }
  
  case form_result {
    Ok(form) -> {
      let app = to_lustre_app(form)
      // Only start the app if we're in a browser environment
      case lustre.start(app, "#app", Nil) {
        Ok(_) -> Nil
        Error(_) -> Nil // Silently ignore if not in browser
      }
    }
    Error(_) -> Nil
  }
}

// Example schema for testing
pub const example_schema = "
{
    \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",
    \"$id\": \"https://example.com/lesion-measurement.schema.json\",
    \"title\": \"Измерение образований\",
    \"description\": \"Укажите наибольший размер каждого обнаруженного образования в миллиметрах\",
    \"type\": \"object\",
    \"properties\": {
      \"diagnosis\": {
        \"description\": \"Диагноз\",
        \"type\": \"string\",
        \"maxLength\": 200
      },
      \"diagnosis2\": {
        \"description\": \"Диагноз3\",
        \"type\": \"string\",
        \"maxLength\": 200
      },
      \"lesions\": {
        \"description\": \"Список измерений образований\",
        \"type\": \"array\",
        \"items\": {
          \"type\": \"object\",
          \"properties\": {
            \"side\": {
              \"description\": \"Сторона (L - левая, R - правая)\",
              \"type\": \"string\",
              \"enum\": [\"L\", \"R\"]
            },
            \"max_size_mm\": {
              \"description\": \"Наибольший размер в миллиметрах\",
              \"type\": \"number\",
              \"minimum\": 0,
              \"maximum\": 200
            },
            \"location\": {
              \"description\": \"Локализация образования\",
              \"type\": \"string\",
              \"maxLength\": 100
            },
            \"notes\": {
              \"description\": \"Дополнительные примечания\",
              \"type\": \"string\",
              \"maxLength\": 500
            }
          },
          \"required\": [\"side\", \"max_size_mm\"]
        },
        \"minItems\": 1
      }
    },
    \"required\": [\"lesions\"]
  }
"