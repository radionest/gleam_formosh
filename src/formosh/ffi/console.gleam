/// FFI wrapper for `console.warn`.
///
/// Used by the submit gate to diagnose silent blocks caused by required
/// errors on UI-suppressed paths (issue #23). Hidden / readOnly-suppressed
/// fields have no DOM anchor to highlight, so a console message is the only
/// channel that surfaces the cause to the developer.
@external(javascript, "./console_ffi.mjs", "warn")
pub fn warn(message: String) -> Nil {
  let _ = message
  panic as "formosh targets JavaScript only"
}
