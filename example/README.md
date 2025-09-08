# Formosh Examples

This directory contains example schemas and demonstration code for the Formosh library.

## Directory Structure

```
example/
├── schemas/              # JSON Schema files
│   ├── contact_form.json      # Simple contact form
│   ├── user_registration.json # Complex registration form
│   └── survey_form.json       # Customer survey form
├── app.gleam            # Main example application
├── schema_loader.gleam  # Utility for loading schemas
├── index.html          # HTML page for running examples
└── README.md           # This file
```

## Available Schemas

### 1. Contact Form (`contact_form.json`)
A simple contact form demonstrating:
- Basic text fields (name, email, phone)
- Email validation with format
- Phone number pattern validation
- Select dropdown (subject)
- Textarea for longer text (message)
- Boolean checkbox (newsletter subscription)
- Required field validation

**Use case:** Customer support, feedback collection, general inquiries

### 2. User Registration (`user_registration.json`)
A comprehensive registration form showcasing:
- Nested objects (personal info, account, address, preferences)
- Various field types (string, integer, boolean, array)
- Date fields with format validation
- Password fields with minimum length
- Email confirmation fields
- Country/timezone selection with enums
- Multiple checkbox selections (notifications)
- Complex validation rules
- Terms and conditions acceptance

**Use case:** User onboarding, account creation, KYC forms

### 3. Survey Form (`survey_form.json`)
A dynamic survey form featuring:
- Rating scales (1-5, 1-10)
- Multiple choice questions
- Conditional sections
- Array fields for multiple selections
- Text feedback areas
- Demographic questions
- Nested question groups

**Use case:** Customer satisfaction surveys, feedback collection, market research

## Running the Examples

### Basic Setup

1. Install dependencies (from project root):
```bash
gleam deps download
```

2. Choose and run a demo:

**Contact Form Demo:**
```bash
gleam run -m lustre/dev start --entry=example/demo_contact
```

**Registration Form Demo:**
```bash
gleam run -m lustre/dev start --entry=example/demo_registration
```

**Survey Form Demo:**
```bash
gleam run -m lustre/dev start --entry=example/demo_survey
```

3. Open `http://localhost:1234` in your browser

### Available Demo Files

#### `demo_contact.gleam`
Simple contact form with:
- Text inputs with validation
- Email format validation
- Select dropdown for subject
- Textarea for message
- Newsletter subscription checkbox

#### `demo_registration.gleam`
Complex registration form with:
- Nested personal information section
- Account credentials with pattern validation
- Address information with country selection
- Terms and privacy agreement checkboxes

#### `demo_survey.gleam`
Customer survey form with:
- Customer type selection
- Rating scales (1-5 and 1-10)
- Satisfaction metrics
- Open-ended feedback fields
- Future engagement preferences

### Advanced Examples in `app.gleam`

The `app.gleam` file contains additional examples for:
- Loading schemas from files
- Using custom submission handlers
- Implementing schema switching
- Configuring validation behavior
- Applying custom CSS prefixes

## Using Schemas in Your Project

### Method 1: Direct String Import
```gleam
import formosh

const my_schema = "{...}" // Your JSON schema as string

pub fn main() {
  case formosh.from_json_string(my_schema) {
    Ok(form) -> // Use form
    Error(err) -> // Handle error
  }
}
```

### Method 2: Load from File (requires file I/O)
```gleam
import formosh
import simplifile  // or your file reading library

pub fn main() {
  case simplifile.read("schemas/contact_form.json") {
    Ok(schema_content) -> {
      case formosh.from_json_string(schema_content) {
        Ok(form) -> // Use form
        Error(err) -> // Handle parsing error
      }
    }
    Error(err) -> // Handle file error
  }
}
```

### Method 3: With Configuration
```gleam
import formosh
import schema/parser

pub fn main() {
  let schema_str = "..." // Your schema
  case parser.parse_schema(schema_str) {
    Ok(schema) -> {
      let config = formosh.config(schema)
        |> formosh.with_submit_url("https://api.example.com/submit")
        |> formosh.with_css_prefix("my-form")
      
      let form = formosh.from_config(config)
      // Use form
    }
    Error(err) -> // Handle error
  }
}
```

## Customizing Schemas

### Adding New Fields

To add a new field to any schema, add it to the `properties` object:

```json
{
  "properties": {
    "newField": {
      "type": "string",
      "title": "New Field Label",
      "description": "Help text for the field",
      "minLength": 2,
      "maxLength": 100
    }
  }
}
```

### Making Fields Required

Add the field name to the `required` array:

```json
{
  "required": ["name", "email", "newField"]
}
```

### Adding Validation

Common validation properties:
- `minLength` / `maxLength` - String length
- `minimum` / `maximum` - Number range
- `pattern` - Regex pattern
- `format` - Predefined formats (email, date, url)
- `enum` - List of allowed values

## Schema Best Practices

1. **Use descriptive titles and descriptions** - They become labels and help text
2. **Group related fields** - Use nested objects for logical grouping
3. **Set appropriate validation** - Balance security with user experience
4. **Use enums for fixed options** - Better UX than free text
5. **Consider field order** - JSON object properties maintain order
6. **Test with real data** - Ensure validation rules aren't too restrictive

## Styling Forms

Forms use CSS classes with configurable prefix (default: "formosh"):

```css
.formosh-container { /* Main form container */ }
.formosh-field-wrapper { /* Individual field wrapper */ }
.formosh-label { /* Field labels */ }
.formosh-input { /* Input fields */ }
.formosh-error { /* Error messages */ }
.formosh-required { /* Required field indicator */ }
```

To use custom prefix:
```gleam
let config = formosh.config(schema)
  |> formosh.with_css_prefix("my-app")
```

## Troubleshooting

### Form doesn't render
- Check browser console for errors
- Verify the DOM element ID exists
- Ensure schema is valid JSON

### Validation not working
- Check field names match exactly
- Verify validation rules are properly formatted
- Test with simpler validation first

### Submission fails
- Check network tab for API errors
- Verify submission URL is correct
- Test with custom handler first

## Contributing

To add new example schemas:
1. Create a new JSON file in `schemas/`
2. Add loader function in `schema_loader.gleam`
3. Create demo function in `app.gleam`
4. Update this README

## Resources

- [JSON Schema Documentation](https://json-schema.org/)
- [Formosh API Reference](../README.md#api-reference)
- [Lustre Framework](https://hexdocs.pm/lustre/)