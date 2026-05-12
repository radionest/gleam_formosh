// FFI for extracting JS object entries in insertion order.

import gleam/dynamic.{type Dynamic}

@external(javascript, "./dynamic_object_ffi.mjs", "entries")
pub fn entries(value: Dynamic) -> List(#(String, Dynamic)) {
  let _ = value
  panic as "formosh targets JavaScript only"
}
