// String field renderer

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import form/model.{type FormMsg, FieldBlurred, FieldChanged}
import schema/types
import fields/field_common

// Render a string field
pub fn render(
  field_name: String,
  property: types.SchemaProperty,
  value: Option(types.FieldValue),
  is_required: Bool,
  is_disabled: Bool,
) -> Element(FormMsg) {
  case property.enum_values {
    Some(_enum_vals) -> render_enum(field_name, property, value, is_required, is_disabled)
    None -> {
      // Check if it's a textarea based on max length
      case property.string_constraints {
        Some(constraints) ->
          case constraints.max_length {
            Some(max) if max > 100 ->
              render_textarea(field_name, property, value, is_required, is_disabled)
            _ ->
              render_input(field_name, property, value, is_required, is_disabled)
          }
        None -> render_input(field_name, property, value, is_required, is_disabled)
      }
    }
  }
}

// Render a standard input field
fn render_input(
  field_name: String,
  property: types.SchemaProperty,
  value: Option(types.FieldValue),
  is_required: Bool,
  is_disabled: Bool,
) -> Element(FormMsg) {
  let current_value = case value {
    Some(types.StringValue(s)) -> s
    _ -> ""
  }

  let input_type = get_input_type(property)
  let extra_attrs = [
    attribute.type_(input_type),
    attribute.class("formosh-input"),
    ..get_string_constraints_attributes(property)
  ]
  
  let input_elem = html.input(
    field_common.input_attributes(field_name, current_value, is_required, is_disabled, extra_attrs)
  )
  
  field_common.field_wrapper(field_name, property, is_required, input_elem)
}

// Render a textarea field
fn render_textarea(
  field_name: String,
  property: types.SchemaProperty,
  value: Option(types.FieldValue),
  is_required: Bool,
  is_disabled: Bool,
) -> Element(FormMsg) {
  let current_value = case value {
    Some(types.StringValue(s)) -> s
    _ -> ""
  }

  let extra_attrs = [
    attribute.class("formosh-textarea"),
    ..get_string_constraints_attributes(property)
  ]
  
  let textarea_elem = html.textarea(
    field_common.input_attributes(field_name, current_value, is_required, is_disabled, extra_attrs),
    current_value
  )
  
  field_common.field_wrapper(field_name, property, is_required, textarea_elem)
}

// Render an enum field as select or radio buttons
pub fn render_enum(
  field_name: String,
  property: types.SchemaProperty,
  value: Option(types.FieldValue),
  is_required: Bool,
  is_disabled: Bool,
) -> Element(FormMsg) {
  case property.enum_values {
    None -> html.text("")
    Some(enum_vals) -> {
      let current_value = case value {
        Some(types.StringValue(s)) -> s
        _ -> ""
      }

      // Use radio buttons for small lists, select for larger ones
      case list.length(enum_vals) <= 5 {
        True -> render_radio_group(
          field_name,
          property,
          enum_vals,
          current_value,
          is_required,
          is_disabled,
        )
        False -> render_select(
          field_name,
          property,
          enum_vals,
          current_value,
          is_required,
          is_disabled,
        )
      }
    }
  }
}

// Render radio button group
fn render_radio_group(
  field_name: String,
  property: types.SchemaProperty,
  enum_vals: List(types.JsonValue),
  current_value: String,
  is_required: Bool,
  is_disabled: Bool,
) -> Element(FormMsg) {
  let radio_group = html.div(
    [attribute.class("formosh-radio-group")],
    list.map(enum_vals, fn(val) {
      let str_val = json_value_to_string(val)
      let radio_id = field_name <> "_" <> str_val
      
      html.div([attribute.class("formosh-radio-item")], [
        html.input([
          attribute.type_("radio"),
          attribute.id(radio_id),
          attribute.name(field_name),
          attribute.value(str_val),
          attribute.checked(str_val == current_value),
          attribute.required(is_required),
          attribute.disabled(is_disabled),
          event.on_click(FieldChanged(field_name, types.StringValue(str_val))),
        ]),
        html.label([attribute.for(radio_id)], [
          html.text(str_val),
        ]),
      ])
    }),
  )
  
  field_common.field_wrapper(field_name, property, is_required, radio_group)
}

// Render select dropdown
fn render_select(
  field_name: String,
  property: types.SchemaProperty,
  enum_vals: List(types.JsonValue),
  current_value: String,
  is_required: Bool,
  is_disabled: Bool,
) -> Element(FormMsg) {
  let select_elem = html.select([
    attribute.id(field_name),
    attribute.name(field_name),
    attribute.class("formosh-select"),
    attribute.required(is_required),
    attribute.disabled(is_disabled),
    event.on_change(fn(val) {
      FieldChanged(field_name, types.StringValue(val))
    }),
    event.on_blur(FieldBlurred(field_name)),
  ], [
    html.option([attribute.value("")], "Select an option..."),
    ..list.map(enum_vals, fn(val) {
      let str_val = json_value_to_string(val)
      html.option([
        attribute.value(str_val),
        attribute.selected(str_val == current_value),
      ], str_val)
    })
  ])
  
  field_common.field_wrapper(field_name, property, is_required, select_elem)
}


// Get input type based on string format
fn get_input_type(property: types.SchemaProperty) -> String {
  case property.string_constraints {
    Some(constraints) ->
      case constraints.format {
        Some(types.EmailFormat) -> "email"
        Some(types.UrlFormat) -> "url"
        Some(types.DateFormat) -> "date"
        Some(types.DateTimeFormat) -> "datetime-local"
        Some(types.TimeFormat) -> "time"
        _ -> "text"
      }
    None -> "text"
  }
}

// Get HTML attributes for string constraints
fn get_string_constraints_attributes(
  property: types.SchemaProperty,
) -> List(attribute.Attribute(FormMsg)) {
  case property.string_constraints {
    Some(constraints) -> {
      let attrs = []
      
      let attrs = case constraints.min_length {
        Some(min) ->
          list.append(attrs, [attribute.attribute("minlength", int.to_string(min))])
        None -> attrs
      }
      
      let attrs = case constraints.max_length {
        Some(max) ->
          list.append(attrs, [attribute.attribute("maxlength", int.to_string(max))])
        None -> attrs
      }
      
      let attrs = case constraints.pattern {
        Some(pattern) ->
          list.append(attrs, [attribute.attribute("pattern", pattern)])
        None -> attrs
      }
      
      attrs
    }
    None -> []
  }
}

// Convert JsonValue to string
fn json_value_to_string(val: types.JsonValue) -> String {
  case val {
    types.JsonString(s) -> s
    types.JsonNumber(n) -> float.to_string(n)
    types.JsonBool(True) -> "true"
    types.JsonBool(False) -> "false"
    types.JsonNull -> ""
    _ -> ""
  }
}