# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Formosh is a JSON Schema-based form generator library for Gleam/Lustre that creates dynamic, type-safe forms using the Model-View-Update (MVU) architecture. It parses JSON Schema (draft 2020-12) and generates fully functional forms with validation.

## Essential Commands

```bash
# Install dependencies
gleam deps download

# Build the project
gleam build

# Run tests
gleam test

# Run specific test module
gleam test --module parser_test

# Format code (ALWAYS run before committing)
gleam format

# Run development server with hot reload (port 1234)
gleam run -m lustre/dev start

# Build for production
gleam run -m lustre/dev build app

# Run example application
gleam run
```

## Architecture & Code Structure

### MVU Architecture Pattern
The codebase strictly follows Model-View-Update separation:
- **Model** (`form/model.gleam`): Immutable state with path-based field addressing
- **Update** (`form/update.gleam`): Pure functions for all state transitions
- **View** (`form/view.gleam`): Declarative HTML generation

### Path-Based Field System
Critical for nested data handling:
```gleam
// Path segments: PropertySegment(name) or ArraySegment(index)
// Example: [PropertySegment("lesions"), ArraySegment(0), PropertySegment("side")] → lesions[0].side

// Path operations in src/form/path.gleam:
to_string(path: FieldPath) -> String    // Convert to dot notation
get_field_name(path: FieldPath) -> String  // Extract final segment
```

### Core Modules
- `src/formosh.gleam`: Public API entry point
- `src/component.gleam`: Web Component integration
- `src/cdn.gleam`: CDN entry point for Web Component auto-registration
- `src/schema/`: JSON Schema parsing and validation
  - `types.gleam`: Core schema type definitions
  - `parser.gleam`: JSON to schema conversion
  - `validator.gleam`: Validation rule execution
  - `resolver.gleam`: $ref resolution
  - `conditional_resolver.gleam`: if/then/else conditional schema resolution
  - `serializer.gleam`: Schema-to-JSON serialization
- `src/form/`: MVU components and state management
  - `model.gleam`: Form state with field map
  - `update.gleam`: All state transitions and effects
  - `view.gleam`: HTML generation pipeline
  - `path.gleam`: Path manipulation utilities
  - `json_utils.gleam`: JSON value utilities
- `src/fields/`: Field-specific rendering logic
  - `string_field.gleam`, `number_field.gleam`, `boolean_field.gleam`, `array_field.gleam`, `object_field.gleam`: Per-type renderers
  - `field_common.gleam`: Shared rendering utilities (help text, labels, etc.)
- `src/validation/`: Validation utilities
  - `field_requirements.gleam`: Field requirement validation

## Critical Gleam/Dynamic Decoding Knowledge

The codebase uses specific patterns for `gleam/dynamic/decode`:
1. **Parameter order**: `decode.optional_field(key, default, decoder)` - NOT `(key, decoder, default)`
2. **Modern style**: Use `use` statements, not numbered decode functions
3. **Error conversion**: `option.from_result()` exists, `result.to_option()` does NOT
4. **Nested extraction**: Use `decode.run()` with `decode.dynamic` for conditional logic

### Common Decoding Patterns
```gleam
// Modern decode pattern with use
use type_value <- decode.field("type", decode.string)
use properties <- decode.optional_field("properties", dict.new(), decode.dict(decode.string, decode.dynamic))

// Conditional decoding
case type_value {
  "object" -> decode_object_schema(data)
  "array" -> decode_array_schema(data)
  _ -> decode_primitive_schema(data)
}
```

## Field Type Rendering Rules

- `maxLength > 100` → textarea
- `enum` with ≤5 options → radio buttons
- `enum` with >5 options → select dropdown
- Boolean fields → Yes/No radio buttons
- Format-specific inputs for email, date, url
- Arrays → Dynamic list with add/remove controls
- Objects → Nested fieldset with proper indentation
- Numbers with `multipleOf` → step attribute
- Fields with `description` → Help text below input

## Testing Strategy

Tests are in `test/` directory. Focus areas:
- Parser logic for JSON Schema
- Update functions (contain business logic)
- Path-based addressing for nested structures
- Validation rules and error handling
- Schema resolution ($ref, conditionals)
- Array field operations (add/remove/reorder)
- Form submission and error states

## Development Patterns

1. **Always use immutable data structures** - no mutable state
2. **Handle all Result types explicitly** - never ignore errors
3. **Use pattern matching** for control flow
4. **Keep update functions pure** for testability
5. **Place side effects only at boundaries** via Lustre effects
6. **Path-based operations** - Always use path utilities for nested fields
7. **Validation pipeline** - Validators compose and aggregate errors
8. **Effect management** - Use rsvp library for HTTP submissions

## Public API

Main functions in `src/formosh.gleam`:
```gleam
// Core form creation
from_schema(schema: JsonSchema) -> lustre.App(Nil, FormModel, FormMsg)
from_json_string(json: String) -> Result(lustre.App(Nil, FormModel, FormMsg), ParseError)
from_json_string_with_config(json_string: String, submit_config: SubmitConfig) -> Result(lustre.App(Nil, FormModel, FormMsg), ParseError)

// Configuration builder pattern
config(schema: JsonSchema) -> FormConfig
from_config(config: FormConfig) -> lustre.App(Nil, FormModel, FormMsg)
with_http_submit(config, url, method, headers) -> FormConfig
with_submit_url(config, url) -> FormConfig
with_custom_submit(config, handler) -> FormConfig
with_css_prefix(config, prefix) -> FormConfig
with_show_errors_on_change(config, show) -> FormConfig
with_show_readonly_fields(config, show) -> FormConfig
with_initial_values(config, values) -> FormConfig

// Utility functions
get_values(model: FormModel) -> Dict(String, Value)
```

## Important Files

- `index.html`: Development UI with embedded CSS
- `index_example.html`: Comprehensive example with multiple schemas
- `gleam.toml`: Dependencies and configuration
- `SHOULD_KNOW.md`: Detailed Gleam API quirks documentation
- `manifest.toml`: Package metadata
- `build/`: Generated JavaScript output (DO NOT EDIT)

**Note**: All .mjs files are auto-generated - do not read or edit them

## Advanced Implementation Details

### Schema Resolution Pipeline
The schema resolver handles complex JSON Schema features:

1. **$ref Resolution** (`src/schema/resolver.gleam`):
   - Resolves internal references (`#/$defs/...` and `#/definitions/...`)
   - Maintains visited set to prevent circular references
   - Merges resolved schemas with parent properties

2. **Conditional Schemas** (`src/schema/conditional_resolver.gleam`):
   - Evaluates if/then/else conditions based on current form values
   - Dynamically switches schema based on field values
   - Properly merges conditional properties

3. **Composition Keywords**:
   - `allOf`: Used for extracting conditional schemas (if/then/else within allOf items)
   - `oneOf/anyOf`: Not yet implemented

### Value Storage System
Form values are stored in a dictionary with dot-notation keys:

```gleam
// Values stored in model as Dict(String, Value)
model.values: Dict(String, Value)

// Example for nested object:
dict.from_list([
  #("user.name", StringValue("John")),
  #("user.age", NumberValue(30))
])
```

### Effect Management with RSVP
HTTP submissions use the rsvp library:
- Constructs proper HTTP requests
- Handles JSON serialization
- Returns success/error messages
- Manages loading states

### Web Component Integration
The `component.gleam` module:
- Registers as `<formosh-form>` custom HTML element
- Handles attribute changes (`schema`, `submit-url`, `submit-method`, `css-prefix`)
- Emits custom events (`formosh-ready`, `formosh-submitting`, `formosh-submit`, `formosh-change`)

## Common Pitfalls & Solutions

### Path Operations
- **Problem**: Incorrect path construction for nested fields
- **Solution**: Always use `path.gleam` utilities, never manual string concatenation

### Validation Timing
- **Problem**: Validation errors shown too early
- **Solution**: Check `touched_fields` state before displaying errors

### Array Field Indexing
- **Problem**: Index out of bounds after deletion
- **Solution**: Reindex array fields after any modification

### Schema Resolution
- **Problem**: Infinite loop with circular $refs
- **Solution**: Maintain visited set in resolver

## Debugging Tips

1. **Form State Inspection**:
   ```gleam
   io.debug(model.values)  // Check current values
   io.debug(model.errors)  // Check validation errors
   io.debug(model.touched_fields) // Check touched fields
   ```

2. **Path Debugging**:
   ```gleam
   io.debug(path.to_string(field.path))  // Verify path construction
   ```

3. **Schema Resolution**:
   ```gleam
   io.debug(resolved_schema)  // Check after resolution
   ```

4. **Update Flow**:
   - Add debug statements in update.gleam
   - Track message flow for complex operations

## Performance Considerations

1. **Large Forms**: Consider virtualizing array fields
2. **Validation**: Debounce validation for expensive rules
3. **Re-renders**: Use targeted updates via path system
4. **Schema Resolution**: Cache resolved schemas when possible

## Dependencies

- `lustre`: Web framework (>= 5.3.4)
- `gleam_json`: JSON parsing (>= 3.0.0)
- `gleam_stdlib`: Standard library (>= 0.44.0)
- `gleam_http`: HTTP types (>= 4.1.1)
- `rsvp`: HTTP client for submissions (>= 1.1.3)
- `simplifile`: File system operations (>= 2.3.1)
- `gleeunit`: Testing framework (dev)
- `lustre_dev_tools`: Development server (dev)