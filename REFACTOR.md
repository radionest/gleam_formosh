# Refactoring Plan for Formosh

## Executive Summary

This document outlines critical refactoring needs for the Formosh codebase based on KISS (Keep It Simple, Stupid), YAGNI (You Aren't Gonna Need It), and DRY (Don't Repeat Yourself) principles analysis. The codebase shows good functional programming practices but suffers from significant code duplication, premature abstractions, and unnecessary complexity.

## Critical Issues by Principle

### 🔴 DRY Violations (Don't Repeat Yourself)

#### 1. **Duplicated Label Rendering** [HIGH PRIORITY]
**Files affected:**
- `src/fields/field_common.gleam` (lines 26-50)
- `src/fields/number_field.gleam` (lines 150-174)
- `src/fields/boolean_field.gleam` (lines 254-278)

**Problem:**
```gleam
// Identical code in 3+ files
fn render_label(field_name: String, property: types.SchemaProperty, is_required: Bool) -> Element(FormMsg) {
  let label_text = case property.title {
    Some(title) -> title
    None -> field_name |> string.replace("_", " ") |> string.capitalise()
  }
  // ... rest of identical implementation
}
```

**Solution:** Use only the version in `field_common.gleam`, remove all duplicates.

#### 2. **Duplicated Help Text Rendering** [HIGH PRIORITY]
**Files affected:**
- `src/fields/field_common.gleam` (lines 63-71)
- `src/fields/number_field.gleam` (lines 186-194)
- `src/fields/boolean_field.gleam` (lines 328-336)

**Problem:** Same help text rendering logic repeated across modules.

**Solution:** Consolidate into `field_common.gleam`.

#### 3. **JSON/FieldValue Conversion Duplication** [HIGH PRIORITY]
**Files affected:**
- `src/form/model.gleam` (lines 418-428)
- `src/form/path.gleam` (lines 237-248)
- `src/form/view.gleam` (lines 302-312)
- `src/form/update.gleam` (lines 237-248)

**Problem:** Same conversion logic scattered across 4+ modules.

**Solution:** Create a dedicated converter module `src/form/converter.gleam`.

#### 4. **Validation Pattern Repetition** [MEDIUM PRIORITY]
**File:** `src/schema/validator.gleam`

**Problem:**
```gleam
// This pattern repeats for every constraint check
let errors = case constraints.minimum {
  Some(min) -> {
    case value <. min {
      True -> list.append(errors, [ValidationError(...)])
      False -> errors
    }
  }
  None -> errors
}
```

**Solution:** Extract helper function `check_constraint(value, constraint, error_builder)`.

### ⚠️ YAGNI Violations (You Aren't Gonna Need It)

#### 1. **Unused Boolean Renderers** [MEDIUM PRIORITY]
**File:** `src/fields/boolean_field.gleam`

**Problem:**
```gleam
pub fn render_as_checkbox(...) // Never used
pub fn render_as_toggle(...)    // Never used
pub fn render(...)              // Only this is used
```

**Solution:** Remove `render_as_checkbox` and `render_as_toggle` functions.

#### 2. **Premature Path Abstraction** [HIGH PRIORITY]
**File:** `src/form/path.gleam`

**Unused functions:**
- `add_array_item_at_path` (lines 265-290)
- `remove_array_item_at_path` (lines 292-320)
- Complex nested operations that aren't needed

**Solution:** Remove until actually needed, keep only basic path operations.

#### 3. **Overbuilt Model API** [MEDIUM PRIORITY]
**File:** `src/form/model.gleam`

**Unused functions:**
- `get_value_at_path` (lines 357-374)
- `set_value_at_path` (lines 521-532)
- `has_errors_at_path` (lines 483-488)
- `get_errors_at_path` (lines 499-508)

**Solution:** Remove all unused path-based accessors.

#### 4. **Unused String Formats** [LOW PRIORITY]
**File:** `src/schema/types.gleam`

**Problem:**
```gleam
pub type StringFormat {
  DateFormat        // Used
  DateTimeFormat    // Not used
  TimeFormat        // Not used
  UuidFormat        // Not used
  RegexFormat       // Not used
  EmailFormat       // Used
  UrlFormat         // Used
}
```

**Solution:** Comment out or remove unused formats.

### 💡 KISS Violations (Keep It Simple, Stupid)

#### 1. **Over-Complex Path System** [HIGH PRIORITY]
**File:** `src/form/path.gleam` (lines 111-300)

**Problem:**
```gleam
pub fn modify_at_path(
  root: types.FieldValue,
  path: FieldPath,
  modifier: fn(types.FieldValue) -> types.FieldValue,
) -> types.FieldValue {
  // Deep recursive nesting with multiple case statements
  case path {
    [] -> modifier(root)
    [segment, ..rest] -> {
      case segment {
        PropertySegment(name) ->
          modify_object_field(root, name, fn(field_value) {
            modify_at_path(field_value, rest, modifier)
          })
        // ... more complex nesting
```

**Solution:** Simplify for actual use cases, reduce nesting depth.

#### 2. **Excessive Conversion Complexity** [HIGH PRIORITY]
**File:** `src/form/update.gleam` (lines 42-147)

**Problem:** Multiple conversions between representations in every update:
1. Model values → JSON values
2. JSON values → Root value
3. Root value → Field value
4. Field value → Back to model

**Solution:** Direct field updates without intermediate conversions where possible.

#### 3. **Complex Array Handling** [MEDIUM PRIORITY]
**Files:** Multiple files handling array operations

**Problem:** Over-engineered array manipulation for simple add/remove operations.

**Solution:** Simplify to basic list operations.

## Implementation Strategy

### Phase 1: Quick Wins (1-2 days)
1. **Consolidate field rendering functions**
   - Move all to `field_common.gleam`
   - Update imports in field modules
   - Run tests to ensure no breakage

2. **Remove unused functions**
   - Delete unused boolean renderers
   - Remove unused model API functions
   - Clean up unused string formats

### Phase 2: Core Refactoring (2-3 days)
3. **Create converter module**
   - New file: `src/form/converter.gleam`
   - Consolidate all JSON/FieldValue conversions
   - Update all modules to use centralized converter

4. **Simplify path system**
   - Keep only used operations
   - Reduce nesting complexity
   - Optimize for common cases

### Phase 3: Optimization (1-2 days)
5. **Streamline update logic**
   - Reduce conversion overhead
   - Direct field updates where possible
   - Profile and measure improvements

6. **Extract validation helpers**
   - Create constraint checking utilities
   - Reduce code duplication in validator

## Expected Benefits

### Immediate Benefits
- **30% less code** - Removing duplicates and unused functions
- **Improved maintainability** - Single source of truth for common operations
- **Faster compilation** - Less code to process

### Long-term Benefits
- **Easier to extend** - Clear, simple patterns to follow
- **Better performance** - Fewer unnecessary conversions
- **Lower cognitive load** - Simpler code is easier to understand

## Success Metrics

1. **Code reduction**: Target 25-30% reduction in LOC
2. **Test coverage**: Maintain 100% coverage for critical paths
3. **Performance**: 20% faster form updates (measure with benchmarks)
4. **Complexity**: Reduce cyclomatic complexity by 40%

## Risk Mitigation

1. **Test thoroughly** after each refactoring phase
2. **Keep old code commented** until new code is proven
3. **Refactor in small, reviewable chunks**
4. **Document breaking changes** if any
5. **Run `gleam format` and `gleam test` after each change

## Priority Order

### 🔴 High Priority (Do First)
1. Consolidate field rendering (DRY)
2. Create converter module (DRY)
3. Simplify path system (KISS)
4. Remove unused path operations (YAGNI)

### 🟡 Medium Priority (Do Second)
5. Remove unused boolean renderers (YAGNI)
6. Remove unused model API (YAGNI)
7. Streamline update logic (KISS)
8. Extract validation helpers (DRY)

### 🟢 Low Priority (Do Later)
9. Remove unused string formats (YAGNI)
10. Further optimize conversions (KISS)
11. Document simplified patterns

## Code Examples

### Before Refactoring
```gleam
// Duplicated in 3 files
fn render_label(field_name: String, property: types.SchemaProperty, is_required: Bool) -> Element(FormMsg) {
  let label_text = case property.title {
    Some(title) -> title
    None -> field_name |> string.replace("_", " ") |> string.capitalise()
  }
  // ... 20 more lines of identical code
}
```

### After Refactoring
```gleam
// In field modules - just import and use
import formosh/fields/field_common

// Usage
field_common.render_label(field_name, property, is_required)
```

### Before Path Complexity
```gleam
// 200+ lines of complex recursive path manipulation
pub fn modify_at_path(...) { 
  // Deep nesting, multiple cases
}
```

### After Path Simplification
```gleam
// 50 lines of focused path operations
pub fn update_field_value(model: FormModel, field_name: String, value: FieldValue) {
  // Direct, simple update
}
```

## Next Steps

1. **Review this plan** with the team
2. **Create feature branch** for refactoring
3. **Start with Phase 1** quick wins
4. **Measure improvements** after each phase
5. **Update documentation** to reflect simplified patterns

## Conclusion

The Formosh codebase is well-architected but suffers from premature optimization and code duplication. By following this refactoring plan, we can reduce code by ~30%, improve performance by ~20%, and significantly enhance maintainability. The key is to embrace simplicity and only build what's actually needed.