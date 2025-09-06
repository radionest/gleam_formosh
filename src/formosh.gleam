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

/// Create a form application from a JSON Schema definition.
/// 
/// This is the main entry point for creating forms. It takes a parsed JSON Schema
/// and returns a FormApp that can be converted to a Lustre application.
/// 
/// ## Example
/// ```gleam
/// let schema = JsonSchema(...)
/// let form_app = formosh.from_schema(schema)
/// let lustre_app = formosh.to_lustre_app(form_app)
/// ```
pub fn from_schema(schema: JsonSchema) -> FormApp {
  create_form(schema)
}

/// A form application containing the MVU (Model-View-Update) functions.
/// 
/// This type encapsulates all the functions needed to run a form as a Lustre
/// application. It provides the init, update, and view functions that follow
/// the Elm/Lustre architecture pattern.
pub type FormApp {
  FormApp(
    init: fn(Nil) -> #(FormModel, Effect(FormMsg)),
    update: fn(FormModel, FormMsg) -> #(FormModel, Effect(FormMsg)),
    view: fn(FormModel) -> Element(FormMsg),
  )
}

/// Internal function to create a FormApp from a parsed JsonSchema.
/// 
/// This function sets up the MVU architecture by providing the init, update,
/// and view functions needed for a Lustre application.
fn create_form(schema: JsonSchema) -> FormApp {
  FormApp(
    init: fn(_) { #(model.init(schema), effect.none()) },
    update: update.update,
    view: view.view,
  )
}

/// Convert a FormApp into a standard Lustre application.
/// 
/// This function takes a FormApp and creates a proper Lustre application that
/// can be started with `lustre.start()`. The resulting application follows the
/// standard MVU pattern and can be mounted to a DOM element.
/// 
/// ## Example
/// ```gleam
/// let app = formosh.to_lustre_app(form_app)
/// lustre.start(app, "#form-container", Nil)
/// ```
pub fn to_lustre_app(form_app: FormApp) -> lustre.App(Nil, FormModel, FormMsg) {
  lustre.application(form_app.init, form_app.update, form_app.view)
}

/// Create a form application from a JSON Schema string.
/// 
/// This is a convenience function that combines JSON parsing and form creation.
/// It takes a JSON string containing a valid JSON Schema and returns either
/// a FormApp or a parsing error.
/// 
/// ## Parameters
/// - `json_string`: A valid JSON string containing a JSON Schema definition
/// 
/// ## Returns
/// - `Ok(FormApp)` if the JSON was valid and could be converted to a form
/// - `Error(ParseError)` if the JSON was invalid or couldn't be parsed
/// 
/// ## Example
/// ```gleam
/// let json = "{\"title\": \"My Form\", \"type\": \"object\", ...}"
/// case formosh.from_json_string(json) {
///   Ok(form_app) -> // Use the form
///   Error(parse_error) -> // Handle parsing error
/// }
/// ```
pub fn from_json_string(json_string: String) -> Result(FormApp, parser.ParseError) {
  case parser.parse_schema(json_string) {
    Ok(schema) -> Ok(from_schema(schema))
    Error(err) -> Error(err)
  }
}

/// Main function that demonstrates the library with an example form.
/// 
/// This function parses the built-in example schema and starts a form
/// application. It's primarily used for development and testing, but also
/// serves as a usage example.
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

/// Example JSON Schema for testing and demonstration purposes.
/// 
/// This schema defines a medical form for lesion measurements with:
/// - Required diagnosis fields (strings with max length)
/// - An array of lesion objects with side, size, location, and notes
/// - Various validation constraints and field types
/// 
/// This serves as both a test case and a comprehensive example of
/// the types of forms this library can generate.
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