// Reusable form component for Formosh
// This module provides a Lustre component that can be embedded in applications
// with configurable submission endpoint and other properties.

import form/model.{type FormModel, type FormMsg}
import form/update
import form/view
import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/result
import lustre
import lustre/attribute.{type Attribute}
import lustre/component
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/event
import schema/parser
import schema/types.{type JsonSchema}

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
          Error(_) -> Error([])
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
      // Listen for schema property changes (for structured data)
      component.on_property_change("schema", {
        decode.dynamic
        |> decode.map(fn(dynamic_value) {
          // Try to parse the dynamic value as a JSON schema
          case parser.parse_schema_from_dynamic(dynamic_value) {
            Ok(schema) -> SchemaChanged(schema)
            Error(_) -> NoOp
          }
        })
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
pub fn schema(schema: JsonSchema) -> Attribute(msg) {
  // Convert the schema to a JSON string for the attribute
  let json_string = schema_to_json_string(schema)
  attribute.attribute("schema", json_string)
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
pub fn on_submit(handler: fn(json.Json) -> msg) -> Attribute(msg) {
  event.on("formosh-submit", {
    decode.at(["detail"], decode.dynamic)
    |> decode.map(fn(data) {
      // Convert the dynamic data to JSON
      handler(json.object([]))  // Simplified for now
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
pub fn on_change(handler: fn(json.Json) -> msg) -> Attribute(msg) {
  event.on("formosh-change", {
    decode.at(["detail"], decode.dynamic)
    |> decode.map(fn(data) {
      handler(json.object([]))  // Simplified for now
    })
  })
}

// MODEL -----------------------------------------------------------------------

/// Component-specific model that wraps the form model with additional state.
type Model {
  Model(
    // The core form model
    form_model: Option(FormModel),
    // Component configuration
    submit_url: Option(String),
    submit_method: String,
    css_prefix: String,
    // Component state
    is_loading: Bool,
    error_message: Option(String),
  )
}

fn init(_flags) -> #(Model, Effect(Msg)) {
  #(
    Model(
      form_model: None,
      submit_url: None,
      submit_method: "POST",
      css_prefix: "formosh",
      is_loading: False,
      error_message: None,
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
  
  // Component events
  ComponentSubmit
  SubmissionComplete(Result(String, String))
  
  // No-op for failed parsing
  NoOp
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    SchemaChanged(schema) -> {
      // Initialize a new form model with the schema
      let form_model = model.init(schema)
      #(
        Model(..model, form_model: Some(form_model)),
        // Emit a change event to notify parent
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
          // Handle form submission specially
          case form_msg {
            model.FormSubmit -> {
              // Intercept form submission to use component's submit URL
              case model.submit_url {
                Some(url) -> {
                  // Validate the form first
                  let #(updated_form, validation_effect) = 
                    update.update(form_model, model.ValidateForm)
                  
                  // If valid, submit with our URL
                  case model.can_submit(updated_form) {
                    True -> {
                      #(
                        Model(
                          ..model,
                          form_model: Some(model.FormModel(
                            ..updated_form,
                            is_submitting: True,
                          )),
                          is_loading: True,
                        ),
                        effect.batch([
                          validation_effect |> effect.map(FormMessage),
                          submit_to_url(updated_form, url, model.submit_method),
                        ]),
                      )
                    }
                    False -> {
                      #(
                        Model(..model, form_model: Some(updated_form)),
                        validation_effect |> effect.map(FormMessage),
                      )
                    }
                  }
                }
                None -> {
                  // No submit URL, just emit an event with the form data
                  let #(updated_form, form_effect) = 
                    update.update(form_model, form_msg)
                  #(
                    Model(..model, form_model: Some(updated_form)),
                    effect.batch([
                      form_effect |> effect.map(FormMessage),
                      emit_submit_event(updated_form),
                    ]),
                  )
                }
              }
            }
            
            _ -> {
              // Regular form message handling
              let #(updated_form, form_effect) = 
                update.update(form_model, form_msg)
              
              #(
                Model(..model, form_model: Some(updated_form)),
                effect.batch([
                  form_effect |> effect.map(FormMessage),
                  emit_change_event(updated_form),
                ]),
              )
            }
          }
        }
        
        None -> {
          // No schema loaded yet
          #(model, effect.none())
        }
      }
    }
    
    ComponentSubmit -> {
      // Delegate to form submit
      update(model, FormMessage(model.FormSubmit))
    }
    
    SubmissionComplete(result) -> {
      case model.form_model {
        Some(form_model) -> {
          let updated_form = case result {
            Ok(message) -> {
              model.FormModel(
                ..form_model,
                is_submitting: False,
                submission_result: Some(model.SubmissionSuccess(message)),
              )
            }
            Error(error) -> {
              model.FormModel(
                ..form_model,
                is_submitting: False,
                submission_result: Some(model.SubmissionError(error)),
              )
            }
          }
          
          #(
            Model(
              ..model,
              form_model: Some(updated_form),
              is_loading: False,
              error_message: case result {
                Ok(_) -> None
                Error(err) -> Some(err)
              },
            ),
            // Emit completion event
            event.emit("formosh-submit-complete", case result {
              Ok(msg) -> json.object([
                #("success", json.bool(True)),
                #("message", json.string(msg)),
              ])
              Error(err) -> json.object([
                #("success", json.bool(False)),
                #("error", json.string(err)),
              ])
            }),
          )
        }
        
        None -> #(model, effect.none())
      }
    }
    
    NoOp -> #(model, effect.none())
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

/// Submit form data to the configured URL.
fn submit_to_url(
  form_model: FormModel,
  url: String,
  method: String,
) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    // In a real implementation, this would:
    // 1. Serialize form values to JSON
    // 2. Make an HTTP request using a library like lustre_http
    // 3. Handle the response
    
    // For now, simulate the submission
    dispatch(SubmissionComplete(Ok("Form submitted to " <> url)))
    
    Nil
  })
}

/// Emit a custom event when the form is submitted.
fn emit_submit_event(form_model: FormModel) -> Effect(Msg) {
  // Convert form values to JSON
  let form_data = form_values_to_json(form_model.values)
  
  event.emit("formosh-submit", form_data)
}

/// Emit a custom event when the form changes.
fn emit_change_event(form_model: FormModel) -> Effect(Msg) {
  let form_data = form_values_to_json(form_model.values)
  
  event.emit("formosh-change", json.object([
    #("values", form_data),
    #("isValid", json.bool(form_model.is_valid)),
    #("isDirty", json.bool(form_model.is_dirty)),
  ]))
}

// HELPERS ---------------------------------------------------------------------

/// Helper to check if form can be submitted.
fn can_submit(model: FormModel) -> Bool {
  model.is_valid && !model.is_submitting
}

/// Convert form values to JSON for events.
fn form_values_to_json(values: model.Dict(String, types.FieldValue)) -> json.Json {
  // Simplified conversion - in real implementation would handle all field types
  json.object([])
}

/// Convert a JsonSchema to a JSON string.
fn schema_to_json_string(schema: JsonSchema) -> String {
  // Simplified - would need proper JSON serialization
  "{}"
}