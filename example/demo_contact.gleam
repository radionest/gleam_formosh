// Demo: Contact Form with Conditional Logic
// This example demonstrates JSON Schema conditionals (if/then/else)
// When "Общий вопрос" is selected, an additional field appears

import formosh
import gleam/io
import lustre
import simplifile

pub fn main() {
  io.println("Starting Contact Form Demo with Conditionals...")
  io.println(
    "📝 When 'Общий вопрос' is selected, a confidentiality checkbox will appear",
  )

  // Load the contact form schema from file (which includes conditional logic)
  case simplifile.read("example/schemas/contact_form.json") {
    Ok(schema) -> {
      io.println("✓ Schema file loaded successfully")

      case
        formosh.from_json_string_with_config(
          schema,
          formosh.HttpSubmit(
            url: "https://api.example.com/contact",
            method: "POST",
            headers: [#("Content-Type", "application/json")],
          ),
        )
      {
        Ok(form_app) -> {
          io.println("✓ Contact form created successfully")

          case lustre.start(form_app, "#app", Nil) {
            Ok(_) -> {
              io.println("✓ Form started successfully")
              io.println(
                "📋 Contact form with conditionals is ready at http://localhost:1234",
              )
            }
            Error(_) ->
              io.println("Note: Form will only display in browser environment")
          }
        }
        Error(_err) -> {
          io.println("Failed to create contact form")
        }
      }
    }
    Error(_err) -> {
      io.println("Failed to read schema file")
      io.println("Make sure example/schemas/contact_form.json exists")
    }
  }
}
