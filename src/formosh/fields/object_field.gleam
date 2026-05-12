/// Object field renderer for nested structured data.
/// 
/// This module handles rendering of object fields that contain nested
/// properties with their own field types. It recursively renders sub-fields
/// based on the object's property schema.
import formosh/fields/boolean_field
import formosh/fields/number_field
import formosh/fields/string_field
import formosh/form/model.{type FormMsg}
import formosh/form/path.{PropertySegment}
import formosh/schema/types.{type SchemaProperty, type Value}
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html

/// Render an object field with all its nested properties.
///
/// Creates a complete object field interface including:
/// - Field label and description
/// - Container for nested fields
/// - Each nested property rendered according to its type
/// - Support for required nested fields
///
/// ## Parameters
/// - `field_path`: The path to this object field
/// - `property`: Schema property defining the object structure
/// - `value`: Current object value as Option(Value)
/// - `is_required`: Whether the object field itself is required
/// - `is_disabled`: Whether the field is disabled
/// - `is_readonly`: Whether the field is read-only
///
/// ## Returns
/// A complete object field interface with all nested properties
pub fn render(
  field_path: path.FieldPath,
  property: SchemaProperty,
  value: Option(Value),
  is_required: Bool,
  is_disabled: Bool,
  is_readonly: Bool,
) -> Element(FormMsg) {
  let field_name = path.to_string(field_path)
  let title = option.unwrap(property.title, field_name)
  let description = property.description

  // Extract nested values from ObjectValue
  let nested_values = case value {
    Some(types.ObjectValue(fields)) -> dict.from_list(fields)
    _ -> dict.new()
  }

  html.div([class("object-field")], [
    // Render label with required indicator
    html.label([class("object-label")], [
      html.text(title),
      case is_required {
        True -> html.span([class("required")], [html.text(" *")])
        False -> element.none()
      },
    ]),
    // Render description if present
    case description {
      Some(desc) -> html.p([class("field-description")], [html.text(desc)])
      None -> element.none()
    },
    // Render nested fields container
    html.div(
      [class("object-fields")],
      render_nested_fields(
        field_path,
        property,
        nested_values,
        is_disabled,
        is_readonly,
      ),
    ),
  ])
}

/// Render all nested fields within an object.
///
/// Takes the object's properties schema and renders each field according to
/// its type and constraints. Each field is connected through the path-based
/// field system for proper state management.
///
/// ## Parameters
/// - `parent_path`: The path to the parent object field
/// - `property`: The object's schema property containing nested properties
/// - `values`: Current values for nested fields
/// - `is_disabled`: Whether fields should be disabled
/// - `is_readonly`: Whether fields should be read-only
///
/// ## Returns
/// List of rendered field elements for the object's properties
fn render_nested_fields(
  parent_path: path.FieldPath,
  property: SchemaProperty,
  values: dict.Dict(String, Value),
  is_disabled: Bool,
  is_readonly: Bool,
) -> List(Element(FormMsg)) {
  case property.properties {
    Some(props) ->
      props
      |> list.map(fn(entry) {
        let #(nested_field_name, nested_property) = entry
        let nested_value =
          dict.get(values, nested_field_name) |> option.from_result()
        let is_required = list.contains(property.required, nested_field_name)

        // Create path for this nested field by appending property segment
        let nested_path =
          list.append(parent_path, [PropertySegment(nested_field_name)])

        // Nested field is readonly if parent is readonly OR if the nested property itself is readonly
        let nested_is_readonly = is_readonly || nested_property.read_only

        render_nested_field(
          nested_path,
          nested_property,
          nested_value,
          is_required,
          is_disabled,
          nested_is_readonly,
        )
      })
    None -> []
  }
}

/// Render a single nested field within an object.
///
/// Delegates to the appropriate field renderer based on the field type,
/// maintaining consistency with the rest of the form system.
///
/// ## Parameters
/// - `field_path`: The full path to this nested field
/// - `property`: Schema property for this field
/// - `value`: Current value of the field
/// - `is_required`: Whether this field is required within the object
/// - `is_disabled`: Whether the field is disabled
/// - `is_readonly`: Whether the field is read-only
///
/// ## Returns
/// A rendered field element using the appropriate field renderer
fn render_nested_field(
  field_path: path.FieldPath,
  property: SchemaProperty,
  value: Option(types.Value),
  is_required: Bool,
  is_disabled: Bool,
  is_readonly: Bool,
) -> Element(FormMsg) {
  let field_element = case property.field_type {
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
    Some(types.ObjectType) ->
      // Support nested objects recursively
      render(field_path, property, value, is_required, is_disabled, is_readonly)
    Some(types.ArrayType) ->
      // For array fields within objects, we need to handle them specially
      // This would require importing array_field, but to avoid circular dependencies,
      // we'll show unsupported for now
      html.div([class("unsupported-field")], [
        html.text("Nested array fields not yet supported"),
      ])
    _ ->
      // Handle enum or unknown types
      case property.enum_values {
        Some(_) ->
          string_field.render_enum(
            field_path,
            property,
            value,
            is_required,
            is_disabled,
            is_readonly,
          )
        None ->
          html.div([class("unsupported-field")], [
            html.text("Unsupported field type"),
          ])
      }
  }

  html.div([class("object-field-item")], [field_element])
}
