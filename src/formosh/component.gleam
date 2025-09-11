// Reusable form component for Formosh
// This module provides a Lustre component that can be embedded in applications
// with configurable submission endpoint and other properties.

import form/model.{type FormModel, type FormMsg, FormSubmit}
import form/update
import form/view
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre
import lustre/attribute.{type Attribute}
import lustre/component
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/event
import schema/parser
import schema/types.{
  type JsonSchema, type Value, ArrayValue, BooleanValue, IntegerValue, NullValue,
  NumberValue, ObjectValue, StringValue,
}

// COMPONENT CONFIGURATION -----------------------------------------------------

/// Register the form component as a Web Component.
/// 
/// This allows the component to be used as a custom HTML element:
/// ```html
/// <formosh-form 
///   schema='{"type": "object", ...}'
///   submit-url="https://api.example.com/submit">
/// </formosh-form>
/// ```
pub fn register() -> Result(Nil, lustre.Error) {
  let component =
    lustre.component(init, update, view, [
      // Listen for schema changes (JSON string)
      component.on_attribute_change("schema", fn(value) {
        case parser.parse_schema(value) {
          Ok(schema) -> Ok(SchemaChanged(schema))
          Error(_) -> Error(Nil)
        }
      }),
      // Listen for submit URL changes
      component.on_attribute_change("submit-url", fn(value) {
        Ok(SubmitUrlChanged(value))
      }),
      // Listen for submit method changes (GET, POST, PUT, etc.)
      component.on_attribute_change("submit-method", fn(value) {
        Ok(SubmitMethodChanged(value))
      }),
      // Listen for CSS prefix changes
      component.on_attribute_change("css-prefix", fn(value) {
        Ok(CssPrefixChanged(value))
      }),
    ])

  lustre.register(component, "formosh-form")
}

/// Create a form component element with attributes.
/// 
/// This function provides a convenient way to create the component
/// programmatically within a Lustre application.
/// 
/// ## Example
/// ```gleam
/// import formosh/component
/// 
/// let form = component.element([
///   component.schema(my_schema),
///   component.submit_url("https://api.example.com/submit"),
///   component.on_submit(HandleFormSubmit),
/// ])
/// ```
pub fn element(attributes: List(Attribute(msg))) -> Element(msg) {
  element.element("formosh-form", attributes, [])
}

// ATTRIBUTES ------------------------------------------------------------------

/// Set the JSON Schema for the form.
/// 
/// This can be either a JSON string or a JsonSchema object when used
/// programmatically.
pub fn schema(_schema: JsonSchema) -> Attribute(msg) {
  // For now, just serialize to empty JSON - would need proper serialization
  attribute.attribute("schema", "{}")
}

/// Set the JSON Schema as a string attribute.
pub fn schema_string(schema_json: String) -> Attribute(msg) {
  attribute.attribute("schema", schema_json)
}

/// Set the submission URL for the form.
pub fn submit_url(url: String) -> Attribute(msg) {
  attribute.attribute("submit-url", url)
}

/// Set the HTTP method for form submission (default: POST).
pub fn submit_method(method: String) -> Attribute(msg) {
  attribute.attribute("submit-method", method)
}

/// Set the CSS class prefix for form elements.
pub fn css_prefix(prefix: String) -> Attribute(msg) {
  attribute.attribute("css-prefix", prefix)
}

/// Listen for form submission events.
/// 
/// The handler receives the form data as a JSON object in the event detail.
pub fn on_submit(handler: fn(dict.Dict(String, Value)) -> msg) -> Attribute(msg) {
  event.on("formosh-submit", {
    decode.at(["detail", "values"], decode.dynamic)
    |> decode.map(fn(_data) {
      // TODO: Properly decode the form values from dynamic
      handler(dict.new())
    })
  })
}

/// Listen for form validation events.
pub fn on_validate(handler: fn(Bool) -> msg) -> Attribute(msg) {
  event.on("formosh-validate", {
    decode.at(["detail", "isValid"], decode.bool)
    |> decode.map(handler)
  })
}

/// Listen for form change events.
pub fn on_change(handler: fn(dict.Dict(String, Value)) -> msg) -> Attribute(msg) {
  event.on("formosh-change", {
    decode.at(["detail", "values"], decode.dynamic)
    |> decode.map(fn(_data) {
      // TODO: Properly decode the form values from dynamic
      handler(dict.new())
    })
  })
}

// MODEL -----------------------------------------------------------------------

/// Component-specific model that wraps the form model.
type Model {
  Model(
    // The core form model
    form_model: Option(FormModel),
    // Component configuration
    submit_url: Option(String),
    submit_method: String,
    css_prefix: String,
  )
}

fn init(_flags) -> #(Model, Effect(Msg)) {
  #(
    Model(
      form_model: None,
      submit_url: None,
      submit_method: "POST",
      css_prefix: "formosh",
    ),
    effect.none(),
  )
}

// UPDATE ----------------------------------------------------------------------

/// Component-specific messages that extend the form messages.
type Msg {
  // Component configuration messages
  SchemaChanged(JsonSchema)
  SubmitUrlChanged(String)
  SubmitMethodChanged(String)
  CssPrefixChanged(String)
  
  // Form messages (wrapped)
  FormMessage(FormMsg)
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    SchemaChanged(schema) -> {
      // Initialize a new form model with the schema
      let form_model = model.init(schema)
      #(
        Model(..model, form_model: Some(form_model)),
        // Emit a ready event to notify parent
        event.emit("formosh-ready", json.object([
          #("schema", json.string("loaded")),
        ])),
      )
    }
    
    SubmitUrlChanged(url) -> {
      #(Model(..model, submit_url: Some(url)), effect.none())
    }
    
    SubmitMethodChanged(method) -> {
      #(Model(..model, submit_method: method), effect.none())
    }
    
    CssPrefixChanged(prefix) -> {
      #(Model(..model, css_prefix: prefix), effect.none())
    }
    
    FormMessage(form_msg) -> {
      case model.form_model {
        Some(form_model) -> {
          // Handle form messages
          let #(updated_form, form_effect) = 
            update.update(form_model, form_msg)
          
          // Check if this was a submit message
          let submit_effect = case form_msg {
            FormSubmit -> {
              // Emit submit event with form data
              case model.submit_url {
                Some(url) -> {
                  effect.batch([
                    emit_submit_event(updated_form, url, model.submit_method),
                    emit_change_event(updated_form),
                  ])
                }
                None -> {
                  emit_submit_event(updated_form, "", "")
                }
              }
            }
            _ -> emit_change_event(updated_form)
          }
          
          #(
            Model(..model, form_model: Some(updated_form)),
            effect.batch([
              form_effect |> effect.map(FormMessage),
              submit_effect,
            ]),
          )
        }
        
        None -> {
          // No schema loaded yet
          #(model, effect.none())
        }
      }
    }
  }
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  case model.form_model {
    Some(form_model) -> {
      // Render the form using the existing view function
      view.view(form_model)
      |> element.map(FormMessage)
    }
    
    None -> {
      // No schema loaded yet
      element.element("div", [
        attribute.class(model.css_prefix <> "-loading"),
      ], [
        element.text("Waiting for schema..."),
      ])
    }
  }
}

// EFFECTS ---------------------------------------------------------------------

/// Convert a Value to JSON for serialization.
fn value_to_json(value: Value) -> json.Json {
  case value {
    StringValue(s) -> json.string(s)
    NumberValue(n) -> json.float(n)
    IntegerValue(i) -> json.int(i)
    BooleanValue(b) -> json.bool(b)
    NullValue -> json.null()
    ArrayValue(items) -> json.array(items, value_to_json)
    ObjectValue(fields) -> 
      json.object(
        fields
        |> list.map(fn(pair) {
          let #(key, val) = pair
          #(key, value_to_json(val))
        })
      )
  }
}

/// Convert form values dictionary to JSON object.
fn values_to_json(values: dict.Dict(String, Value)) -> json.Json {
  values
  |> dict.to_list()
  |> list.map(fn(pair) {
    let #(key, val) = pair
    #(key, value_to_json(val))
  })
  |> json.object()
}

/// Emit a custom event when the form is submitted.
fn emit_submit_event(form_model: FormModel, url: String, method: String) -> Effect(Msg) {
  event.emit("formosh-submit", json.object([
    #("values", values_to_json(form_model.values)),
    #("url", json.string(url)),
    #("method", json.string(method)),
    #("isValid", json.bool(form_model.is_valid)),
  ]))
}

/// Emit a custom event when the form changes.
fn emit_change_event(form_model: FormModel) -> Effect(Msg) {
  event.emit("formosh-change", json.object([
    #("values", values_to_json(form_model.values)),
    #("isValid", json.bool(form_model.is_valid)),
    #("isDirty", json.bool(form_model.is_dirty)),
  ]))
}