/// Object container renderer.
///
/// Renders the object label and a fieldset of nested properties. Child
/// fields are dispatched through `render_child` (typically the unified
/// `field_dispatcher.render_field_at_path`), so any child — string,
/// number, nested object, array, image-upload widget — goes through the
/// same selection logic as top-level fields.
import formosh/fields/field_common
import formosh/form/model.{type FormModel, type FormMsg}
import formosh/form/path.{type FieldPath, PropertySegment}
import formosh/schema/types.{type SchemaProperty}
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
  field_path: FieldPath,
  property: SchemaProperty,
  model: FormModel,
  is_required: Bool,
  is_disabled: Bool,
  is_readonly: Bool,
  render_child: fn(FieldPath, SchemaProperty, FormModel, Bool, Bool, Bool) ->
    Element(FormMsg),
) -> Element(FormMsg) {
  let object_name = path.get_field_name(field_path)
  let description = property.description

  html.div([class("object-field")], [
    field_common.render_container_label(
      object_name,
      property,
      is_required,
      "object-label",
    ),
    case description {
      Some(desc) -> html.p([class("field-description")], [html.text(desc)])
      None -> element.none()
    },
    html.div(
      [class("object-fields")],
      render_nested_fields(
        field_path,
        property,
        model,
        is_disabled,
        is_readonly,
        render_child,
      ),
    ),
  ])
}

fn render_nested_fields(
  parent_path: FieldPath,
  property: SchemaProperty,
  model: FormModel,
  is_disabled: Bool,
  is_readonly: Bool,
  render_child: fn(FieldPath, SchemaProperty, FormModel, Bool, Bool, Bool) ->
    Element(FormMsg),
) -> List(Element(FormMsg)) {
  case property.properties {
    Some(props) ->
      list.map(props, fn(entry) {
        let #(child_name, child_prop) = entry
        let child_path = list.append(parent_path, [PropertySegment(child_name)])
        let child_required = list.contains(property.required, child_name)
        let child_readonly = is_readonly || child_prop.read_only
        render_child(
          child_path,
          child_prop,
          model,
          child_required,
          is_disabled,
          child_readonly,
        )
      })
    None -> []
  }
}
