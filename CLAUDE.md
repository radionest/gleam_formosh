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

## Architecture

The codebase strictly follows Model-View-Update separation:
- **Model** (`formosh/form/model.gleam`): Immutable state with path-based field addressing
- **Update** (`formosh/form/update.gleam`): Pure functions for all state transitions
- **View** (`formosh/form/view.gleam`): Declarative HTML generation

### Path-Based Field System
Critical for nested data handling — always use `path.gleam` utilities, never manual string concatenation:
```gleam
// Path segments: PropertySegment(name) or ArraySegment(index)
// Example: [PropertySegment("lesions"), ArraySegment(0), PropertySegment("side")] → lesions[0].side
to_string(path: FieldPath) -> String    // Convert to dot notation
get_field_name(path: FieldPath) -> String  // Extract final segment
```

Form values are stored as `Dict(String, Value)` with dot-notation keys (e.g. `"user.name"` → `StringValue("John")`).

## Common Pitfalls

- **Paths**: Always use `path.gleam` utilities for nested fields, never string concatenation
- **Validation timing**: Check `touched_fields` before displaying errors
- **Array indexing**: Reindex array fields after any add/remove operation
- **Circular $refs**: Resolver maintains visited set — do not bypass it

## Web Component

Registers as `<formosh-form>` custom element. Attributes: `schema`, `submit-url`, `submit-method`, `css-prefix`, `show-readonly-fields`, `upload-base-url`. Emits events: `formosh-ready`, `formosh-submitting`, `formosh-submit`, `formosh-change`.

## Notes

- All `.mjs` files are auto-generated — do not read or edit them (except `src/formosh/ffi/*_ffi.mjs` which are hand-written FFI)
- `oneOf`/`anyOf` composition keywords are not yet implemented
- `x-widget: "image-upload"` works only on top-level properties; nested image-upload fields (inside objects/arrays) are not yet supported
- HTTP submissions use the `rsvp` library for effect management
