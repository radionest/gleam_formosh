# Important Knowledge: gleam/dynamic/decode API

These are critical insights about working with `gleam/dynamic/decode` module that were discovered while implementing the JSON Schema parser. This knowledge is not immediately obvious from documentation and can save hours of debugging.

## 1. Correct Parameter Order in `optional_field`

```gleam
// CORRECT - order is: key, default, decoder
decode.optional_field("description", None, decode.string)

// WRONG - this is NOT the correct order:
decode.optional_field("description", decode.string, None)
```

## 2. Handling Nested Option Types

When working with `optional_field` and `decode.optional()`:

```gleam
// To get Option(String), you need to wrap the decoder
decode.optional_field("title", None, decode.optional(decode.string))

// This returns Result(Option(Option(String)), error)
// Requires additional processing to simplify to Option(String)
```

## 3. Correct Usage of `decode.one_of`

```gleam
// CORRECT - no labeled arguments
decode.one_of([decoder1, decoder2, decoder3])

// WRONG - this syntax doesn't exist:
decode.one_of(first: decoder1, or: [decoder2, decoder3])
```

## 4. Extracting Data from Dynamic for Complex Logic

For extracting fields with conditional logic:

```gleam
// First get Dynamic
use dynamic_data <- decode.then(decode.dynamic)

// Then use decode.run to extract fields
let value = decode.run(dynamic_data, decode.at(["field"], decoder))
  |> option.from_result()  // NOT result.to_option() - that function doesn't exist!
```

## 5. Handling Recursive Structures

```gleam
// For recursive decoders, lazy evaluation is needed but not with decode.lazy
// Instead, reference the function directly
decode.optional_field("items", None, property_decoder())

// Note: decode.lazy doesn't exist in the current API
```

## 6. Working with `list.filter_map`

```gleam
// filter_map expects Result, not Option
list.filter_map(items, fn(item) {
  case decode.run(item, decoder) {
    Ok(value) -> Ok(value)     // Return Result
    Error(_) -> Error(Nil)      // NOT None!
  }
})
```

## 7. Constructors with Parameters

```gleam
// Some types like CustomFormat require parameters
CustomFormat(String)  // NOT just CustomFormat
```

## 8. Using Continuation-Style with `use`

```gleam
// Correct sequence of decoding with use
use field1 <- decode.field("key1", decoder1)
use field2 <- decode.optional_field("key2", default, decoder2)
use dynamic_data <- decode.then(decode.dynamic)

// Final result
decode.success(MyType(field1: field1, field2: field2))
```

## 9. Functions That Don't Exist in Gleam stdlib

Be aware these functions DO NOT exist:
- `result.to_option()` - use `option.from_result()` instead
- `decode.fail()` - use `decode.failure()` instead
- `decode.lazy()` - not available in current API
- `decode.decode7()` or similar numbered decode functions - use continuation style with `use` instead
- `decode.from()` - use `decode.run()` instead
- `decode.map_error()` - not available

## 10. JSON Schema Parsing Specifics

When parsing JSON Schema, remember:
- Constraints (minLength, maxLength, etc.) can be at the same level as type
- Properties and required are often at different hierarchy levels
- Need to handle both inline constraints and nested objects
- Arrays in JSON Schema have `items` field defining element schema
- Enums are represented as arrays of possible values

## 11. The `decode.run` Function

```gleam
// decode.run executes a decoder on dynamic data
// Returns Result(value, List(DecodeError))
let result = decode.run(dynamic_data, decoder)

// It's the primary way to execute decoders outside of the main decoding pipeline
```

## 12. Error Handling in Decoders

```gleam
// decode.failure creates a failing decoder
decode.failure(default_value, "error message")

// The first parameter is the "zero" value of the expected type
// The second parameter is the error message string
```

## Common Pitfalls to Avoid

1. **Don't assume parameter order** - always check the actual function signature
2. **Don't assume functions exist** - Gleam's stdlib is minimal by design
3. **Remember Result vs Option** - many functions expect Result, not Option
4. **Check constructor requirements** - some types need parameters
5. **Use continuation style** - modern Gleam uses `use` statements for complex decoding

## Practical Example: Complex JSON Parsing

```gleam
// Parse nested JSON with optional fields and constraints
fn parse_complex_json() -> Decoder(ComplexType) {
  use title <- decode.field("title", decode.string)
  use optional_desc <- decode.optional_field("description", None, decode.string)
  use properties <- decode.optional_field("properties", dict.new(), properties_decoder())
  use dynamic_data <- decode.then(decode.dynamic)
  
  // Extract inline constraints
  let constraints = extract_constraints(dynamic_data)
  
  decode.success(ComplexType(
    title: title,
    description: optional_desc,
    properties: properties,
    constraints: constraints
  ))
}

fn extract_constraints(data: Dynamic) -> Option(Constraints) {
  let min = decode.run(data, decode.at(["min"], decode.int))
    |> option.from_result()
  
  let max = decode.run(data, decode.at(["max"], decode.int))
    |> option.from_result()
  
  case min, max {
    None, None -> None
    _, _ -> Some(Constraints(min: min, max: max))
  }
}
```

This knowledge is essential for anyone working with JSON parsing in Gleam and should be incorporated into the development workflow.