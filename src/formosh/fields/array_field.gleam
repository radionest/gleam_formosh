/// Array field renderer for dynamic lists of structured data.
/// 
/// This module handles rendering of array fields that contain lists of objects
/// with defined properties. It supports adding, removing, and editing items
/// within the array, with each item rendered as a group of sub-fields.
/// 
/// The array field supports nested object schemas with various field types
/// including strings, numbers, booleans, and enums within each array item.
import formosh/fields/boolean_field
import formosh/fields/number_field
import formosh/fields/string_field
import formosh/form/model.{type FormMsg, AddArrayItemPath, RemoveArrayItemPath}
import formosh/form/path
import formosh/schema/types.{type SchemaProperty, type Value}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import lustre/attribute.{class, type_}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// Render an array field with dynamic add/remove functionality.
/// 
/// Creates a complete array field interface including:
/// - Field label and description
/// - List of existing array items with their sub-fields
/// - "Add Item" button to create new entries
/// - "Remove" buttons for each item
/// - Error display
/// 
/// ## Parameters
/// - `name`: The array field name
/// - `property`: Schema property defining the array structure and item schema
/// - `values`: Current array values as list of field dictionaries
/// - `errors`: List of error messages for the array field
/// - `required`: Whether the array field is required (affects label styling)
/// 
/// ## Returns
/// A complete array field interface with all items and controls
/// 
/// ## Features
/// - Dynamic item management (add/remove)
/// - Nested field rendering based on item schema
/// - Numbered items for easy reference
/// - Support for required items within array objects
pub fn view(
  name: String,
  property: SchemaProperty,
  values: List(dict.Dict(String, Value)),
  errors: List(String),
  required: Bool,
) -> Element(FormMsg) {
  let title = option.unwrap(property.title, name)
  let description = property.description

  html.div([class("array-field")], [
    html.label([class("array-label")], [
      html.text(title),
      case required {
        True -> html.span([class("required")], [html.text(" *")])
        False -> element.none()
      },
    ]),
    case description {
      Some(desc) -> html.p([class("field-description")], [html.text(desc)])
      None -> element.none()
    },
    html.div(
      [class("array-items")],
      list.index_map(values, fn(item_values, index) {
        render_array_item(name, property, item_values, index)
      }),
    ),
    html.button(
      [
        type_("button"),
        class("add-array-item"),
        // Use new path-based message
        event.on_click(AddArrayItemPath(path.from_field_name(name))),
      ],
      [html.text("Добавить элемент")],
    ),
    case errors {
      [] -> element.none()
      errs ->
        html.div(
          [class("field-errors")],
          list.map(errs, fn(err) {
            html.span([class("error-message")], [html.text(err)])
          }),
        )
    },
  ])
}

/// Render a single item within an array field.
/// 
/// Each array item is rendered as a container with:
/// - Header showing item number and remove button
/// - Sub-fields based on the item schema definition
/// 
/// ## Parameters
/// - `array_name`: The parent array field name
/// - `property`: The array property containing item schema
/// - `item_values`: Current values for this specific array item
/// - `index`: Zero-based index of this item in the array
/// 
/// ## Returns
/// A single array item container with all its sub-fields
fn render_array_item(
  array_name: String,
  property: SchemaProperty,
  item_values: dict.Dict(String, Value),
  index: Int,
) -> Element(FormMsg) {
  case property.items {
    Some(item_schema) ->
      html.div([class("array-item")], [
        html.div([class("array-item-header")], [
          html.span([class("array-item-index")], [
            html.text("№ " <> int.to_string(index + 1)),
          ]),
          html.button(
            [
              type_("button"),
              class("remove-array-item"),
              // Use new path-based message
              event.on_click(RemoveArrayItemPath(
                path.from_field_name(array_name),
                index,
              )),
            ],
            [html.text("Удалить")],
          ),
        ]),
        html.div(
          [class("array-item-fields")],
          render_item_fields(array_name, item_schema, item_values, index),
        ),
      ])
    None -> element.none()
  }
}

/// Render all fields for a single array item.
/// 
/// Takes the item schema properties and renders each field according to
/// its type and constraints. Each field is connected to the array through
/// the unified path-based field renderers.
/// 
/// ## Parameters
/// - `array_name`: The parent array field name
/// - `item_schema`: Schema property defining the structure of array items
/// - `item_values`: Current values for this array item
/// - `index`: Index of this item in the array
/// 
/// ## Returns
/// List of rendered field elements for the array item
fn render_item_fields(
  array_name: String,
  item_schema: SchemaProperty,
  item_values: dict.Dict(String, Value),
  index: Int,
) -> List(Element(FormMsg)) {
  case item_schema.properties {
    Some(props) ->
      dict.to_list(props)
      |> list.map(fn(entry) {
        let #(field_name, field_prop) = entry
        let value =
          dict.get(item_values, field_name) |> result.unwrap(types.NullValue)
        render_field(
          array_name,
          index,
          field_name,
          field_prop,
          value,
          list.contains(item_schema.required, field_name),
        )
      })
    None -> []
  }
}

/// Render a single field within an array item.
/// 
/// Uses the unified field renderers (string_field, number_field, boolean_field)
/// to render fields with consistent behavior across the application.
/// 
/// ## Parameters
/// - `array_name`: The parent array field name
/// - `index`: Index of the array item containing this field
/// - `field_name`: Name of the field within the array item
/// - `property`: Schema property for this field
/// - `value`: Current value of the field
/// - `required`: Whether this field is required within the array item
/// 
/// ## Returns
/// A rendered field element using the unified field renderers
/// 
/// ## Supported Field Types
/// - String fields (text input or select for enums)
/// - Number/Integer fields with constraints
/// - Boolean fields (radio buttons style)
fn render_field(
  array_name: String,
  index: Int,
  field_name: String,
  property: SchemaProperty,
  value: Value,
  required: Bool,
) -> Element(FormMsg) {
  // Create a path for this nested field
  let field_path = path.to_array_item_field(array_name, index, field_name)

  // Array item fields inherit read_only from their property
  let is_readonly = property.read_only

  let field_element = case property.field_type {
    Some(types.StringType) ->
      string_field.render(
        field_path,
        property,
        Some(value),
        required,
        False,
        is_readonly,
      )
    Some(types.NumberType) | Some(types.IntegerType) ->
      number_field.render(
        field_path,
        property,
        Some(value),
        required,
        False,
        is_readonly,
      )
    Some(types.BooleanType) ->
      boolean_field.render(
        field_path,
        property,
        Some(value),
        required,
        False,
        is_readonly,
      )
    _ ->
      html.div([class("unsupported-field")], [
        html.text("Unsupported field type"),
      ])
  }

  html.div([class("array-item-field")], [field_element])
}
