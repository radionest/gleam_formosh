// FFI for extracting JS object entries in insertion order.

import gleam/dynamic.{type Dynamic}

/// Return the key/value pairs of a JS object in insertion order.
///
/// Returns `Error(Nil)` if `value` is not a plain object (i.e. it is `null`,
/// an array, or a primitive). Callers should treat that as a type mismatch
/// and produce a decoder error rather than fall through to an empty result.
@external(javascript, "./dynamic_object_ffi.mjs", "entries")
pub fn entries(value: Dynamic) -> Result(List(#(String, Dynamic)), Nil) {
  let _ = value
  panic as "formosh targets JavaScript only"
}
