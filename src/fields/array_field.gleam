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
import form/model.{type FormMsg, AddArrayItem, ArrayItemChanged, RemoveArrayItem}

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
        event.on_click(AddArrayItem(name)),
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
              event.on_click(RemoveArrayItem(array_name, index)),
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
              ArrayItemChanged(array_name, index, field_name, types.StringValue(val))
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
            ArrayItemChanged(array_name, index, field_name, types.StringValue(val))
          }),
        ])
    },
  ])
}

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
        case property.field_type {
          Some(types.IntegerType) ->
            case int.parse(val) {
              Ok(i) -> ArrayItemChanged(array_name, index, field_name, types.IntegerValue(i))
              Error(_) -> ArrayItemChanged(array_name, index, field_name, types.NullValue)
            }
          _ ->
            case float.parse(val) {
              Ok(f) -> ArrayItemChanged(array_name, index, field_name, types.NumberValue(f))
              Error(_) -> ArrayItemChanged(array_name, index, field_name, types.NullValue)
            }
        }
      }),
    ]),
  ])
}

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
          ArrayItemChanged(array_name, index, field_name, types.BooleanValue(checked))
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