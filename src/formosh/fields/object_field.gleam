/// Object container renderer.
///
/// Renders the object label and a fieldset of nested properties. Child
/// fields are dispatched through `render_child` (typically the unified
/// `field_dispatcher.render_field_at_path`), so any child — string,
/// number, nested object, array, image-upload widget — goes through the
/// same selection logic as top-level fields.
import formosh/fields/field_common.{type FieldRenderCtx}
import formosh/form/model.{type FormModel, type FormMsg}
import formosh/form/path.{PropertySegment}
import formosh/schema/properties
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html

/// Render an object field as a labelled fieldset of its properties.
///
/// `is_required` on the container itself is decided by the parent (it's
/// in the parent's `required` list); on every child it's decided here
/// (it's in *this* property's `required` list).
pub fn render_container(
  ctx: FieldRenderCtx,
  model: FormModel,
  render_child: fn(FieldRenderCtx, FormModel) -> Element(FormMsg),
) -> Element(FormMsg) {
  let object_name = path.get_field_name(ctx.path)
  let description = ctx.property.description

  html.div([class("object-field")], [
    field_common.render_container_label(
      field_name: object_name,
      property: ctx.property,
      is_required: ctx.is_required,
      css_class: "object-label",
      hints: ctx.hints,
    ),
    case description {
      Some(desc) -> html.p([class("field-description")], [html.text(desc)])
      None -> element.none()
    },
    html.div(
      [class("object-fields")],
      render_nested_fields(ctx, model, render_child),
    ),
  ])
}

fn render_nested_fields(
  ctx: FieldRenderCtx,
  model: FormModel,
  render_child: fn(FieldRenderCtx, FormModel) -> Element(FormMsg),
) -> List(Element(FormMsg)) {
  case ctx.property.properties {
    Some(props) ->
      properties.apply_order(props, ctx.hints.order)
      |> list.map(fn(entry) {
        let #(child_name, child_prop) = entry
        let child_path = list.append(ctx.path, [PropertySegment(child_name)])
        let child_ctx =
          field_common.make_child_ctx(
            parent: ctx,
            model: model,
            path: child_path,
            property: child_prop,
            is_required: list.contains(ctx.property.required, child_name),
          )
        render_child(child_ctx, model)
      })
    None -> []
  }
}
