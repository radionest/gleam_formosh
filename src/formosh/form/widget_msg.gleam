// Widget-specific event types, grouped under `WidgetMsg` and wrapped into
// `FormMsg.WidgetEvent` so the core message type doesn't grow per widget.

import formosh/form/path.{type FieldPath}

pub type WidgetMsg {
  ImageUpload(ImageUploadEvent)
}

pub type ImageUploadEvent {
  Requested(path: FieldPath)
  Started(path: FieldPath, temp_id: String, preview_url: String)
  Completed(path: FieldPath, temp_id: String, server_url: String)
  Failed(path: FieldPath, temp_id: String, error: String)
  Removed(path: FieldPath, server_url: String)
}
