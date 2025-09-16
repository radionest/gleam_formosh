# Formosh - JSON Schema Form Generator for Gleam

A powerful, type-safe form generator library for Gleam that creates dynamic forms from JSON Schema definitions. Built with the Lustre framework using the Model-View-Update (MVU) architecture.

## ✨ Features

- 📋 **JSON Schema Support** - Full support for JSON Schema draft 2020-12
- 🎯 **Type Safety** - Leverages Gleam's powerful type system
- 🏗️ **MVU Architecture** - Clean separation of concerns with Model-View-Update pattern
- 🎨 **Smart Field Rendering** - Automatic field type selection based on schema
- ✅ **Built-in Validation** - Comprehensive validation based on JSON Schema constraints
- 🔄 **Dynamic Forms** - Support for conditional schemas (if/then/else)
- 📦 **Web Components** - Use as custom HTML elements
- 🚀 **Zero Dependencies** - Minimal runtime overhead

## 📦 Installation

Add formosh to your `gleam.toml`:

```toml
[dependencies]
formosh = "~> 0.1"
```

## 🚀 Quick Start

### Basic Form

```gleam
import formosh
import lustre

pub fn main() {
  let schema = "
  {
    \"type\": \"object\",
    \"properties\": {
      \"name\": {
        \"type\": \"string\",
        \"title\": \"Full Name\"
      },
      \"email\": {
        \"type\": \"string\",
        \"format\": \"email\"
      }
    },
    \"required\": [\"name\", \"email\"]
  }"

  let assert Ok(app) = formosh.from_json_string(schema)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
}
```

### Using Web Components

```html
<!DOCTYPE html>
<html>
<head>
  <script type="module">
    import { register_formosh } from "./build/dev/javascript/formosh/formosh/component.mjs";
    register_formosh();
  </script>
</head>
<body>
  <formosh-form
    schema='{"type": "object", "properties": {"name": {"type": "string"}}}'
    submit-url="https://api.example.com/submit">
  </formosh-form>

  <script>
    // Listen for form events
    document.querySelector('formosh-form').addEventListener('formosh-submit', (e) => {
      console.log('Form submitted:', e.detail);
    });
  </script>
</body>
</html>
```

## 📚 Comprehensive Examples

### User Registration Form with Nested Objects

```gleam
import formosh
import lustre

pub fn main() {
  let schema = "
  {
    \"title\": \"User Registration\",
    \"type\": \"object\",
    \"properties\": {
      \"personal\": {
        \"type\": \"object\",
        \"title\": \"Personal Information\",
        \"properties\": {
          \"firstName\": {
            \"type\": \"string\",
            \"minLength\": 2
          },
          \"lastName\": {
            \"type\": \"string\",
            \"minLength\": 2
          },
          \"birthDate\": {
            \"type\": \"string\",
            \"format\": \"date\"
          }
        },
        \"required\": [\"firstName\", \"lastName\"]
      },
      \"account\": {
        \"type\": \"object\",
        \"title\": \"Account Details\",
        \"properties\": {
          \"username\": {
            \"type\": \"string\",
            \"pattern\": \"^[a-zA-Z0-9_]{3,20}$\"
          },
          \"password\": {
            \"type\": \"string\",
            \"minLength\": 8
          },
          \"email\": {
            \"type\": \"string\",
            \"format\": \"email\"
          }
        },
        \"required\": [\"username\", \"password\", \"email\"]
      }
    }
  }"

  let assert Ok(app) = formosh.from_json_string(schema)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
}
```

### Dynamic Array Fields

```gleam
let schema = "
{
  \"type\": \"object\",
  \"properties\": {
    \"skills\": {
      \"type\": \"array\",
      \"title\": \"Technical Skills\",
      \"items\": {
        \"type\": \"object\",
        \"properties\": {
          \"name\": {
            \"type\": \"string\",
            \"title\": \"Skill Name\"
          },
          \"level\": {
            \"type\": \"string\",
            \"enum\": [\"Beginner\", \"Intermediate\", \"Advanced\", \"Expert\"]
          }
        }
      }
    }
  }
}"
```

### Conditional Forms (if/then/else)

```gleam
let schema = "
{
  \"type\": \"object\",
  \"properties\": {
    \"hasLicense\": {
      \"type\": \"boolean\",
      \"title\": \"Do you have a driver's license?\"
    }
  },
  \"if\": {
    \"properties\": {
      \"hasLicense\": {\"const\": true}
    }
  },
  \"then\": {
    \"properties\": {
      \"licenseNumber\": {
        \"type\": \"string\",
        \"title\": \"License Number\"
      },
      \"expiryDate\": {
        \"type\": \"string\",
        \"format\": \"date\",
        \"title\": \"Expiry Date\"
      }
    },
    \"required\": [\"licenseNumber\", \"expiryDate\"]
  }
}"
```

### HTTP Form Submission

```gleam
import formosh
import lustre

pub fn main() {
  let schema_string = "{ ... }"  // Your JSON Schema
  let assert Ok(app) = formosh.from_json_string(schema_string)

  // Or with configuration:
  let assert Ok(schema) = schema/parser.parse_schema(schema_string)

  let form_config = formosh.config(schema)
    |> formosh.with_http_submit(
      url: "https://api.example.com/forms",
      method: "POST",
      headers: [
        #("Authorization", "Bearer token123"),
        #("Content-Type", "application/json")
      ]
    )
    |> formosh.with_css_prefix("my-form")

  let app = formosh.from_config(form_config)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
}
```

### Custom Submission Handler

```gleam
import formosh
import gleam/io
import gleam/json
import schema/parser

pub fn handle_submission(model) {
  // Extract form values
  let values = formosh.get_values(model)

  // Custom processing
  io.println("Form values received")
  // Your custom logic here
  Ok("Successfully processed!")
}

pub fn main() {
  let assert Ok(schema) = parser.parse_schema("{ ... }")

  let config = formosh.config(schema)
    |> formosh.with_custom_submit(handle_submission)

  let app = formosh.from_config(config)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
}
```

## 🎨 Field Rendering Rules

The library automatically selects the appropriate input type based on your schema:

| Schema Configuration | Rendered As |
|---------------------|-------------|
| `type: "string"` with `maxLength > 100` | Textarea |
| `type: "string"` with `enum` ≤ 5 options | Radio buttons |
| `type: "string"` with `enum` > 5 options | Select dropdown |
| `type: "string"` with `format: "email"` | Email input |
| `type: "string"` with `format: "date"` | Date picker |
| `type: "string"` with `format: "url"` | URL input |
| `type: "boolean"` | Yes/No radio buttons |
| `type: "number"` | Number input |
| `type: "integer"` | Integer input |
| `type: "array"` | Dynamic list with add/remove |
| `type: "object"` | Nested fieldset |

## 🔧 Advanced Features

### Schema References ($ref)

```json
{
  "$defs": {
    "address": {
      "type": "object",
      "properties": {
        "street": {"type": "string"},
        "city": {"type": "string"},
        "country": {"type": "string"}
      }
    }
  },
  "type": "object",
  "properties": {
    "billing": {"$ref": "#/$defs/address"},
    "shipping": {"$ref": "#/$defs/address"}
  }
}
```

### Validation Rules

All JSON Schema validation keywords are supported:

- **Strings**: `minLength`, `maxLength`, `pattern`, `format`
- **Numbers**: `minimum`, `maximum`, `exclusiveMinimum`, `exclusiveMaximum`, `multipleOf`
- **Arrays**: `minItems`, `maxItems`, `uniqueItems`
- **Objects**: `minProperties`, `maxProperties`, `required`
- **General**: `enum`, `const`, `type`

### CSS Customization

```gleam
let config = config.new(schema)
  |> config.with_css_prefix("my-app")
```

This generates classes like:
- `my-app-form`
- `my-app-field`
- `my-app-input`
- `my-app-error`
- `my-app-label`

## 📖 API Reference

### Core Functions

#### `formosh.from_schema(schema: JsonSchema) -> lustre.App(Nil, FormModel, FormMsg)`
Create a form application from a parsed JSON Schema.

#### `formosh.from_json_string(json: String) -> Result(lustre.App(Nil, FormModel, FormMsg), ParseError)`
Parse a JSON Schema string and create a form application.

### Configuration Builder

#### `formosh.config(schema: JsonSchema) -> FormConfig`
Create a new form configuration.

#### `formosh.from_config(config: FormConfig) -> lustre.App(Nil, FormModel, FormMsg)`
Create a form application from a configuration.

#### `formosh.with_http_submit(config, url, method, headers) -> FormConfig`
Configure HTTP submission.

#### `formosh.with_submit_url(config, url) -> FormConfig`
Configure HTTP submission with POST method.

#### `formosh.with_custom_submit(config, handler) -> FormConfig`
Set a custom submission handler.

#### `formosh.with_css_prefix(config, prefix) -> FormConfig`
Set CSS class prefix for styling.

#### `formosh.with_show_errors_on_change(config, show) -> FormConfig`
Configure when validation errors are shown.

### Utility Functions

#### `formosh.get_values(model: FormModel) -> Dict(String, Value)`
Extract current form values.

#### Schema Parsing (from schema/parser module)

#### `parser.parse_schema(json: String) -> Result(JsonSchema, ParseError)`
Parse a JSON Schema string into a schema type.

## 🏗️ Project Structure

```
formosh/
├── src/
│   ├── formosh.gleam              # Public API
│   ├── formosh/
│   │   └── component.gleam        # Web Component
│   ├── schema/
│   │   ├── types.gleam           # Schema types
│   │   ├── parser.gleam          # JSON parser
│   │   ├── validator.gleam       # Validation logic
│   │   └── resolver.gleam        # $ref resolution
│   ├── form/
│   │   ├── model.gleam           # Form state
│   │   ├── update.gleam          # State updates
│   │   ├── view.gleam            # HTML rendering
│   │   ├── path.gleam            # Path utilities
│   │   └── value.gleam           # Value transforms
│   └── fields/
│       └── [field_type].gleam    # Field renderers
├── test/                          # Test files
└── build/                         # Generated JavaScript
```

## 🛠️ Development

### Setup

```bash
# Install dependencies
gleam deps download

# Build the project
gleam build

# Run tests
gleam test

# Format code
gleam format
```

### Development Server

```bash
# Start dev server with hot reload (port 1234)
gleam run -m lustre/dev start

# Build for production
gleam run -m lustre/dev build app
```

## 🐛 Troubleshooting

### Common Issues

**Q: Form doesn't render**
- Ensure the target element exists in DOM
- Check browser console for errors
- Verify JSON Schema is valid

**Q: Validation not working**
- Check schema has correct validation keywords
- Ensure field names match schema properties
- Verify required fields are properly defined

**Q: Web Component not loading**
- Import and register the component before use
- Check module path is correct
- Ensure gleam build was run

## 🚧 Roadmap

- [x] Basic form generation
- [x] All primitive types
- [x] Nested objects
- [x] Dynamic arrays
- [x] $ref support
- [x] Conditional schemas (if/then/else)
- [x] Web Component export
- [x] HTTP submission
- [ ] oneOf/anyOf support
- [ ] File upload fields
- [ ] Custom field renderers
- [ ] Internationalization
- [ ] Form wizards/steps

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

MIT

## 🙏 Acknowledgments

Built with [Lustre](https://hexdocs.pm/lustre/) - A web framework for Gleam.

Based on [JSON Schema](https://json-schema.org/) specification.

## 💬 Support

For issues and questions, please use the [GitHub issue tracker](https://github.com/your-username/formosh/issues).