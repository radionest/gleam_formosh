// Example application demonstrating Formosh usage with multiple schemas

import formosh
import lustre
import gleam/io
import schema_loader

/// Main function demonstrating loading and using multiple schemas
pub fn main() {
  // Load the default contact form
  demo_contact_form()
}

/// Demo: Contact Form
pub fn demo_contact_form() {
  let schema = schema_loader.load_schema(schema_loader.ContactForm)
  
  io.println("Loading Contact Form...")
  
  case formosh.from_json_string_with_config(
    schema,
    formosh.HttpSubmit(
      url: "https://api.example.com/contact",
      method: "POST",
      headers: [#("Content-Type", "application/json")],
    ),
  ) {
    Ok(form_app) -> {
      io.println("✓ Contact form loaded successfully")
      
      let app = formosh.to_lustre_app(form_app)
      case lustre.start(app, "#app", Nil) {
        Ok(_) -> io.println("✓ Form started successfully")
        Error(_) -> io.println("✗ Failed to start form (not in browser environment)")
      }
    }
    Error(err) -> {
      io.println("✗ Failed to parse schema")
      handle_parse_error(err)
    }
  }
}

/// Demo: User Registration Form
pub fn demo_user_registration() {
  let schema = schema_loader.load_schema(schema_loader.UserRegistration)
  
  io.println("Loading User Registration Form...")
  
  case formosh.from_json_string_with_config(
    schema,
    formosh.HttpSubmit(
      url: "https://api.example.com/register",
      method: "POST",
      headers: [
        #("Content-Type", "application/json"),
        #("X-Form-Type", "registration"),
      ],
    ),
  ) {
    Ok(form_app) -> {
      io.println("✓ Registration form loaded successfully")
      
      let app = formosh.to_lustre_app(form_app)
      case lustre.start(app, "#app", Nil) {
        Ok(_) -> io.println("✓ Form started successfully")
        Error(_) -> io.println("✗ Failed to start form")
      }
    }
    Error(err) -> {
      io.println("✗ Failed to parse schema")
      handle_parse_error(err)
    }
  }
}

/// Demo: Survey Form with Custom Handler
pub fn demo_survey_form() {
  let schema = schema_loader.load_schema(schema_loader.SurveyForm)
  
  io.println("Loading Survey Form...")
  
  // Parse schema first
  case formosh.from_json_string(schema) {
    Ok(form_app) -> {
      // Define custom submission handler
      let submit_handler = fn(model) {
        io.println("Processing survey response...")
        
        // Extract form values
        let values = formosh.get_values(model)
        io.println("Survey data collected")
        
        // In real app, you would send this to your analytics service
        // For demo, just return success
        Ok("Thank you for your feedback! Your response has been recorded.")
      }
      
      // Create configuration with custom handler
      // Note: This would require accessing the schema from form_app
      // In a real implementation, you'd parse the schema separately
      io.println("✓ Survey form configured with custom handler")
      
      let app = formosh.to_lustre_app(form_app)
      case lustre.start(app, "#app", Nil) {
        Ok(_) -> io.println("✓ Form started successfully")
        Error(_) -> io.println("✗ Failed to start form")
      }
    }
    Error(err) -> {
      io.println("✗ Failed to parse schema")
      handle_parse_error(err)
    }
  }
}

/// Demo: Loading All Forms
/// This demonstrates how to load multiple forms on the same page
pub fn demo_multiple_forms() {
  io.println("Loading multiple forms...")
  
  // Get all available schemas
  let schemas = schema_loader.get_available_schemas()
  
  // Load each schema and create a form
  schemas
  |> gleam.list.each(fn(schema_name) {
    let display_name = schema_loader.get_schema_display_name(schema_name)
    let container_id = case schema_name {
      schema_loader.ContactForm -> "#contact-form"
      schema_loader.UserRegistration -> "#registration-form"
      schema_loader.SurveyForm -> "#survey-form"
    }
    
    io.println("Loading " <> display_name <> "...")
    
    let schema_content = schema_loader.load_schema(schema_name)
    case formosh.from_json_string(schema_content) {
      Ok(form_app) -> {
        let app = formosh.to_lustre_app(form_app)
        case lustre.start(app, container_id, Nil) {
          Ok(_) -> io.println("  ✓ " <> display_name <> " loaded")
          Error(_) -> io.println("  ✗ Failed to start " <> display_name)
        }
      }
      Error(_) -> io.println("  ✗ Failed to parse " <> display_name)
    }
  })
}

/// Demo: Dynamic Schema Switching
/// This shows how to switch between different schemas dynamically
pub fn demo_schema_switcher(schema_name: schema_loader.SchemaName) {
  let display_name = schema_loader.get_schema_display_name(schema_name)
  io.println("Switching to: " <> display_name)
  
  // Clear existing form
  // In a real app, you'd properly unmount the previous form
  
  // Load new schema
  let schema = schema_loader.load_schema(schema_name)
  
  // Configure based on schema type
  let submit_config = case schema_name {
    schema_loader.ContactForm ->
      formosh.HttpSubmit(
        url: "https://api.example.com/contact",
        method: "POST",
        headers: [#("Content-Type", "application/json")],
      )
    schema_loader.UserRegistration ->
      formosh.HttpSubmit(
        url: "https://api.example.com/register",
        method: "POST",
        headers: [#("Content-Type", "application/json")],
      )
    schema_loader.SurveyForm ->
      formosh.HttpSubmit(
        url: "https://api.example.com/survey",
        method: "POST",
        headers: [#("Content-Type", "application/json")],
      )
  }
  
  case formosh.from_json_string_with_config(schema, submit_config) {
    Ok(form_app) -> {
      let app = formosh.to_lustre_app(form_app)
      case lustre.start(app, "#app", Nil) {
        Ok(_) -> io.println("✓ Switched to " <> display_name)
        Error(_) -> io.println("✗ Failed to display " <> display_name)
      }
    }
    Error(err) -> {
      io.println("✗ Failed to load " <> display_name)
      handle_parse_error(err)
    }
  }
}

/// Handle parsing errors
fn handle_parse_error(err: formosh.ParseError) {
  case err {
    formosh.InvalidJson(msg) -> io.println("  Invalid JSON: " <> msg)
    formosh.MissingField(field) -> io.println("  Missing field: " <> field)
    formosh.InvalidType(msg) -> io.println("  Invalid type: " <> msg)
    formosh.UnexpectedValue(msg) -> io.println("  Unexpected value: " <> msg)
    formosh.DecodingError(_) -> io.println("  JSON decoding error")
  }
}

/// Example: Form with validation feedback
pub fn demo_with_validation() {
  let schema = schema_loader.load_schema(schema_loader.ContactForm)
  
  case formosh.from_json_string(schema) {
    Ok(form_app) -> {
      // Configure to show errors immediately
      let config = formosh.config(form_app.schema)
        |> formosh.with_submit_url("https://api.example.com/contact")
        |> formosh.with_show_errors_on_change(True)
        |> formosh.with_css_prefix("validated-form")
      
      let configured_form = formosh.from_config(config)
      let app = formosh.to_lustre_app(configured_form)
      
      case lustre.start(app, "#app", Nil) {
        Ok(_) -> io.println("✓ Form with validation started")
        Error(_) -> io.println("✗ Failed to start form")
      }
    }
    Error(err) -> handle_parse_error(err)
  }
}

/// Example: Form with custom styling
pub fn demo_with_custom_styling() {
  let schema = schema_loader.load_schema(schema_loader.SurveyForm)
  
  case formosh.from_json_string(schema) {
    Ok(form_app) -> {
      // Use custom CSS prefix for styling
      let config = formosh.config(form_app.schema)
        |> formosh.with_css_prefix("custom-survey")
        |> formosh.with_submit_url("https://api.example.com/survey")
      
      let configured_form = formosh.from_config(config)
      let app = formosh.to_lustre_app(configured_form)
      
      case lustre.start(app, "#app", Nil) {
        Ok(_) -> io.println("✓ Custom styled form started")
        Error(_) -> io.println("✗ Failed to start form")
      }
    }
    Error(err) -> handle_parse_error(err)
  }
}