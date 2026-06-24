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
  /// Begin a horizontal drag on a zone row. `start_x` is the pointer's
  /// clientX; `pos_code`/`neg_code` are the answers committed on a
  /// right/left release past `threshold` (px).
  DragStart(
    path: FieldPath,
    start_x: Float,
    pos_code: String,
    neg_code: String,
    threshold: Float,
  )
  /// Pointer moved to clientX `x` during a drag — updates the live offset.
  DragMove(x: Float)
  /// Pointer released — commit the answer if past threshold, else snap back.
  DragEnd
  /// Drag aborted (pointer left the row / cancelled) — snap back, no answer.
  DragCancel
  /// Flip the "hide answered / show all" view mode.
  ToggleHideAnswered
  /// Commit a zone answer and fly the card off in `dir` (tap path; the swipe
  /// release computes its own dir from the drag). Drives a fly-off only in
  /// hide-answered mode; in show-all it just records the answer.
  AnswerZone(path: FieldPath, code: String, dir: ExitDir)
  /// The fly-off transition for a committed card finished — drop it from the
  /// transient exiting set.
  ExitDone(path: FieldPath)
}

/// Direction a committed swipe-review card flies off: right/left for a
/// directional answer, fade-in-place for the neutral middle choice.
pub type ExitDir {
  ExitLeft
  ExitRight
  ExitFade
}
