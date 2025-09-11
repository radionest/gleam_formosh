# Type System Refactoring Plan

## Current Problem

The Formosh library currently has two nearly identical types that create unnecessary complexity:

### Current Type Definitions

```gleam
// In schema/types.gleam

pub type JsonValue {
  JsonString(String)
  JsonNumber(Float)
  JsonInteger(Int)
  JsonBool(Bool)
  JsonNull
  JsonArray(List(JsonValue))
  JsonObject(List(#(String, JsonValue)))
}

pub type FieldValue {
  StringValue(String)
  NumberValue(Float)
  IntegerValue(Int)
  BooleanValue(Bool)
  NullValue
  ArrayValue(List(JsonValue))    // ⚠️ Uses JsonValue, not FieldValue!
  ObjectValue(List(#(String, JsonValue)))  // ⚠️ Uses JsonValue, not FieldValue!
}
```

### Issues with Current Architecture

1. **Mixed Type System**: `FieldValue` uses `JsonValue` for nested structures, creating inconsistency
2. **Redundant Conversions**: Need converters between two nearly identical types
3. **Cognitive Overhead**: Developers must remember when to use which type
4. **Maintenance Burden**: Changes need to be made in multiple places

### Current Usage Patterns

- **JsonValue** is used for:
  - Schema defaults (`default: Option(JsonValue)`)
  - Enum values (`enum_values: Option(List(JsonValue))`)
  - Nested structures inside FieldValue

- **FieldValue** is used for:
  - Form values storage (`values: Dict(String, FieldValue)`)
  - Validation functions
  - Update operations

## Proposed Solution: Unified Type System

### Step 1: Create New Unified Type

```gleam
// In schema/types.gleam

/// Unified value type for both schema definitions and form values
pub type Value {
  StringValue(String)
  NumberValue(Float)
  IntegerValue(Int)
  BooleanValue(Bool)
  NullValue
  ArrayValue(List(Value))    // ✅ Recursive, uses Value
  ObjectValue(List(#(String, Value)))  // ✅ Recursive, uses Value
}
```

### Step 2: Migration Strategy

#### Phase 1: Add Unified Type (Non-breaking)
1. Add the new `Value` type alongside existing types
2. Create migration helpers:
   ```gleam
   pub fn field_value_to_value(fv: FieldValue) -> Value
   pub fn json_value_to_value(jv: JsonValue) -> Value
   pub fn value_to_field_value(v: Value) -> FieldValue
   pub fn value_to_json_value(v: Value) -> JsonValue
   ```

#### Phase 2: Migrate Core Components
1. Update `FormModel`:
   ```gleam
   pub type FormModel {
     FormModel(
       values: Dict(String, Value),  // Changed from FieldValue
       // ... other fields
     )
   }
   ```

2. Update `SchemaProperty`:
   ```gleam
   pub type SchemaProperty {
     SchemaProperty(
       default: Option(Value),  // Changed from JsonValue
       enum_values: Option(List(Value)),  // Changed from List(JsonValue)
       // ... other fields
     )
   }
   ```

#### Phase 3: Update Dependencies
Files to modify (in order):

1. **schema/types.gleam**
   - Add new `Value` type
   - Add migration functions

2. **form/converter.gleam**
   - Can be deleted after migration
   - Or temporarily keep with migration helpers

3. **form/model.gleam**
   - Update `values: Dict(String, Value)`
   - Update all functions using values

4. **form/update.gleam**
   - Update value handling functions
   - Remove conversion calls

5. **form/path.gleam**
   - Update path traversal to use `Value`
   - Simplify nested value handling

6. **schema/validator.gleam**
   - Update validation functions to use `Value`

7. **schema/conditional_resolver.gleam**
   - Update conditional logic to use `Value`

8. **form/view.gleam**
   - Update view rendering to use `Value`

9. **fields/*.gleam** (all field modules)
   - Update to use `Value` type

10. **schema/parser.gleam**
    - Update decoder to produce `Value`
    - Rename `json_value_decoder()` to `value_decoder()`

11. **formosh/component.gleam**
    - Update to use `Value` for event emission
    - Simplify conversion to `gleam/json`

#### Phase 4: Cleanup
1. Remove old `JsonValue` and `FieldValue` types
2. Remove converter module if no longer needed
3. Update documentation

### Benefits of Unified System

1. **Consistency**: Single type throughout the codebase
2. **Simplicity**: No need for converters between similar types
3. **Performance**: Fewer conversions = better performance
4. **Maintainability**: Changes in one place affect entire system
5. **Type Safety**: Recursive type definition ensures consistency at all levels

### Implementation Checklist

- [ ] Create new `Value` type in schema/types.gleam
- [ ] Add migration helper functions
- [ ] Update FormModel to use Value
- [ ] Update SchemaProperty to use Value
- [ ] Update form/update.gleam functions
- [ ] Update form/path.gleam traversal
- [ ] Update validators
- [ ] Update conditional resolver
- [ ] Update view rendering
- [ ] Update all field modules
- [ ] Update parser/decoder
- [ ] Update component for event emission
- [ ] Remove old types
- [ ] Remove converter module
- [ ] Update tests
- [ ] Update documentation

### Conversion to gleam/json

With the unified type, conversion to `gleam/json` becomes straightforward:

```gleam
import gleam/json

pub fn value_to_json(value: Value) -> json.Json {
  case value {
    StringValue(s) -> json.string(s)
    NumberValue(n) -> json.float(n)
    IntegerValue(i) -> json.int(i)
    BooleanValue(b) -> json.bool(b)
    NullValue -> json.null()
    ArrayValue(items) -> 
      json.array(items, of: value_to_json)
    ObjectValue(fields) -> 
      json.object(
        fields |> list.map(fn(pair) {
          let #(key, val) = pair
          #(key, value_to_json(val))
        })
      )
  }
}
```
