---
globs: "**/*.gleam"
---

# Gleam code style rules

## Use expressions over nested case/callbacks

Always prefer `use` expressions for Result/Option pipelines. Never write nested callbacks or chained `result.try` without `use`.

```gleam
// BAD
result.try(get_value(x), fn(value) {
  result.try(process(value), fn(processed) {
    Ok(processed)
  })
})

// GOOD
use value <- result.try(get_value(x))
use processed <- result.try(process(value))
Ok(processed)
```

## Pattern match on meaningful values, not booleans

When a boolean comes from a check, match on the source value instead of True/False. Avoid introducing an intermediate `is_*` boolean just to `case` on it.

```gleam
// BAD — matching on derived bool when source value is available
let is_empty = list.is_empty(items)
case is_empty {
  True -> default
  False -> process(items)
}

// GOOD — match on the actual data
case items {
  [] -> default
  _ -> process(items)
}
```

`case is_readonly { True -> ... False -> ... }` is fine when the Bool is a function parameter — there is nothing deeper to match on. The rule targets cases where a richer value is available.
