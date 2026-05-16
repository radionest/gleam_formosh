// Image upload field renderer

import formosh/fields/field_common.{type FieldRenderCtx}
import formosh/form/model.{
  type FileUploadState, type FormMsg, FileUploadError, FileUploading, image_msg,
}
import formosh/form/path
import formosh/form/widget_msg.{ImageRemoved, ImageRequested}
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
///
/// `upload_states` and `upload_base_url` stay outside the ctx because they
/// are image-specific runtime state pulled from the model by the dispatcher.
pub fn render(
  ctx: FieldRenderCtx,
  upload_states: List(FileUploadState),
  upload_base_url: Option(String),
) -> Element(FormMsg) {
  let uploaded_urls = case ctx.value {
    Some(types.ArrayValue(items)) ->
      list.filter_map(items, fn(item) {
        case item {
          types.StringValue(url) -> Ok(url)
          _ -> Error(Nil)
        }
      })
    _ -> []
  }

  let effective_disabled = ctx.is_disabled || ctx.is_readonly

  let content =
    html.div(
      [
        attribute.class("formosh-image-upload"),
        attribute.attribute("part", "image-upload"),
      ],
      [
        // Grid of uploaded images
        html.div(
          [
            attribute.class("formosh-image-grid"),
            attribute.attribute("part", "image-grid"),
          ],
          list.append(
            list.append(
              // Completed uploads
              list.map(uploaded_urls, fn(url) {
                render_uploaded_image(ctx.path, url, effective_disabled)
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
                attribute.attribute("part", "image-add"),
                event.on_click(image_msg(ImageRequested(ctx.path))),
              ],
              [html.text("Add photo")],
            )
        },
      ],
    )

  field_common.field_wrapper(ctx, content)
}

/// Render a single uploaded image with delete button.
fn render_uploaded_image(
  field_path: path.FieldPath,
  url: String,
  is_disabled: Bool,
) -> Element(FormMsg) {
  html.div(
    [
      attribute.class("formosh-image-card"),
      attribute.attribute("part", "image-card"),
    ],
    [
      html.img([
        attribute.src(url),
        attribute.class("formosh-image-preview"),
        attribute.attribute("part", "image-preview"),
        attribute.alt("Uploaded image"),
      ]),
      case is_disabled {
        True -> element.none()
        False ->
          html.button(
            [
              attribute.type_("button"),
              attribute.class("formosh-image-remove"),
              attribute.attribute("part", "image-remove"),
              event.on_click(image_msg(ImageRemoved(field_path, url))),
            ],
            [html.text("×")],
          )
      },
    ],
  )
}

/// Render an image being uploaded with preview and spinner.
fn render_uploading_image(preview_url: String) -> Element(FormMsg) {
  html.div(
    [
      attribute.class("formosh-image-card formosh-image-uploading"),
      attribute.attribute("part", "image-card image-uploading"),
    ],
    [
      html.img([
        attribute.src(preview_url),
        attribute.class("formosh-image-preview"),
        attribute.attribute("part", "image-preview"),
        attribute.alt("Uploading..."),
      ]),
      html.div(
        [
          attribute.class("formosh-image-spinner"),
          attribute.attribute("part", "image-spinner"),
        ],
        [],
      ),
    ],
  )
}

/// Render an upload error card.
fn render_upload_error(error: String) -> Element(FormMsg) {
  html.div(
    [
      attribute.class("formosh-image-card formosh-image-error"),
      attribute.attribute("part", "image-card image-error"),
    ],
    [
      html.div(
        [
          attribute.class("formosh-image-error-text"),
          attribute.attribute("part", "image-error-text"),
        ],
        [html.text(error)],
      ),
    ],
  )
}
