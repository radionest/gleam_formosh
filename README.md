# Formosh - JSON Schema Form Generator for Gleam

A type-safe, functional form generator library for Gleam that creates dynamic forms from JSON Schema definitions. Built with Lustre framework using the Model-View-Update (MVU) architecture.

## Features

- ✨ **JSON Schema Support** - Generate forms from JSON Schema (draft 2020-12)
- 🎯 **Type Safety** - Full type safety with Gleam's type system
- 🔧 **MVU Architecture** - Clean separation of concerns with Model-View-Update pattern
- 🎨 **Field Types** - Support for string, number, integer, boolean, array, and object types
- ✅ **Validation** - Built-in validation based on JSON Schema constraints
- 🎮 **Interactive** - Real-time field validation and error display
- 🚀 **Functional** - Pure functional approach with immutable data structures

## Installation

Add formosh to your `gleam.toml`:

```toml
[dependencies]
formosh = "~> 0.1"
lustre = "~> 5.3"
gleam_json = "~> 3.0"
```

## Quick Start

### Basic Usage

```gleam
import formosh
import lustre

pub fn main() {
  // Define your JSON Schema
  let schema = "
  {
    \"title\": \"Contact Form\",
    \"type\": \"object\",
    \"properties\": {
      \"name\": {
        \"type\": \"string\",
        \"title\": \"Name\",
        \"minLength\": 2
      },
      \"email\": {
        \"type\": \"string\",
        \"format\": \"email\"
      },
      \"message\": {
        \"type\": \"string\",
        \"maxLength\": 500
      }
    },
    \"required\": [\"name\", \"email\"]
  }"
  
  // Create and start the form application
  let assert Ok(form) = formosh.from_json_string(schema)
  let app = formosh.to_lustre_app(form)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  
  Nil
}
```

### With HTTP Submission

```gleam
import formosh

pub fn main() {
  let schema = "{ ... }"  // Your JSON Schema
  
  // Create form with HTTP submission
  let assert Ok(form) = formosh.from_json_string_with_config(
    schema,
    formosh.HttpSubmit(
      url: "https://api.example.com/submit",
      method: "POST",
      headers: [#("Content-Type", "application/json")],
    ),
  )
  
  let app = formosh.to_lustre_app(form)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
}
```

### Using Builder Pattern

```gleam
import formosh
import schema/parser

pub fn main() {
  let schema_string = "{ ... }"  // Your JSON Schema
  let assert Ok(schema) = parser.parse_schema(schema_string)
  
  // Configure form with builder pattern
  let config = formosh.config(schema)
    |> formosh.with_submit_url("https://api.example.com/forms")
    |> formosh.with_css_prefix("my-form")
    |> formosh.with_show_errors_on_change(False)
  
  let form = formosh.from_config(config)
  let app = formosh.to_lustre_app(form)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
}
```

### Custom Submission Handler

```gleam
import formosh
import gleam/io

pub fn main() {
  let schema = "{ ... }"  // Your JSON Schema
  let assert Ok(parsed_schema) = parser.parse_schema(schema)
  
  // Define custom submission handler
  let submit_handler = fn(model) {
    // Extract and process form data
    let values = formosh.get_values(model)
    io.println("Processing form data...")
    
    // Return success or error
    Ok("Form submitted successfully!")
  }
  
  // Create form with custom handler
  let config = formosh.config(parsed_schema)
    |> formosh.with_custom_submit(submit_handler)
  
  let form = formosh.from_config(config)
  let app = formosh.to_lustre_app(form)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
}
```

## Supported JSON Schema Features

### Field Types
- `string` - Text inputs, textareas, select dropdowns
- `number` - Floating point number inputs
- `integer` - Integer number inputs
- `boolean` - Radio buttons (Yes/No)
- `array` - Multiple selection, dynamic lists
- `object` - Nested form structures

### String Formats
- `email` - Email input validation
- `url` / `uri` - URL validation
- `date` - Date picker
- `date-time` - DateTime picker
- `time` - Time picker

### Validation Rules
- `required` - Required field validation
- `minLength` / `maxLength` - String length constraints
- `minimum` / `maximum` - Number range constraints
- `exclusiveMinimum` / `exclusiveMaximum` - Exclusive number ranges
- `pattern` - Regex pattern validation
- `enum` - Enumeration values (rendered as select or radio)
- `multipleOf` - Number step validation

### Special Features
- `enum` - Renders as radio buttons (≤5 options) or select dropdown (>5 options)
- `maxLength > 100` - Automatically renders as textarea
- `description` - Shows help text under fields
- `title` - Custom field labels

## Architecture

The library follows the MVU (Model-View-Update) pattern:

### Model
Manages the form state including:
- Current field values
- Validation errors
- Touched/dirty states
- Submission status

### Update
Handles all form events:
- Field value changes
- Field focus/blur
- Form submission
- Validation triggers

### View
Renders the form UI:
- Dynamic field generation based on schema
- Error display
- Submit/reset buttons
- Real-time validation feedback

## Project Structure

```
formosh/
├── src/
│   ├── formosh.gleam           # Main entry point
│   ├── schema/
│   │   ├── types.gleam         # JSON Schema type definitions
│   │   ├── parser.gleam        # JSON Schema parser
│   │   └── validator.gleam     # Field validation logic
│   ├── form/
│   │   ├── model.gleam         # Form state model
│   │   ├── update.gleam        # Update functions
│   │   └── view.gleam          # View rendering
│   └── fields/
│       ├── string_field.gleam  # String field renderer
│       ├── number_field.gleam  # Number field renderer
│       ├── boolean_field.gleam # Boolean field renderer
│       ├── array_field.gleam   # Array field renderer
│       └── object_field.gleam  # Object field renderer
```

## API Reference

### Core Functions

#### `formosh.config(schema: JsonSchema) -> FormConfig`
Create a form configuration with default settings.

#### `formosh.from_schema(schema: JsonSchema) -> FormApp`
Create a form application from a JSON Schema.

#### `formosh.from_config(config: FormConfig) -> FormApp`
Create a form application from a configuration.

#### `formosh.from_json_string(json: String) -> Result(FormApp, ParseError)`
Parse JSON Schema string and create a form.

#### `formosh.to_lustre_app(form: FormApp) -> lustre.App`
Convert FormApp to a Lustre application.

### Configuration Functions

#### `with_submit_url(config: FormConfig, url: String) -> FormConfig`
Add HTTP POST submission to the form.

#### `with_http_submit(config: FormConfig, url: String, method: String, headers: List(#(String, String))) -> FormConfig`
Add HTTP submission with custom method and headers.

#### `with_custom_submit(config: FormConfig, handler: fn(FormModel) -> Result(String, String)) -> FormConfig`
Add custom submission handler function.

#### `with_css_prefix(config: FormConfig, prefix: String) -> FormConfig`
Set CSS class prefix for styling.

#### `with_show_errors_on_change(config: FormConfig, show: Bool) -> FormConfig`
Configure error display behavior.

### Utility Functions

#### `get_values(model: FormModel) -> Dict(String, FieldValue)`
Extract current form values.

#### `get_errors(model: FormModel) -> List(#(String, List(ValidationError)))`
Get current validation errors.

#### `is_valid(model: FormModel) -> Bool`
Check if form is valid for submission.

#### `get_form_json(model: FormModel) -> Result(String, String)`
Convert form data to JSON string.

## Development

### Building

```bash
cd formosh
gleam build
```

### Testing

```bash
gleam test
```

### Running the Example

```bash
cd example
gleam run -m lustre/dev start
```

Then open `http://localhost:1234` in your browser.

## Example Schema

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "User Registration",
  "description": "Complete user registration form",
  "type": "object",
  "properties": {
    "personalInfo": {
      "type": "object",
      "title": "Personal Information",
      "properties": {
        "firstName": {
          "type": "string",
          "title": "First Name",
          "minLength": 2
        },
        "lastName": {
          "type": "string",
          "title": "Last Name",
          "minLength": 2
        },
        "age": {
          "type": "integer",
          "minimum": 18,
          "maximum": 120
        }
      },
      "required": ["firstName", "lastName"]
    },
    "contact": {
      "type": "object",
      "title": "Contact Details",
      "properties": {
        "email": {
          "type": "string",
          "format": "email"
        },
        "phone": {
          "type": "string",
          "pattern": "^[0-9-+()\\s]+$"
        }
      },
      "required": ["email"]
    },
    "preferences": {
      "type": "object",
      "title": "Preferences",
      "properties": {
        "newsletter": {
          "type": "boolean",
          "title": "Subscribe to newsletter?"
        },
        "notifications": {
          "type": "array",
          "title": "Notification Preferences",
          "items": {
            "enum": ["email", "sms", "push"]
          }
        }
      }
    }
  },
  "required": ["personalInfo", "contact"]
}
```

## Roadmap

- [ ] Complete array field implementation
- [ ] Complete object field implementation  
- [ ] Support for `$ref` and `$defs`
- [ ] Support for `oneOf`, `anyOf`, `allOf`
- [ ] Conditional schemas (`if`/`then`/`else`)
- [ ] Custom field renderers
- [ ] Form data serialization
- [ ] Async validation support
- [ ] Custom themes and styling
- [ ] File upload support
- [ ] Multi-step forms

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT

## Inspiration

This project is inspired by:
- [Formosh](https://github.com/your-repo/formosh) - Python JSON Schema form generator
- [Lustre](https://hexdocs.pm/lustre/) - Gleam web framework
- [JSON Schema](https://json-schema.org/) - JSON Schema specification

## Support

For issues and questions, please use the GitHub issue tracker.