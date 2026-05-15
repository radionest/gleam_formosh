// String field renderer

import formosh/fields/field_common.{type FieldRenderCtx}
import formosh/form/model.{type FormMsg, UpdateFieldPath}
import formosh/form/path
import formosh/schema/types
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// Render a string field with appropriate input type and constraints.
///
/// Picks between text input, textarea, select dropdown, and radio buttons
/// based on the property's `enum`, `oneOf`, and string constraints.
///
/// ## Field Type Selection
/// - `oneOf` const+title → radio or select
/// - `enum` values → select dropdown or radio buttons
/// - Long text (maxLength > 100) → textarea
/// - Regular strings → text input with format-derived HTML type
pub fn render(ctx: FieldRenderCtx) -> Element(FormMsg) {
  // Check oneOf first (has const+title options), then enum_values
  let one_of_options = case ctx.property.one_of {
    Some(schemas) -> extract_one_of_options(schemas)
    None -> []
  }

  case one_of_options {
    [_, ..] -> render_one_of_enum(ctx, one_of_options)
    [] -> render_string_or_enum(ctx)
  }
}

/// Render a string field as either enum or text input.
fn render_string_or_enum(ctx: FieldRenderCtx) -> Element(FormMsg) {
  case ctx.property.enum_values {
    Some(_enum_vals) -> render_enum(ctx)
    None -> {
      // Check if it's a textarea based on max length
      case ctx.property.string_constraints {
        Some(constraints) ->
          case constraints.max_length {
            Some(max) if max > 100 -> render_textarea(ctx)
            _ -> render_input(ctx)
          }
        None -> render_input(ctx)
      }
    }
  }
}

/// Render a standard HTML input with format-derived type and constraints.
fn render_input(ctx: FieldRenderCtx) -> Element(FormMsg) {
  let current_value = field_common.extract_string_value(ctx.value)

  let input_type = get_input_type(ctx.property)
  let extra_attrs = [
    attribute.type_(input_type),
    attribute.class("formosh-input"),
    attribute.attribute("part", "input"),
    ..get_string_constraints_attributes(ctx.property)
  ]

  let extra_attrs = case ctx.is_readonly {
    True -> [attribute.attribute("readonly", "readonly"), ..extra_attrs]
    False -> extra_attrs
  }

  let input_elem =
    html.input(field_common.input_attributes(
      ctx.path,
      current_value,
      ctx.is_required,
      ctx.is_disabled,
      extra_attrs,
    ))

  field_common.field_wrapper_with_path(
    ctx.path,
    ctx.property,
    ctx.is_required,
    input_elem,
  )
}

/// Render a textarea for string fields with `maxLength > 100`.
fn render_textarea(ctx: FieldRenderCtx) -> Element(FormMsg) {
  let current_value = field_common.extract_string_value(ctx.value)

  let extra_attrs = [
    attribute.class("formosh-textarea"),
    attribute.attribute("part", "textarea"),
    ..get_string_constraints_attributes(ctx.property)
  ]

  let extra_attrs = case ctx.is_readonly {
    True -> [attribute.attribute("readonly", "readonly"), ..extra_attrs]
    False -> extra_attrs
  }

  let textarea_elem =
    html.textarea(
      field_common.input_attributes(
        ctx.path,
        current_value,
        ctx.is_required,
        ctx.is_disabled,
        extra_attrs,
      ),
      current_value,
    )

  field_common.field_wrapper_with_path(
    ctx.path,
    ctx.property,
    ctx.is_required,
    textarea_elem,
  )
}

/// Render an enum field as either radio buttons or a select dropdown.
///
/// ## Selection Logic
/// - ≤ 5 options: Radio button group for easy scanning
/// - > 5 options: Select dropdown to save space
pub fn render_enum(ctx: FieldRenderCtx) -> Element(FormMsg) {
  // Check oneOf first for const+title options
  let one_of_options = case ctx.property.one_of {
    Some(schemas) -> extract_one_of_options(schemas)
    None -> []
  }

  case one_of_options {
    [_, ..] -> render_one_of_enum(ctx, one_of_options)
    [] -> render_regular_enum(ctx)
  }
}

/// Render a regular enum field (without oneOf).
fn render_regular_enum(ctx: FieldRenderCtx) -> Element(FormMsg) {
  case ctx.property.enum_values {
    None -> element.none()
    Some(enum_vals) -> {
      let current_value = field_common.extract_string_value(ctx.value)

      case list.length(enum_vals) <= 5 {
        True -> render_radio_group(ctx, enum_vals, current_value)
        False -> render_select(ctx, enum_vals, current_value)
      }
    }
  }
}

/// Render a radio button group for enum values (≤ 5 options).
fn render_radio_group(
  ctx: FieldRenderCtx,
  enum_vals: List(types.Value),
  current_value: String,
) -> Element(FormMsg) {
  let field_id = path.to_string(ctx.path)
  let effective_disabled = ctx.is_disabled || ctx.is_readonly

  let radio_group =
    html.div(
      [
        attribute.class("formosh-radio-group"),
        attribute.attribute("part", "radio-group"),
      ],
      list.map(enum_vals, fn(val) {
        let str_val = value_to_string(val)
        let radio_id = field_id <> "_" <> str_val

        html.div(
          [
            attribute.class("formosh-radio-item"),
            attribute.attribute("part", "radio-item"),
          ],
          [
            html.input([
              attribute.type_("radio"),
              attribute.id(radio_id),
              attribute.name(field_id),
              attribute.value(str_val),
              attribute.checked(str_val == current_value),
              attribute.required(ctx.is_required),
              attribute.disabled(effective_disabled),
              event.on_click(UpdateFieldPath(
                ctx.path,
                types.StringValue(str_val),
              )),
            ]),
            html.label([attribute.for(radio_id)], [
              html.text(str_val),
            ]),
          ],
        )
      }),
    )

  field_common.field_wrapper_with_path(
    ctx.path,
    ctx.property,
    ctx.is_required,
    radio_group,
  )
}

/// Render a select dropdown for enum values (> 5 options).
fn render_select(
  ctx: FieldRenderCtx,
  enum_vals: List(types.Value),
  current_value: String,
) -> Element(FormMsg) {
  let field_id = path.to_string(ctx.path)
  let effective_disabled = ctx.is_disabled || ctx.is_readonly

  let select_elem =
    html.select(
      [
        attribute.id(field_id),
        attribute.name(field_id),
        attribute.class("formosh-select"),
        attribute.attribute("part", "select"),
        attribute.required(ctx.is_required),
        attribute.disabled(effective_disabled),
        event.on_change(fn(val) {
          UpdateFieldPath(ctx.path, types.StringValue(val))
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
    ctx.path,
    ctx.property,
    ctx.is_required,
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

/// Extract const+title option pairs from oneOf sub-schemas.
///
/// Each sub-schema with a single const value (stored as enum_values with one item)
/// produces a (value, label) pair. The label comes from the sub-schema's title,
/// falling back to the string representation of the const value.
fn extract_one_of_options(
  one_of: List(types.SchemaProperty),
) -> List(#(String, String)) {
  use schema <- list.filter_map(one_of)
  use vals <- result.try(option.to_result(schema.enum_values, Nil))
  use const_val <- result.try(case vals {
    [val] -> Ok(val)
    _ -> Error(Nil)
  })
  let value = value_to_string(const_val)
  let label = option.unwrap(schema.title, value)
  Ok(#(value, label))
}

/// Render a oneOf field with const+title options as radio buttons or select.
fn render_one_of_enum(
  ctx: FieldRenderCtx,
  options: List(#(String, String)),
) -> Element(FormMsg) {
  let current_value = field_common.extract_string_value(ctx.value)

  case list.length(options) <= 5 {
    True -> render_one_of_radio_group(ctx, options, current_value)
    False -> render_one_of_select(ctx, options, current_value)
  }
}

/// Render radio buttons for oneOf const+title options.
fn render_one_of_radio_group(
  ctx: FieldRenderCtx,
  options: List(#(String, String)),
  current_value: String,
) -> Element(FormMsg) {
  let field_id = path.to_string(ctx.path)
  let effective_disabled = ctx.is_disabled || ctx.is_readonly

  let radio_group =
    html.div(
      [
        attribute.class("formosh-radio-group"),
        attribute.attribute("part", "radio-group"),
      ],
      list.map(options, fn(option) {
        let #(value, label) = option
        let radio_id = field_id <> "_" <> value

        html.div(
          [
            attribute.class("formosh-radio-item"),
            attribute.attribute("part", "radio-item"),
          ],
          [
            html.input([
              attribute.type_("radio"),
              attribute.id(radio_id),
              attribute.name(field_id),
              attribute.value(value),
              attribute.checked(value == current_value),
              attribute.required(ctx.is_required),
              attribute.disabled(effective_disabled),
              event.on_click(UpdateFieldPath(ctx.path, types.StringValue(value))),
            ]),
            html.label([attribute.for(radio_id)], [
              html.text(label),
            ]),
          ],
        )
      }),
    )

  field_common.field_wrapper_with_path(
    ctx.path,
    ctx.property,
    ctx.is_required,
    radio_group,
  )
}

/// Render a select dropdown for oneOf const+title options.
fn render_one_of_select(
  ctx: FieldRenderCtx,
  options: List(#(String, String)),
  current_value: String,
) -> Element(FormMsg) {
  let field_id = path.to_string(ctx.path)
  let effective_disabled = ctx.is_disabled || ctx.is_readonly

  let select_elem =
    html.select(
      [
        attribute.id(field_id),
        attribute.name(field_id),
        attribute.class("formosh-select"),
        attribute.attribute("part", "select"),
        attribute.required(ctx.is_required),
        attribute.disabled(effective_disabled),
        event.on_change(fn(val) {
          UpdateFieldPath(ctx.path, types.StringValue(val))
        }),
      ],
      [
        html.option([attribute.value("")], "Select an option..."),
        ..list.map(options, fn(option) {
          let #(value, label) = option
          html.option(
            [
              attribute.value(value),
              attribute.selected(value == current_value),
            ],
            label,
          )
        })
      ],
    )

  field_common.field_wrapper_with_path(
    ctx.path,
    ctx.property,
    ctx.is_required,
    select_elem,
  )
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
