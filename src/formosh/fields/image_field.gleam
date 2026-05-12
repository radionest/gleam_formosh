// Image upload field renderer

import formosh/fields/field_common
import formosh/form/model.{
  type FileUploadState, type FormMsg, FileUploadError, FileUploading,
  ImageRemoved, ImageUploadRequested,
}
import formosh/form/path
import formosh/schema/types
import gleam/list
import gleam/option.{type Option, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// Render an image upload field.
///
/// Displays a grid of uploaded images with delete buttons,
/// in-progress uploads with preview, error cards, and an add button.
pub fn render(
  field_path: path.FieldPath,
  property: types.SchemaProperty,
  value: Option(types.Value),
  is_required: Bool,
  is_disabled: Bool,
  is_readonly: Bool,
  upload_states: List(FileUploadState),
  upload_base_url: Option(String),
) -> Element(FormMsg) {
  let uploaded_urls = case value {
    Some(types.ArrayValue(items)) ->
      list.filter_map(items, fn(item) {
        case item {
          types.StringValue(url) -> Ok(url)
          _ -> Error(Nil)
        }
      })
    _ -> []
  }

  let effective_disabled = is_disabled || is_readonly

  let content =
    html.div([attribute.class("formosh-image-upload")], [
      // Grid of uploaded images
      html.div(
        [attribute.class("formosh-image-grid")],
        list.append(
          list.append(
            // Completed uploads
            list.map(uploaded_urls, fn(url) {
              render_uploaded_image(field_path, url, effective_disabled)
            }),
            // In-progress uploads
            list.filter_map(upload_states, fn(state) {
              case state {
                FileUploading(_, preview_url) ->
                  Ok(render_uploading_image(preview_url))
                _ -> Error(Nil)
              }
            }),
          ),
          // Error cards
          list.filter_map(upload_states, fn(state) {
            case state {
              FileUploadError(_, error) -> Ok(render_upload_error(error))
              _ -> Error(Nil)
            }
          }),
        ),
      ),
      // Add button (hidden when disabled/readonly or no upload URL)
      case effective_disabled || option.is_none(upload_base_url) {
        True -> element.none()
        False ->
          html.button(
            [
              attribute.type_("button"),
              attribute.class("formosh-image-add"),
              event.on_click(ImageUploadRequested(field_path)),
            ],
            [html.text("Add photo")],
          )
      },
    ])

  field_common.field_wrapper_with_path(
    field_path,
    property,
    is_required,
    content,
  )
}

/// Render a single uploaded image with delete button.
fn render_uploaded_image(
  field_path: path.FieldPath,
  url: String,
  is_disabled: Bool,
) -> Element(FormMsg) {
  html.div([attribute.class("formosh-image-card")], [
    html.img([
      attribute.src(url),
      attribute.class("formosh-image-preview"),
      attribute.alt("Uploaded image"),
    ]),
    case is_disabled {
      True -> element.none()
      False ->
        html.button(
          [
            attribute.type_("button"),
            attribute.class("formosh-image-remove"),
            event.on_click(ImageRemoved(field_path, url)),
          ],
          [html.text("×")],
        )
    },
  ])
}

/// Render an image being uploaded with preview and spinner.
fn render_uploading_image(preview_url: String) -> Element(FormMsg) {
  html.div([attribute.class("formosh-image-card formosh-image-uploading")], [
    html.img([
      attribute.src(preview_url),
      attribute.class("formosh-image-preview"),
      attribute.alt("Uploading..."),
    ]),
    html.div([attribute.class("formosh-image-spinner")], []),
  ])
}

/// Render an upload error card.
fn render_upload_error(error: String) -> Element(FormMsg) {
  html.div([attribute.class("formosh-image-card formosh-image-error")], [
    html.div([attribute.class("formosh-image-error-text")], [
      html.text(error),
    ]),
  ])
}
