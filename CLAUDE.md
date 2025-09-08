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
// Example: ["lesions", ArraySegment(0), "side"] → lesions[0].side
```

### Core Modules
- `src/formosh.gleam`: Public API entry point
- `src/schema/`: JSON Schema parsing and validation
- `src/form/`: MVU components and state management
- `src/fields/`: Field-specific rendering logic

## Critical Gleam/Dynamic Decoding Knowledge

The codebase uses specific patterns for `gleam/dynamic/decode`:
1. **Parameter order**: `decode.optional_field(key, default, decoder)` - NOT `(key, decoder, default)`
2. **Modern style**: Use `use` statements, not numbered decode functions
3. **Error conversion**: `option.from_result()` exists, `result.to_option()` does NOT
4. **Nested extraction**: Use `decode.run()` with `decode.dynamic` for conditional logic

## Field Type Rendering Rules

- `maxLength > 100` → textarea
- `enum` with ≤5 options → radio buttons
- `enum` with >5 options → select dropdown
- Boolean fields → Yes/No radio buttons
- Format-specific inputs for email, date, url

## Testing Strategy

Tests are in `test/` directory. Focus areas:
- Parser logic for JSON Schema
- Update functions (contain business logic)
- Path-based addressing for nested structures
- Validation rules and error handling

## Development Patterns

1. **Always use immutable data structures** - no mutable state
2. **Handle all Result types explicitly** - never ignore errors
3. **Use pattern matching** for control flow
4. **Keep update functions pure** for testability
5. **Place side effects only at boundaries** via Lustre effects

## Public API

Main functions in `src/formosh.gleam`:
```gleam
from_schema(schema: JsonSchema) -> FormApp
from_json_string(json: String) -> Result(FormApp, ParseError)
to_lustre_app(form_app: FormApp) -> lustre.App(Nil, FormModel, FormMsg)
```

## Important Files

- `index.html`: Development UI with embedded CSS
- `gleam.toml`: Dependencies and configuration
- `SHOULD_KNOW.md`: Detailed Gleam API quirks documentation

**Note**: mjs все файлы если не указано обратное являются автоматически сгененрированными и читать их не надо

## Dependencies

- `lustre`: Web framework (5.3.4+)
- `gleam_json`: JSON parsing (3.0.0+)
- `gleam_stdlib`: Standard library
- `gleeunit`: Testing framework (dev)
- `lustre_dev_tools`: Development server (dev)