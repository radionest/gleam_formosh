/// Demo glue for attaching JS cross-field validators to the
/// `<formosh-form>` element by id.
@external(javascript, "./validators_ffi.mjs", "attachValidator")
pub fn attach_validator(element_id: String, validator_kind: String) -> Nil {
  let _ = element_id
  let _ = validator_kind
  Nil
}

@external(javascript, "./validators_ffi.mjs", "detachValidator")
pub fn detach_validator(element_id: String) -> Nil {
  let _ = element_id
  Nil
}
