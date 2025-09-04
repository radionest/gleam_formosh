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
lustre = "~> 4.6"
gleam_json = "~> 1.0"
```

## Quick Start

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