// Unified field dispatcher.
//
// Single entry point for rendering a form field at any depth. Containers
// (array, object) call back into this dispatcher via the `render_child`
// parameter, keeping a single source of truth for widget selection and
// field-level wrapping (errors, touched, readonly markers).
//
// Selection priority: `widget` override (e.g. "image-upload") first, then
// `field_type` (string/number/boolean/array/object), then enum/oneOf as
// a fallback for properties without an explicit type.

import formosh/fields/array_field
import formosh/fields/boolean_field
import formosh/fields/field_common.{type FieldRenderCtx}
import formosh/fields/image_field
import formosh/fields/number_field
import formosh/fields/object_field
import formosh/fields/string_field
import formosh/fields/swipe_review_field
import formosh/form/model.{type FormModel, type FormMsg}
import formosh/form/path
import formosh/schema/types
import formosh/validation/error.{type ValidationError}
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

/// Render a single form field described by `ctx`.
///
/// `ctx.is_required`, `ctx.is_disabled`, `ctx.is_readonly` come from the
/// *parent* (root view, array container, object container). The parent has
/// direct access to its own `required` list and can pass an item-resolved
/// value (e.g. after `allOf` for array rows), which a path-based lookup
/// against the form-level resolved schema cannot yet see. The recursive
/// `model.is_required_at_path/2` is available for external callers.
pub fn render_field_at_path(
  ctx: FieldRenderCtx,
  model: FormModel,
) -> Element(FormMsg) {
  let is_hidden = ctx.hints.widget == Some(types.HiddenWidget)
  let is_readonly_suppressed = ctx.is_readonly && !model.show_readonly_fields
  case is_hidden || is_readonly_suppressed {
    True -> element.none()
    False -> render_visible(ctx, model)
  }
}

fn render_visible(ctx: FieldRenderCtx, model: FormModel) -> Element(FormMsg) {
  let is_touched = model.is_field_touched(model, ctx.path)
  let errors = model.get_errors_at_path(model, ctx.path)
  let has_errors = errors != []

  let field_element = render_widget(ctx, model)

  wrap_with_errors(
    field_element,
    errors,
    is_touched,
    has_errors,
    ctx.is_readonly,
  )
}

fn render_widget(ctx: FieldRenderCtx, model: FormModel) -> Element(FormMsg) {
  case ctx.hints.widget {
    Some(types.ImageUploadWidget) -> {
      let path_key = path.to_string(ctx.path)
      let upload_states = case dict.get(model.upload_states, path_key) {
        Ok(states) -> states
        Error(_) -> []
      }
      image_field.render(ctx, upload_states, model.upload_base_url)
    }
    Some(types.SwipeReviewWidget) -> swipe_review_field.render(ctx, model)
    _ ->
      case ctx.property.field_type {
        Some(types.StringType) -> string_field.render(ctx)
        Some(types.NumberType) | Some(types.IntegerType) ->
          number_field.render(ctx)
        Some(types.BooleanType) -> boolean_field.render(ctx)
        Some(types.ArrayType) ->
          array_field.render_container(ctx, model, render_field_at_path)
        Some(types.ObjectType) ->
          object_field.render_container(ctx, model, render_field_at_path)
        _ ->
          case ctx.property.enum_values, ctx.property.one_of {
            Some(_), _ | _, Some(_) -> string_field.render_enum(ctx)
            None, None -> element.none()
          }
      }
  }
}

fn wrap_with_errors(
  field_element: Element(FormMsg),
  errors: List(ValidationError),
  is_touched: Bool,
  has_errors: Bool,
  is_readonly: Bool,
) -> Element(FormMsg) {
  let show_error = has_errors && is_touched
  let base_attrs = [
    attribute.class("formosh-field"),
    attribute.attribute("part", "field"),
  ]
  let error_attr = case show_error {
    True -> [attribute.attribute("data-error", "true")]
    False -> []
  }
  let readonly_attr = case is_readonly {
    True -> [attribute.attribute("data-readonly", "true")]
    False -> []
  }
  let attrs = list.flatten([base_attrs, error_attr, readonly_attr])

  html.div(attrs, [
    field_element,
    case show_error {
      True -> field_common.render_field_errors(errors)
      False -> element.none()
    },
  ])
}
