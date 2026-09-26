// Unified field dispatcher.
//
// Single entry point for rendering a form field at any depth. Containers
// (array, object) call back into this dispatcher via the `render_child`
// parameter, keeping a single source of truth for widget selection and
// field-level wrapping (errors, touched, readonly markers).
//
// Selection priority: `widget` override (e.g. "image-upload") first, then
// `field_type` (string/number/boolean/array/object — a number with
// enum/oneOf options renders the enum widget, an option-list array with
// uniqueItems the checkbox group), then enum/oneOf as a
// fallback for properties without an explicit type.

import formosh/fields/array_field
import formosh/fields/boolean_field
import formosh/fields/field_common.{type FieldRenderCtx}
import formosh/fields/image_field
import formosh/fields/number_field
import formosh/fields/object_field
import formosh/fields/string_field
import formosh/fields/swipe_review_field
import formosh/fields/union_field
import formosh/form/model.{type FormModel, type FormMsg}
import formosh/form/path
import formosh/schema/types
import formosh/schema/ui_resolver
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
  // `ui_resolver.is_suppressed` is the single source of truth for the
  // "this field is suppressed from the UI" decision — shared with the
  // submit-time walker in `formosh/form/visibility`. Add new suppression
  // rules there, not inline here.
  case
    ui_resolver.is_suppressed(
      ctx.hints,
      ctx.is_readonly,
      model.show_readonly_fields,
    )
  {
    True -> element.none()
    False -> render_visible(ctx, model)
  }
}

fn render_visible(ctx: FieldRenderCtx, model: FormModel) -> Element(FormMsg) {
  let is_touched = model.is_field_touched(model, ctx.path)
  let errors = model.get_errors_at_path(model, ctx.path)
  // Array-level errors (minItems/maxItems/uniqueItems) bypass the touched
  // gate. In the row editor, add/remove gating makes the length ones
  // unreachable through the UI, so there they only arise from externally
  // injected values — where they are the only visible explanation for a
  // blocked submit. A checkbox group has no minItems gating (unlike
  // maxItems, which disables the unchecked boxes at the cap); every click
  // sends UpdateFieldPath/ClearFieldPath at the array path itself, marking
  // that exact path touched — so an under-minItems checkbox selection
  // already surfaces through the normal touched branch above; the bypass
  // only matters there for externally injected values (e.g. initial values
  // below minItems), same as the row editor. A row-editor duplicate is
  // typed into `n.[i]`/`n.[i].field`, which never touches the array path
  // itself, so a uniqueItems error would otherwise stay invisible — blank
  // rows are never compared, so this path only fires for genuine
  // duplicates (rows filled from schema defaults are a known exception:
  // they still compare equal).
  let visible_errors = case is_touched {
    True -> errors
    False -> list.filter(errors, error.is_array_level)
  }

  let field_element = render_widget(ctx, model)

  wrap_with_errors(ctx, field_element, visible_errors)
}

fn render_widget(ctx: FieldRenderCtx, model: FormModel) -> Element(FormMsg) {
  case ctx.property.any_of {
    // 2+ members: a genuine union — render the branch chooser. Exactly
    // 0/1-member `any_of` cannot survive parsing (composer.normalize_any_of
    // collapses those into the node itself), but the guard is written to
    // fall through to the existing body rather than assume the invariant.
    //
    // `render_child` is `render_widget_by_type`, NOT `render_field_at_path`:
    // the subform dispatches at the union's own `ctx.path` (see
    // `union_field.gleam`'s `child_ctx`), so a wrapping callback there would
    // re-enter `render_visible` -> `wrap_with_errors` at that same path —
    // duplicating the error/touched wrap this arm's own caller (the outer
    // `render_visible`) already applies. `render_widget_by_type` is the
    // plain widget-type switch with no wrapping and no suppression check of
    // its own (both already happened once, in the outer call that reached
    // this `render_widget` in the first place) — exactly the seam that
    // keeps ONE `part="field"` wrapper per union while still dispatching
    // hints/array/object content in full (those recurse into
    // `render_field_at_path` again, but at their OWN child paths, not the
    // union's).
    Some([_, _, ..]) -> union_field.render(ctx, model, render_widget_by_type)
    _ -> render_widget_by_type(ctx, model)
  }
}

fn render_widget_by_type(
  ctx: FieldRenderCtx,
  model: FormModel,
) -> Element(FormMsg) {
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
          case
            is_bare_const(ctx.property)
            || !string_field.has_options(ctx.property)
          {
            True -> number_field.render(ctx)
            False -> string_field.render_enum(ctx)
          }
        Some(types.BooleanType) -> boolean_field.render(ctx)
        Some(types.ArrayType) ->
          case types.is_multi_select(ctx.property) {
            True -> string_field.render_checkboxes(ctx)
            False ->
              array_field.render_container(ctx, model, render_field_at_path)
          }
        Some(types.ObjectType) ->
          object_field.render_container(ctx, model, render_field_at_path)
        _ ->
          case string_field.has_options(ctx.property) {
            True -> string_field.render_enum(ctx)
            False -> element.none()
          }
      }
  }
}

// A bare `const` parses to a one-value `enum` — nothing to choose between.
fn is_bare_const(property: types.SchemaProperty) -> Bool {
  case property.enum_values, property.one_of {
    Some([_]), None -> True
    _, _ -> False
  }
}

fn wrap_with_errors(
  ctx: FieldRenderCtx,
  field_element: Element(FormMsg),
  errors: List(ValidationError),
) -> Element(FormMsg) {
  let show_error = errors != []
  let base_attrs = [
    attribute.class("formosh-field"),
    attribute.attribute("part", "field"),
    attribute.attribute("data-name", path.get_field_name(ctx.path)),
    attribute.attribute("data-path", path.to_string(ctx.path)),
  ]
  let error_attr = case show_error {
    True -> [attribute.attribute("data-error", "true")]
    False -> []
  }
  let readonly_attr = case ctx.is_readonly {
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
