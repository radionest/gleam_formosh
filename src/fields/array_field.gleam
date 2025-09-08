/// Array field renderer for dynamic lists of structured data.
/// 
/// This module handles rendering of array fields that contain lists of objects
/// with defined properties. It supports adding, removing, and editing items
/// within the array, with each item rendered as a group of sub-fields.
/// 
/// The array field supports nested object schemas with various field types
/// including strings, numbers, booleans, and enums within each array item.

import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import lustre/attribute.{class, type_}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import schema/types.{type FieldValue, type SchemaProperty}
import form/model.{type FormMsg, AddArrayItemPath, RemoveArrayItemPath, UpdateFieldPath}
import form/path

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
  values: List(dict.Dict(String, FieldValue)),
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
      Some(desc) ->
        html.p([class("field-description")], [html.text(desc)])
      None -> element.none()
    },
    html.div([class("array-items")], 
      list.index_map(values, fn(item_values, index) {
        render_array_item(name, property, item_values, index)
      })
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
  item_values: dict.Dict(String, FieldValue),
  index: Int,
) -> Element(FormMsg) {
  case property.items {
    Some(item_schema) ->
      html.div([class("array-item")], [
        html.div([class("array-item-header")], [
          html.span([class("array-item-index")], [
            html.text("№ " <> int.to_string(index + 1))
          ]),
          html.button(
            [
              type_("button"),
              class("remove-array-item"),
              // Use new path-based message
              event.on_click(RemoveArrayItemPath(path.from_field_name(array_name), index)),
            ],
            [html.text("Удалить")],
          ),
        ]),
        html.div([class("array-item-fields")], 
          render_item_fields(array_name, item_schema, item_values, index)
        ),
      ])
    None -> element.none()
  }
}

/// Render all fields for a single array item.
/// 
/// Takes the item schema properties and renders each field according to
/// its type and constraints. Each field is connected to the array through
/// ArrayItemChanged messages.
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
  item_values: dict.Dict(String, FieldValue),
  index: Int,
) -> List(Element(FormMsg)) {
  case item_schema.properties {
    Some(props) ->
      dict.to_list(props)
      |> list.map(fn(entry) {
        let #(field_name, field_prop) = entry
        let value = dict.get(item_values, field_name) |> result.unwrap(types.NullValue)
        render_field(array_name, index, field_name, field_prop, value, 
          list.contains(item_schema.required, field_name))
      })
    None -> []
  }
}

/// Render a single field within an array item.
/// 
/// Determines the appropriate field renderer based on the field type and
/// renders it with proper event handling for array item updates.
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
/// A rendered field element with array-specific event handling
/// 
/// ## Supported Field Types
/// - String fields (text input or select for enums)
/// - Number/Integer fields with constraints
/// - Boolean fields (checkbox style)
fn render_field(
  array_name: String,
  index: Int,
  field_name: String,
  property: SchemaProperty,
  value: FieldValue,
  required: Bool,
) -> Element(FormMsg) {
  let field_element = case property.field_type {
    Some(types.StringType) ->
      render_string_field(array_name, index, field_name, property, value, required)
    Some(types.NumberType) | Some(types.IntegerType) ->
      render_number_field(array_name, index, field_name, property, value, required)
    Some(types.BooleanType) ->
      render_boolean_field(array_name, index, field_name, property, value, required)
    _ ->
      html.div([class("unsupported-field")], [
        html.text("Unsupported field type")
      ])
  }
  
  html.div([class("array-item-field")], [field_element])
}

/// Render a string field within an array item.
/// 
/// Creates either a text input or select dropdown based on whether the
/// field has enum values. Handles ArrayItemChanged events for updates.
/// 
/// ## Parameters
/// - `array_name`: The parent array field name
/// - `index`: Array item index
/// - `field_name`: Name of the string field
/// - `property`: Schema property with string constraints and enum values
/// - `value`: Current string value
/// - `required`: Whether the field is required
/// 
/// ## Returns
/// A string input field (text input or select) for array items
fn render_string_field(
  array_name: String,
  index: Int,
  field_name: String,
  property: SchemaProperty,
  value: FieldValue,
  required: Bool,
) -> Element(FormMsg) {
  let string_value = case value {
    types.StringValue(s) -> s
    _ -> ""
  }
  
  html.div([class("field-group")], [
    html.label([class("field-label")], [
      html.text(option.unwrap(property.title, field_name)),
      case required {
        True -> html.span([class("required")], [html.text(" *")])
        False -> element.none()
      },
    ]),
    case property.description {
      Some(desc) -> html.p([class("field-help")], [html.text(desc)])
      None -> element.none()
    },
    case property.enum_values {
      Some(enum_vals) ->
        html.select(
          [
            class("field-select"),
            event.on_input(fn(val) {
              // Use new path-based message for nested field updates
              UpdateFieldPath(
                path.to_array_item_field(array_name, index, field_name),
                types.StringValue(val)
              )
            }),
          ],
          list.map(enum_vals, fn(enum_val) {
            case enum_val {
              types.JsonString(s) ->
                html.option(
                  [
                    attribute.value(s),
                    attribute.selected(s == string_value),
                  ],
                  s
                )
              _ -> html.option([], "")
            }
          }),
        )
      None ->
        html.input([
          type_("text"),
          class("field-input"),
          attribute.value(string_value),
          event.on_input(fn(val) {
            // Use new path-based message for nested field updates
            UpdateFieldPath(
              path.to_array_item_field(array_name, index, field_name),
              types.StringValue(val)
            )
          }),
        ])
    },
  ])
}

/// Render a number field within an array item.
/// 
/// Creates a number input with appropriate constraints and handles both
/// integer and float types. Parses input and sends ArrayItemChanged events.
/// 
/// ## Parameters
/// - `array_name`: The parent array field name
/// - `index`: Array item index
/// - `field_name`: Name of the number field
/// - `property`: Schema property with numeric constraints and type info
/// - `value`: Current numeric value
/// - `required`: Whether the field is required
/// 
/// ## Returns
/// A number input field with constraints for array items
/// 
/// ## Note
/// The numeric constraint attribute handling in this function has some
/// implementation issues that should be addressed for proper validation.
fn render_number_field(
  array_name: String,
  index: Int,
  field_name: String,
  property: SchemaProperty,
  value: FieldValue,
  required: Bool,
) -> Element(FormMsg) {
  let number_value = case value {
    types.NumberValue(n) -> float.to_string(n)
    types.IntegerValue(i) -> int.to_string(i)
    _ -> ""
  }
  
  html.div([class("field-group")], [
    html.label([class("field-label")], [
      html.text(option.unwrap(property.title, field_name)),
      case required {
        True -> html.span([class("required")], [html.text(" *")])
        False -> element.none()
      },
    ]),
    case property.description {
      Some(desc) -> html.p([class("field-help")], [html.text(desc)])
      None -> element.none()
    },
    html.input([
      type_("number"),
      class("field-input"),
      attribute.value(number_value),
      case property.number_constraints {
        Some(constraints) -> {
          let attrs = []
          let attrs = case constraints.minimum {
            Some(min) -> list.append(attrs, [attribute.min(float.to_string(min))])
            None -> attrs
          }
          let attrs = case constraints.maximum {
            Some(max) -> list.append(attrs, [attribute.max(float.to_string(max))])
            None -> attrs
          }
          case attrs {
            [] -> attribute.class("")
            [a] -> a
            [_a, _b] -> attribute.classes([#("", True)])
            _ -> attribute.class("")
          }
        }
        None -> attribute.class("")
      },
      event.on_input(fn(val) {
        let path_to_field = path.to_array_item_field(array_name, index, field_name)
        case property.field_type {
          Some(types.IntegerType) ->
            case int.parse(val) {
              Ok(i) -> UpdateFieldPath(path_to_field, types.IntegerValue(i))
              Error(_) -> UpdateFieldPath(path_to_field, types.NullValue)
            }
          _ ->
            case float.parse(val) {
              Ok(f) -> UpdateFieldPath(path_to_field, types.NumberValue(f))
              Error(_) -> UpdateFieldPath(path_to_field, types.NullValue)
            }
        }
      }),
    ]),
  ])
}

/// Render a boolean field within an array item.
/// 
/// Creates a checkbox input for boolean values within array items.
/// Uses checkbox style rather than radio buttons for compactness.
/// 
/// ## Parameters
/// - `array_name`: The parent array field name
/// - `index`: Array item index
/// - `field_name`: Name of the boolean field
/// - `property`: Schema property for the boolean field
/// - `value`: Current boolean value
/// - `required`: Whether the field is required
/// 
/// ## Returns
/// A checkbox input for boolean values in array items
fn render_boolean_field(
  array_name: String,
  index: Int,
  field_name: String,
  property: SchemaProperty,
  value: FieldValue,
  required: Bool,
) -> Element(FormMsg) {
  let bool_value = case value {
    types.BooleanValue(b) -> b
    _ -> False
  }
  
  html.div([class("field-group checkbox-group")], [
    html.label([class("checkbox-label")], [
      html.input([
        type_("checkbox"),
        class("field-checkbox"),
        attribute.checked(bool_value),
        event.on_check(fn(checked) {
          // Use new path-based message for nested field updates
          UpdateFieldPath(
            path.to_array_item_field(array_name, index, field_name),
            types.BooleanValue(checked)
          )
        }),
      ]),
      html.span([], [
        html.text(option.unwrap(property.title, field_name)),
        case required {
          True -> html.span([class("required")], [html.text(" *")])
          False -> element.none()
        },
      ]),
    ]),
    case property.description {
      Some(desc) -> html.p([class("field-help")], [html.text(desc)])
      None -> element.none()
    },
  ])
}