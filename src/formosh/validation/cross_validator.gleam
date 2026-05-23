// Cross-field custom validator extension point.
//
// JSON Schema does not express arithmetic constraints across siblings
// (e.g. "sum of category limits ≤ total limit"). This module lets the
// embedder plug a function that receives the full form data and returns
// per-field errors, which are merged into `FormModel.errors` after the
// schema-driven validation passes in `update.validate_all_fields`.
//
// Two construction paths:
//   - `pure/1`  — for Gleam embedders (via `formosh.with_validator`)
//   - `from_js/1` — for the `<formosh-form>` web component, where the
//                   embedder sets `element.validator = (values) => [...]`
//                   on the DOM element

import formosh/ffi/custom_validator as ffi
import formosh/form/path
import formosh/validation/error.{type ValidationError, ValidationError}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode

/// A cross-field validator parameterised on the model type `m`.
///
/// Opaque so the JS-vs-Gleam representation can evolve (e.g. add an
/// `Async` variant later) without breaking embedder code.
pub opaque type Validator(m) {
  Pure(fn(m) -> List(ValidationError))
  Js(Dynamic)
}

/// Build a validator from a pure Gleam function.
pub fn pure(f: fn(m) -> List(ValidationError)) -> Validator(m) {
  Pure(f)
}

/// Build a validator from a JS function obtained via DOM property setter.
///
/// The JS function will be called with `JSON.parse(values_json)` and is
/// expected to return `Array<{path: string, message: string, rule?: string}>`.
/// Exceptions thrown by the JS function are caught and logged; malformed
/// items are silently dropped.
pub fn from_js(js_fn: Dynamic) -> Validator(m) {
  Js(js_fn)
}

/// Run the validator and collect the resulting errors.
///
/// `serialize` is used only for the JS branch — it converts the model to a
/// JSON string that crosses the FFI boundary. For pure validators it is not
/// invoked, so callers can pass any cheap function.
pub fn run(
  v: Validator(m),
  m: m,
  serialize: fn(m) -> String,
) -> List(ValidationError) {
  case v {
    Pure(f) -> f(m)
    Js(js_fn) -> {
      let raw = ffi.call_validator(js_fn, serialize(m))
      decode_errors(raw)
    }
  }
}

fn decode_errors(raw: Dynamic) -> List(ValidationError) {
  let item_decoder = {
    use path_str <- decode.field("path", decode.string)
    use message <- decode.field("message", decode.string)
    use rule <- decode.optional_field("rule", "custom", decode.string)
    decode.success(ValidationError(
      field: path.from_string(path_str),
      message: message,
      rule: rule,
    ))
  }
  case decode.run(raw, decode.list(item_decoder)) {
    Ok(errors) -> errors
    Error(_) -> []
  }
}
