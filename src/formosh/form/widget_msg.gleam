// Widget-specific event types, grouped under `WidgetMsg` and wrapped into
// `FormMsg.WidgetEvent` so the core message type doesn't grow per widget.

import formosh/form/path.{type FieldPath}

pub type WidgetMsg {
  ImageUpload(ImageUploadEvent)
  SwipeReview(SwipeReviewEvent)
}

pub type ImageUploadEvent {
  ImageRequested(path: FieldPath)
  ImageStarted(path: FieldPath, temp_id: String, preview_url: String)
  ImageCompleted(path: FieldPath, temp_id: String, server_url: String)
  ImageFailed(path: FieldPath, temp_id: String, error: String)
  ImageRemoved(path: FieldPath, server_url: String)
}

pub type SwipeReviewEvent {
  /// Set every listed zone path to `code` in one update (bulk-finish).
  FillRemaining(paths: List(FieldPath), code: String)
}
