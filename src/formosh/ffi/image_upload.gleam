// FFI bindings for image upload functionality

@external(javascript, "./image_upload_ffi.mjs", "openFilePicker")
pub fn open_file_picker(
  accept: String,
  max_file_size: Int,
  upload_url: String,
  on_started: fn(String, String) -> Nil,
  on_uploaded: fn(String, String) -> Nil,
  on_error: fn(String, String) -> Nil,
) -> Nil {
  // Erlang stub — formosh is a JS-only library
  let _ = accept
  let _ = max_file_size
  let _ = upload_url
  let _ = on_started
  let _ = on_uploaded
  let _ = on_error
  Nil
}

@external(javascript, "./image_upload_ffi.mjs", "deleteFile")
pub fn delete_file(upload_base_url: String, filename: String) -> Nil {
  let _ = upload_base_url
  let _ = filename
  Nil
}

@external(javascript, "./image_upload_ffi.mjs", "revokeObjectUrl")
pub fn revoke_object_url(url: String) -> Nil {
  let _ = url
  Nil
}
