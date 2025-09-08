# Formosh Library Usage Guide

## Migrating from Application to Library

Formosh has been refactored from a standalone application to a reusable library. This guide explains how to use Formosh as a library in your Gleam frontend application.

## Key Changes

1. **No more `main()` function** - The library no longer includes a main function or example schema
2. **Configuration-based initialization** - Forms are now created with explicit configuration
3. **Flexible submission handling** - Support for HTTP endpoints, custom handlers, or manual data extraction
4. **Builder pattern API** - Fluent API for configuring forms

## Basic Integration

### 1. Add to Dependencies

```toml
[dependencies]
formosh = "~> 0.1"
lustre = "~> 5.3"
gleam_json = "~> 3.0"
```

### 2. Simple Form Creation

```gleam
import formosh
import lustre

pub fn create_form(schema_string: String) {
  // Parse and create form
  case formosh.from_json_string(schema_string) {
    Ok(form_app) -> {
      // Convert to Lustre app
      let app = formosh.to_lustre_app(form_app)
      
      // Mount to DOM element
      lustre.start(app, "#my-form-container", Nil)
    }
    Error(err) -> {
      // Handle parsing error
      Error(err)
    }
  }
}
```

## Advanced Configuration

### HTTP Submission

```gleam
import formosh

pub fn create_form_with_api(schema_string: String, api_url: String) {
  // Create form with HTTP submission
  case formosh.from_json_string_with_config(
    schema_string,
    formosh.HttpSubmit(
      url: api_url,
      method: "POST",
      headers: [#("Content-Type", "application/json")],
    ),
  ) {
    Ok(form_app) -> {
      let app = formosh.to_lustre_app(form_app)
      lustre.start(app, "#form", Nil)
    }
    Error(err) -> Error(err)
  }
}
```

### Custom Submission Handler

```gleam
import formosh
import my_app/api

pub fn create_form_with_handler(schema: JsonSchema) {
  // Define how to handle form submission
  let submit_handler = fn(model) {
    // Extract form data
    let values = formosh.get_values(model)
    
    // Process with your application logic
    case api.submit_form_data(values) {
      Ok(response) -> Ok("Success: " <> response.message)
      Error(err) -> Error("Failed: " <> err.message)
    }
  }
  
  // Configure form
  let config = formosh.config(schema)
    |> formosh.with_custom_submit(submit_handler)
  
  // Create and start form
  let form = formosh.from_config(config)
  let app = formosh.to_lustre_app(form)
  lustre.start(app, "#form", Nil)
}
```

### Manual Data Extraction

```gleam
import formosh
import gleam/json

pub fn create_form_with_manual_submit(schema: JsonSchema) {
  // Create form without submission handler
  let config = formosh.config(schema)
  let form = formosh.from_config(config)
  
  // In your update function, handle submission manually
  let custom_update = fn(model, msg) {
    case msg {
      formosh.FormSubmit -> {
        // Extract and process data
        let values = formosh.get_values(model)
        let json_result = formosh.get_form_json(model)
        
        // Send to your API
        case json_result {
          Ok(json) -> send_to_api(json)
          Error(_) -> handle_error()
        }
        
        // Continue with normal update
        #(model, effect.none())
      }
      _ -> formosh.update(model, msg)
    }
  }
  
  // Use custom update function
  let form_with_custom = formosh.from_config_with_custom_update(
    config,
    custom_update,
  )
  
  let app = formosh.to_lustre_app(form_with_custom)
  lustre.start(app, "#form", Nil)
}
```

## Integration Patterns

### 1. Embedded in Larger Application

```gleam
// In your main application module
import formosh
import my_app/router
import my_app/state

pub fn init() {
  let app_state = state.init()
  
  // Create form when needed
  case router.current_route() {
    router.FormRoute(schema) -> {
      let form_config = formosh.config(schema)
        |> formosh.with_submit_url(app_state.api_url <> "/forms")
        |> formosh.with_css_prefix("app-form")
      
      let form = formosh.from_config(form_config)
      render_form(form)
    }
    _ -> render_other_content()
  }
}
```

### 2. Dynamic Schema Loading

```gleam
import formosh
import gleam/http
import gleam/json

pub fn load_and_create_form(schema_url: String) {
  // Fetch schema from API
  use response <- http.get(schema_url)
  
  case response {
    Ok(schema_json) -> {
      // Create form from fetched schema
      case formosh.from_json_string(schema_json) {
        Ok(form) -> {
          let app = formosh.to_lustre_app(form)
          lustre.start(app, "#dynamic-form", Nil)
        }
        Error(err) -> handle_parse_error(err)
      }
    }
    Error(err) -> handle_fetch_error(err)
  }
}
```

### 3. Multiple Forms

```gleam
import formosh

pub fn create_multiple_forms(schemas: List(#(String, JsonSchema))) {
  schemas
  |> list.map(fn(item) {
    let #(container_id, schema) = item
    
    let config = formosh.config(schema)
      |> formosh.with_css_prefix(container_id)
    
    let form = formosh.from_config(config)
    let app = formosh.to_lustre_app(form)
    
    lustre.start(app, "#" <> container_id, Nil)
  })
}
```

## CSS Customization

The library uses CSS classes with a configurable prefix (default: "formosh"):

```gleam
// Custom CSS prefix
let config = formosh.config(schema)
  |> formosh.with_css_prefix("my-form")
```

This will generate classes like:
- `my-form-container`
- `my-form-field`
- `my-form-input`
- `my-form-error`
- etc.

## Error Handling

Always handle potential errors when creating forms:

```gleam
case formosh.from_json_string(schema_json) {
  Ok(form) -> {
    // Success path
    start_form(form)
  }
  Error(err) -> {
    case err {
      formosh.InvalidJson(msg) -> log_error("Invalid JSON: " <> msg)
      formosh.MissingField(field) -> log_error("Missing: " <> field)
      formosh.InvalidType(msg) -> log_error("Type error: " <> msg)
      formosh.UnexpectedValue(msg) -> log_error("Unexpected: " <> msg)
      formosh.DecodingError(_) -> log_error("Decoding failed")
    }
  }
}
```

## Migration Checklist

- [ ] Remove direct imports of `formosh.main()`
- [ ] Replace `formosh.example_schema` with your own schema
- [ ] Add submission configuration (HTTP or custom handler)
- [ ] Update CSS classes if using custom prefix
- [ ] Handle parsing errors appropriately
- [ ] Test form submission with your backend

## Example Migration

### Before (as application):
```gleam
import formosh

pub fn main() {
  formosh.main()  // Used built-in example
}
```

### After (as library):
```gleam
import formosh

pub fn main() {
  let my_schema = load_schema_from_file("forms/contact.json")
  
  let config = formosh.config(my_schema)
    |> formosh.with_submit_url("https://api.myapp.com/contact")
    |> formosh.with_css_prefix("contact-form")
  
  let form = formosh.from_config(config)
  let app = formosh.to_lustre_app(form)
  
  case lustre.start(app, "#contact-form", Nil) {
    Ok(_) -> io.println("Form initialized")
    Error(err) -> io.println("Failed to start: " <> string.inspect(err))
  }
}
```

## Support

For issues or questions about using Formosh as a library, please refer to:
- [API Documentation](https://hexdocs.pm/formosh)
- [GitHub Issues](https://github.com/youruser/formosh/issues)
- [Example Application](./example/)