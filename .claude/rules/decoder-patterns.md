---
paths:
  - "src/formosh/schema/**/*.gleam"
---

# Decoder patterns specific to formosh JSON Schema parser

## Nested Option handling

`optional_field` + `decode.optional()` produces `Option(Option(String))` — needs flattening:

```gleam
decode.optional_field("title", None, decode.optional(decode.string))
// Result type: Result(Option(Option(String)), error) — flatten with option.flatten()
```

## Dynamic extraction inside decode pipeline

Use `decode.then(decode.dynamic)` to get raw Dynamic, then `decode.run` for conditional logic:

```gleam
use dynamic_data <- decode.then(decode.dynamic)
let value = decode.run(dynamic_data, decode.at(["field"], decoder))
  |> option.from_result()
```

## decode.failure signature

First argument is the "zero" value of the expected type, second is the error message:

```gleam
decode.failure(default_value, "error message")
```

## Recursive structures

Reference the decoder function directly — `decode.lazy()` does not exist:

```gleam
decode.optional_field("items", None, property_decoder())
```

## JSON Schema specifics

- Constraints (minLength, maxLength, etc.) live at the same level as `type`
- `properties` and `required` are often at different hierarchy levels
- Handle both inline constraints and nested objects
- `const` is represented as single-element `enum_values`
- Arrays use `items` field for element schema
- Enums are arrays of possible values
