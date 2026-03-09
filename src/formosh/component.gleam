// Reusable form component for Formosh
// This module provides a Lustre component that can be embedded in applications
// with configurable submission endpoint and other properties.

import formosh/form/json_utils
import formosh/form/model.{
  type FormModel, type FormMsg, FormModel, FormSubmit, FormSubmitted, HttpSubmit,
  init_with_full_config,
}
import formosh/form/update.{validate_all_fields}
import formosh/form/view
import formosh/schema/conditional_resolver
import formosh/schema/parser
import formosh/schema/serializer
import formosh/schema/types.{type JsonSchema, type Value}
import gleam/dict
import gleam/dynamic/decode
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre
import lustre/attribute.{type Attribute}
import lustre/component
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/event

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
          Error(error) -> {
            io.println_error(
              "formosh: schema parse error: " <> string.inspect(error),
            )
            Error(Nil)
          }
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
      // Listen for initial values changes (JSON string)
      component.on_attribute_change("initial-values", fn(value) {
        case json_utils.json_string_to_values(value) {
          Ok(values) -> Ok(InitialValuesChanged(values))
          Error(_) -> {
            io.println_error("formosh: initial-values parse error")
            Error(Nil)
          }
        }
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
  let json_obj = serializer.schema_to_json(schema)
  let json_string = json.to_string(json_obj)
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

/// Set initial values for the form as a JSON string.
pub fn initial_values_string(json: String) -> Attribute(msg) {
  attribute.attribute("initial-values", json)
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
    // Initial values to populate the form with
    initial_values: dict.Dict(String, Value),
  )
}

fn init(_flags) -> #(Model, Effect(Msg)) {
  #(
    Model(
      form_model: None,
      submit_url: None,
      submit_method: "POST",
      css_prefix: "formosh",
      initial_values: dict.new(),
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
  InitialValuesChanged(dict.Dict(String, Value))

  // Form messages (wrapped)
  FormMessage(FormMsg)

  // HTTP submission result
  SubmissionResponse(Result(String, String))
}

/// Helper function to reinitialize form with current configuration
fn reinitialize_form_with_schema(model: Model, schema: JsonSchema) -> Model {
  // Create submit config if URL is present
  let submit_config = case model.submit_url {
    Some(url) ->
      Some(
        HttpSubmit(url, model.submit_method, [
          #("Content-Type", "application/json"),
        ]),
      )
    None -> None
  }

  // Initialize form with the schema, submit config, and initial values
  let form_model =
    init_with_full_config(schema, submit_config, False, model.initial_values)
  // Resolve conditional schema (if/then/else) based on initial values
  let resolved_schema =
    conditional_resolver.resolve_conditional_schema(schema, form_model.values)
  let form_model_resolved =
    FormModel(..form_model, resolved_schema: resolved_schema)
  // Validate the form initially to check required fields
  let validated_form = validate_all_fields(form_model_resolved)
  Model(..model, form_model: Some(validated_form))
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    SchemaChanged(schema) -> {
      // Store the schema but reinitialize the form with current config
      let new_model = reinitialize_form_with_schema(model, schema)
      #(
        new_model,
        // Emit a ready event to notify parent
        event.emit(
          "formosh-ready",
          json.object([
            #("schema", json.string("loaded")),
          ]),
        ),
      )
    }

    SubmitUrlChanged(url) -> {
      // Update the submit URL and reinitialize form if schema exists
      let new_model = Model(..model, submit_url: Some(url))
      let final_model = case new_model.form_model {
        Some(form_model) -> {
          // Reinitialize with the new submit config
          case form_model.schema {
            schema -> reinitialize_form_with_schema(new_model, schema)
          }
        }
        None -> new_model
      }
      #(final_model, effect.none())
    }

    SubmitMethodChanged(method) -> {
      // Update the submit method and reinitialize form if both schema and URL exist
      let new_model = Model(..model, submit_method: method)
      let final_model = case new_model {
        Model(form_model: Some(form_model), submit_url: Some(_), ..) -> {
          reinitialize_form_with_schema(new_model, form_model.schema)
        }
        _ -> new_model
      }
      #(final_model, effect.none())
    }

    CssPrefixChanged(prefix) -> {
      #(Model(..model, css_prefix: prefix), effect.none())
    }

    InitialValuesChanged(values) -> {
      let new_model = Model(..model, initial_values: values)
      // If schema already loaded, reinitialize with new initial values
      let final_model = case new_model.form_model {
        Some(form_model) ->
          reinitialize_form_with_schema(new_model, form_model.schema)
        None -> new_model
      }
      #(final_model, effect.none())
    }

    FormMessage(form_msg) -> {
      case model.form_model {
        Some(form_model) -> {
          // Handle form messages
          let #(updated_form, form_effect) = update.update(form_model, form_msg)

          // Handle form events
          let event_effect = case form_msg {
            FormSubmit -> {
              // Form will handle the submission internally
              // Just emit a submitting event
              event.emit(
                "formosh-submitting",
                json.object([
                  #("status", json.string("submitting")),
                ]),
              )
            }
            FormSubmitted(result) -> {
              // Form submitted, emit result
              case result {
                Ok(message) -> emit_submit_result(Ok(message))
                Error(error) -> emit_submit_result(Error(error))
              }
            }
            _ -> emit_change_event(updated_form)
          }

          #(
            Model(..model, form_model: Some(updated_form)),
            effect.batch([
              form_effect |> effect.map(FormMessage),
              event_effect,
            ]),
          )
        }

        None -> {
          // No schema loaded yet
          #(model, effect.none())
        }
      }
    }

    SubmissionResponse(result) -> {
      // Emit the result to parent component
      #(model, emit_submit_result(result))
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
      element.element(
        "div",
        [
          attribute.class(model.css_prefix <> "-loading"),
        ],
        [
          element.text("Waiting for schema..."),
        ],
      )
    }
  }
}

// EFFECTS ---------------------------------------------------------------------

/// Convert form values dictionary to JSON object.
fn values_to_json(values: dict.Dict(String, Value)) -> json.Json {
  values
  |> dict.to_list()
  |> list.map(fn(pair) {
    let #(key, val) = pair
    #(key, json_utils.value_to_json(val))
  })
  |> json.object()
}

/// Emit the submission result to parent component.
fn emit_submit_result(result: Result(String, String)) -> Effect(Msg) {
  // Convert Result to JSON for event emission
  let json_result = case result {
    Ok(body) ->
      json.object([
        #("status", json.string("success")),
        #("data", json.string(body)),
      ])
    Error(message) ->
      json.object([
        #("status", json.string("error")),
        #("error", json.string(message)),
      ])
  }

  event.emit("formosh-submit", json_result)
}

/// Emit a custom event when the form changes.
fn emit_change_event(form_model: FormModel) -> Effect(Msg) {
  event.emit(
    "formosh-change",
    json.object([
      #("values", values_to_json(form_model.values)),
      #("isValid", json.bool(form_model.is_valid)),
      #("isDirty", json.bool(form_model.is_dirty)),
    ]),
  )
}
