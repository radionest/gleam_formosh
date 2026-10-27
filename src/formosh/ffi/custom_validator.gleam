// FFI bindings for calling user-supplied JS cross-field validators.

import gleam/dynamic.{type Dynamic}

/// Check whether a JS value handed through a DOM property setter is actually
/// a function. Used to treat `el.validator = null` (and any other
/// non-function) as "detach" instead of storing a validator that warns on
/// every validation pass (#170).
@external(javascript, "./custom_validator_ffi.mjs", "isValidatorFunction")
pub fn is_validator_function(js_fn: Dynamic) -> Bool {
  // Erlang stub — formosh is JS-only.
  let _ = js_fn
  False
}

/// Invoke a JS validator function with the form values serialised as JSON.
///
/// Returns the validator's output as a `Dynamic` value (expected shape:
/// `Array<{path: string, message: string, rule: string}>`). The JS shim
/// catches exceptions and validates the output shape, so the returned value
/// is always a well-formed (possibly empty) array of error records.
@external(javascript, "./custom_validator_ffi.mjs", "callValidator")
pub fn call_validator(js_fn: Dynamic, values_json: String) -> Dynamic {
  // Erlang stub — formosh is JS-only.
  let _ = js_fn
  let _ = values_json
  dynamic.nil()
}
