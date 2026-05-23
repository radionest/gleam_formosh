// FFI bindings for calling user-supplied JS cross-field validators.

import gleam/dynamic.{type Dynamic}

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
