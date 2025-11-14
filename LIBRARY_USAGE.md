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
  // Parse and create form - returns a Lustre app directly
  case formosh.from_json_string(schema_string) {
    Ok(form_app) -> {
      // Mount directly to DOM element - no conversion needed
      lustre.start(form_app, "#my-form-container", Nil)
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
import lustre

pub fn create_form_with_api(schema_string: String, api_url: String) {
  // Parse schema first
  case formosh.parse_schema(schema_string) {
    Ok(schema) -> {
      // Create form with HTTP submission
      let config = formosh.config(schema)
        |> formosh.with_submit_url(api_url)

      let form_app = formosh.from_config(config)
      lustre.start(form_app, "#form", Nil)
    }
    Error(err) -> Error(err)
  }
}
```

### Custom Submission Handler

```gleam
import formosh
import gleam/dict
import lustre
import lustre/effect
import my_app/api

pub fn create_form_with_handler(schema: formosh.JsonSchema) {
  // Define how to handle form submission
  let submit_handler = fn(values: dict.Dict(String, formosh.Value)) {
    // Process with your application logic
    case api.submit_form_data(values) {
      Ok(response) -> effect.from(fn(_) {
        // Handle success - could dispatch a message or perform an action
        Nil
      })
      Error(err) -> effect.from(fn(_) {
        // Handle error
        Nil
      })
    }
  }

  // Configure form
  let config = formosh.config(schema)
    |> formosh.with_custom_submit(submit_handler)

  // Create and start form
  let form = formosh.from_config(config)
  lustre.start(form, "#form", Nil)
}
```

### Manual Data Extraction

```gleam
import formosh
import gleam/json
import lustre

pub fn create_form_with_manual_submit(schema: formosh.JsonSchema) {
  // Create form without submission handler
  let config = formosh.config(schema)
  let form = formosh.from_config(config)

  // Note: To handle submission manually, you would need to:
  // 1. Extract values using formosh.get_values() after mounting
  // 2. Listen for form submission events in your parent application
  // 3. Process the extracted values with your custom logic

  lustre.start(form, "#form", Nil)

  // In your parent app, you can access the form model's values:
  // let values = formosh.get_values(form_model)
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
      lustre.start(form, "#form-container", Nil)
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
          lustre.start(form, "#dynamic-form", Nil)
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

    lustre.start(form, "#" <> container_id, Nil)
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
    lustre.start(form, "#form", Nil)
  }
  Error(err) -> {
    // The 'err' variable contains the error message
    io.println("Failed to parse schema: " <> string.inspect(err))
  }
}
```


## Example Migration

### Before (as application):
```gleam
// The old version had a built-in example that ran automatically
// This is no longer available - you must provide your own schema
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

  case lustre.start(form, "#contact-form", Nil) {
    Ok(_) -> io.println("Form initialized")
    Error(err) -> io.println("Failed to start: " <> string.inspect(err))
  }
}
```