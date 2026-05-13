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
import formosh/fields/field_common
import formosh/fields/image_field
import formosh/fields/number_field
import formosh/fields/object_field
import formosh/fields/string_field
import formosh/form/model.{type FormModel, type FormMsg}
import formosh/form/path.{type FieldPath}
import formosh/schema/types.{type SchemaProperty, type Value}
import gleam/dict
import gleam/option.{type Option, None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

/// Render a single form field at the given path.
///
/// `is_required`, `is_disabled`, `is_readonly` come from the *parent*
/// (root view, array container, object container). The parent has direct
/// access to its own `required` list and can pass an item-resolved value
/// (e.g. after `allOf` for array rows), which a path-based lookup against
/// the form-level resolved schema cannot yet see. The recursive
/// `model.is_required_at_path/2` is available for external callers.
pub fn render_field_at_path(
  field_path: FieldPath,
  property: SchemaProperty,
  model: FormModel,
  is_required: Bool,
  is_disabled: Bool,
  is_readonly: Bool,
) -> Element(FormMsg) {
  case is_readonly && !model.show_readonly_fields {
    True -> element.none()
    False ->
      render_visible(
        field_path,
        property,
        model,
        is_required,
        is_disabled,
        is_readonly,
      )
  }
}

fn render_visible(
  field_path: FieldPath,
  property: SchemaProperty,
  model: FormModel,
  is_required: Bool,
  is_disabled: Bool,
  is_readonly: Bool,
) -> Element(FormMsg) {
  let path_key = path.to_string(field_path)
  let value = model.get_value_at_path(model, field_path)
  let is_touched = model.is_field_touched(model, path_key)
  let errors = model.get_errors_at_path(model, field_path)
  let has_errors = errors != []

  let field_element =
    render_widget(
      field_path,
      property,
      value,
      model,
      is_required,
      is_disabled,
      is_readonly,
    )

  wrap_with_errors(field_element, errors, is_touched, has_errors, is_readonly)
}

fn render_widget(
  field_path: FieldPath,
  property: SchemaProperty,
  value: Option(Value),
  model: FormModel,
  is_required: Bool,
  is_disabled: Bool,
  is_readonly: Bool,
) -> Element(FormMsg) {
  case property.widget {
    Some("image-upload") -> {
      let path_key = path.to_string(field_path)
      let upload_states = case dict.get(model.upload_states, path_key) {
        Ok(states) -> states
        Error(_) -> []
      }
      image_field.render(
        field_path,
        property,
        value,
        is_required,
        is_disabled,
        is_readonly,
        upload_states,
        model.upload_base_url,
      )
    }
    _ ->
      case property.field_type {
        Some(types.StringType) ->
          string_field.render(
            field_path,
            property,
            value,
            is_required,
            is_disabled,
            is_readonly,
          )
        Some(types.NumberType) | Some(types.IntegerType) ->
          number_field.render(
            field_path,
            property,
            value,
            is_required,
            is_disabled,
            is_readonly,
          )
        Some(types.BooleanType) ->
          boolean_field.render(
            field_path,
            property,
            value,
            is_required,
            is_disabled,
            is_readonly,
          )
        Some(types.ArrayType) ->
          array_field.render_container(
            field_path,
            property,
            model,
            is_required,
            is_disabled,
            is_readonly,
            render_field_at_path,
          )
        Some(types.ObjectType) ->
          object_field.render_container(
            field_path,
            property,
            model,
            is_required,
            is_disabled,
            is_readonly,
            render_field_at_path,
          )
        _ ->
          case property.enum_values, property.one_of {
            Some(_), _ | _, Some(_) ->
              string_field.render_enum(
                field_path,
                property,
                value,
                is_required,
                is_disabled,
                is_readonly,
              )
            None, None -> element.none()
          }
      }
  }
}

fn wrap_with_errors(
  field_element: Element(FormMsg),
  errors: List(types.ValidationError),
  is_touched: Bool,
  has_errors: Bool,
  is_readonly: Bool,
) -> Element(FormMsg) {
  let error_class = case has_errors && is_touched {
    True -> " formosh-field-error"
    False -> ""
  }
  let readonly_class = case is_readonly {
    True -> " formosh-field-readonly"
    False -> ""
  }
  let class_str = "formosh-field" <> error_class <> readonly_class

  html.div([attribute.class(class_str)], [
    field_element,
    case has_errors && is_touched {
      True -> field_common.render_field_errors(errors)
      False -> element.none()
    },
  ])
}
