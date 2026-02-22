// String field renderer

import formosh/fields/field_common
import formosh/form/model.{type FormMsg, UpdateFieldPath}
import formosh/form/path
import formosh/schema/types
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// Render a string field with appropriate input type and constraints.
///
/// This is the main entry point for rendering string fields. It automatically
/// chooses the appropriate input type (text input, textarea, select, radio)
/// based on the field's constraints and enum values.
///
/// ## Parameters
/// - `field_name`: The field name for identification and events
/// - `property`: The schema property with type and constraint information
/// - `value`: The current field value, if any
/// - `is_required`: Whether the field is required
/// - `is_disabled`: Whether the field is disabled
/// - `is_readonly`: Whether the field is read-only
///
/// ## Returns
/// A complete field element with label, input, and help text
///
/// ## Field Type Selection
/// - Enum values → select dropdown or radio buttons
/// - Long text (maxLength > 100) → textarea
/// - Regular strings → text input with appropriate HTML type
pub fn render(
  field_path: path.FieldPath,
  property: types.SchemaProperty,
  value: Option(types.Value),
  is_required: Bool,
  is_disabled: Bool,
  is_readonly: Bool,
) -> Element(FormMsg) {
  case property.enum_values {
    Some(_enum_vals) ->
      render_enum(
        field_path,
        property,
        value,
        is_required,
        is_disabled,
        is_readonly,
      )
    None -> {
      // Check if it's a textarea based on max length
      case property.string_constraints {
        Some(constraints) ->
          case constraints.max_length {
            Some(max) if max > 100 ->
              render_textarea(
                field_path,
                property,
                value,
                is_required,
                is_disabled,
                is_readonly,
              )
            _ ->
              render_input(
                field_path,
                property,
                value,
                is_required,
                is_disabled,
                is_readonly,
              )
          }
        None ->
          render_input(
            field_path,
            property,
            value,
            is_required,
            is_disabled,
            is_readonly,
          )
      }
    }
  }
}

/// Render a standard HTML input element for string values.
///
/// Creates a single-line text input with the appropriate HTML input type
/// based on the string format (email, url, date, etc.) and applies any
/// string constraints as HTML attributes.
///
/// ## Parameters
/// - `field_name`: The field name for identification
/// - `property`: The schema property with constraints and format info
/// - `value`: The current field value
/// - `is_required`: Whether the field is required
/// - `is_disabled`: Whether the field is disabled
/// - `is_readonly`: Whether the field is read-only
///
/// ## Returns
/// A complete field element wrapped with label and help text
fn render_input(
  field_path: path.FieldPath,
  property: types.SchemaProperty,
  value: Option(types.Value),
  is_required: Bool,
  is_disabled: Bool,
  is_readonly: Bool,
) -> Element(FormMsg) {
  let current_value = field_common.extract_string_value(value)

  let input_type = get_input_type(property)
  let extra_attrs = [
    attribute.type_(input_type),
    attribute.class("formosh-input"),
    ..get_string_constraints_attributes(property)
  ]

  // Add readonly attribute if needed
  let extra_attrs = case is_readonly {
    True -> [attribute.attribute("readonly", "readonly"), ..extra_attrs]
    False -> extra_attrs
  }

  let input_elem =
    html.input(field_common.input_attributes(
      field_path,
      current_value,
      is_required,
      is_disabled,
      extra_attrs,
    ))

  field_common.field_wrapper_with_path(
    field_path,
    property,
    is_required,
    input_elem,
  )
}

/// Render a textarea element for multi-line string input.
///
/// Used for string fields with large maxLength constraints (> 100 characters)
/// to provide a better user experience for longer text input.
///
/// ## Parameters
/// - `field_name`: The field name for identification
/// - `property`: The schema property with constraints
/// - `value`: The current field value
/// - `is_required`: Whether the field is required
/// - `is_disabled`: Whether the field is disabled
/// - `is_readonly`: Whether the field is read-only
///
/// ## Returns
/// A complete textarea field wrapped with label and help text
fn render_textarea(
  field_path: path.FieldPath,
  property: types.SchemaProperty,
  value: Option(types.Value),
  is_required: Bool,
  is_disabled: Bool,
  is_readonly: Bool,
) -> Element(FormMsg) {
  let current_value = field_common.extract_string_value(value)

  let extra_attrs = [
    attribute.class("formosh-textarea"),
    ..get_string_constraints_attributes(property)
  ]

  // Add readonly attribute if needed
  let extra_attrs = case is_readonly {
    True -> [attribute.attribute("readonly", "readonly"), ..extra_attrs]
    False -> extra_attrs
  }

  let textarea_elem =
    html.textarea(
      field_common.input_attributes(
        field_path,
        current_value,
        is_required,
        is_disabled,
        extra_attrs,
      ),
      current_value,
    )

  field_common.field_wrapper_with_path(
    field_path,
    property,
    is_required,
    textarea_elem,
  )
}

/// Render an enum field as either radio buttons or a select dropdown.
///
/// For enum fields (fields with a limited set of allowed values), this function
/// chooses between radio buttons (for small lists ≤ 5 options) and select
/// dropdowns (for larger lists) to provide the best user experience.
///
/// ## Parameters
/// - `field_name`: The field name for identification
/// - `property`: The schema property containing enum values
/// - `value`: The current field value
/// - `is_required`: Whether the field is required
/// - `is_disabled`: Whether the field is disabled
/// - `is_readonly`: Whether the field is read-only
///
/// ## Returns
/// A complete field element with appropriate enum input control
///
/// ## Selection Logic
/// - ≤ 5 options: Radio button group for easy scanning
/// - > 5 options: Select dropdown to save space
pub fn render_enum(
  field_path: path.FieldPath,
  property: types.SchemaProperty,
  value: Option(types.Value),
  is_required: Bool,
  is_disabled: Bool,
  is_readonly: Bool,
) -> Element(FormMsg) {
  case property.enum_values {
    None -> html.text("")
    Some(enum_vals) -> {
      let current_value = field_common.extract_string_value(value)

      // Use radio buttons for small lists, select for larger ones
      case list.length(enum_vals) <= 5 {
        True ->
          render_radio_group(
            field_path,
            property,
            enum_vals,
            current_value,
            is_required,
            is_disabled,
            is_readonly,
          )
        False ->
          render_select(
            field_path,
            property,
            enum_vals,
            current_value,
            is_required,
            is_disabled,
            is_readonly,
          )
      }
    }
  }
}

/// Render a radio button group for enum values.
///
/// Creates a group of radio buttons for selecting from a small set of enum values.
/// Each radio button is properly labeled and grouped under the same field name.
///
/// ## Parameters
/// - `field_name`: The field name for grouping radio buttons
/// - `property`: The schema property for labeling and help text
/// - `enum_vals`: The list of allowed enum values
/// - `current_value`: The currently selected value
/// - `is_required`: Whether a selection is required
/// - `is_disabled`: Whether the entire group is disabled
/// - `is_readonly`: Whether the field is read-only
///
/// ## Returns
/// A complete radio button group with wrapper, label, and help text
fn render_radio_group(
  field_path: path.FieldPath,
  property: types.SchemaProperty,
  enum_vals: List(types.Value),
  current_value: String,
  is_required: Bool,
  is_disabled: Bool,
  is_readonly: Bool,
) -> Element(FormMsg) {
  let field_name = path.get_field_name(field_path)
  // For readonly, disable the radio buttons to prevent changes
  let effective_disabled = is_disabled || is_readonly

  let radio_group =
    html.div(
      [attribute.class("formosh-radio-group")],
      list.map(enum_vals, fn(val) {
        let str_val = value_to_string(val)
        let radio_id = field_name <> "_" <> str_val

        html.div([attribute.class("formosh-radio-item")], [
          html.input([
            attribute.type_("radio"),
            attribute.id(radio_id),
            attribute.name(field_name),
            attribute.value(str_val),
            attribute.checked(str_val == current_value),
            attribute.required(is_required),
            attribute.disabled(effective_disabled),
            event.on_click(UpdateFieldPath(
              field_path,
              types.StringValue(str_val),
            )),
          ]),
          html.label([attribute.for(radio_id)], [
            html.text(str_val),
          ]),
        ])
      }),
    )

  field_common.field_wrapper_with_path(
    field_path,
    property,
    is_required,
    radio_group,
  )
}

/// Render a select dropdown for enum values.
///
/// Creates a select dropdown with options for each enum value, including
/// a placeholder option. Used for enum fields with many options where
/// radio buttons would take too much space.
///
/// ## Parameters
/// - `field_name`: The field name for identification
/// - `property`: The schema property for labeling and help text
/// - `enum_vals`: The list of allowed enum values
/// - `current_value`: The currently selected value
/// - `is_required`: Whether a selection is required
/// - `is_disabled`: Whether the dropdown is disabled
/// - `is_readonly`: Whether the field is read-only
///
/// ## Returns
/// A complete select dropdown with wrapper, label, and help text
fn render_select(
  field_path: path.FieldPath,
  property: types.SchemaProperty,
  enum_vals: List(types.Value),
  current_value: String,
  is_required: Bool,
  is_disabled: Bool,
  is_readonly: Bool,
) -> Element(FormMsg) {
  let field_name = path.get_field_name(field_path)
  // For readonly, disable the select to prevent changes
  let effective_disabled = is_disabled || is_readonly

  let select_elem =
    html.select(
      [
        attribute.id(field_name),
        attribute.name(field_name),
        attribute.class("formosh-select"),
        attribute.required(is_required),
        attribute.disabled(effective_disabled),
        event.on_change(fn(val) {
          UpdateFieldPath(field_path, types.StringValue(val))
        }),
      ],
      [
        html.option([attribute.value("")], "Select an option..."),
        ..list.map(enum_vals, fn(val) {
          let str_val = value_to_string(val)
          html.option(
            [
              attribute.value(str_val),
              attribute.selected(str_val == current_value),
            ],
            str_val,
          )
        })
      ],
    )

  field_common.field_wrapper_with_path(
    field_path,
    property,
    is_required,
    select_elem,
  )
}

/// Determine the appropriate HTML input type based on string format.
/// 
/// Maps JSON Schema string formats to appropriate HTML5 input types
/// to enable browser validation and better mobile keyboard support.
/// 
/// ## Parameters
/// - `property`: The schema property that may contain format information
/// 
/// ## Returns
/// An HTML input type string ("email", "url", "date", "text", etc.)
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

/// Convert string constraints to HTML input attributes.
/// 
/// Takes string validation constraints from the JSON Schema and converts
/// them to appropriate HTML attributes (minlength, maxlength, pattern)
/// for client-side validation and user feedback.
/// 
/// ## Parameters
/// - `property`: The schema property containing string constraints
/// 
/// ## Returns
/// A list of HTML attributes representing the constraints
/// 
/// ## Generated Attributes
/// - `minlength`: From minLength constraint
/// - `maxlength`: From maxLength constraint  
/// - `pattern`: From pattern constraint (regex)
fn get_string_constraints_attributes(
  property: types.SchemaProperty,
) -> List(attribute.Attribute(FormMsg)) {
  case property.string_constraints {
    Some(constraints) -> {
      let attrs = []

      let attrs = case constraints.min_length {
        Some(min) ->
          list.append(attrs, [
            attribute.attribute("minlength", int.to_string(min)),
          ])
        None -> attrs
      }

      let attrs = case constraints.max_length {
        Some(max) ->
          list.append(attrs, [
            attribute.attribute("maxlength", int.to_string(max)),
          ])
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

/// Convert a Value to its string representation.
/// 
/// Used primarily for rendering enum option values and labels.
/// Handles different value types appropriately for display.
/// 
/// ## Parameters
/// - `val`: The Value to convert
/// 
/// ## Returns
/// A string representation of the value
/// 
/// ## Conversion Rules
/// - Strings: returned as-is
/// - Numbers: converted to string representation
/// - Booleans: "true" or "false"
/// - Null: empty string
/// - Arrays/Objects: empty string (not displayable as simple text)
fn value_to_string(val: types.Value) -> String {
  case val {
    types.StringValue(s) -> s
    types.NumberValue(n) -> float.to_string(n)
    types.IntegerValue(i) -> int.to_string(i)
    types.BooleanValue(True) -> "true"
    types.BooleanValue(False) -> "false"
    types.NullValue -> ""
    _ -> ""
  }
}
