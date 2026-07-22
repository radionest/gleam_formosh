// Reusable form component for Formosh
// This module provides a Lustre component that can be embedded in applications
// with configurable submission endpoint and other properties.

import formosh/form/defaults
import formosh/form/json_utils
import formosh/form/model.{
  type FormModel, type FormMsg, FormModel, FormSubmit, FormSubmitted, HttpSubmit,
  init_with_full_config,
}
import formosh/form/update.{validate_all_fields}
import formosh/form/view
import formosh/schema/parser
import formosh/schema/serializer
import formosh/schema/types.{type JsonSchema, type Value}
import formosh/schema/ui_parser
import formosh/schema/ui_schema.{type UiSchema, empty_ui_schema}
import formosh/validation/cross_validator.{type Validator}
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/io
import gleam/json
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
      // Listen for show-readonly-fields changes
      component.on_attribute_change("show-readonly-fields", fn(value) {
        Ok(ShowReadonlyFieldsChanged(value == "true"))
      }),
      // Listen for read-only (review) mode toggle
      component.on_attribute_change("read-only", fn(value) {
        Ok(ReadOnlyChanged(value == "true"))
      }),
      // Listen for upload-base-url changes
      component.on_attribute_change("upload-base-url", fn(value) {
        Ok(UploadBaseUrlChanged(value))
      }),
      // Listen for ui-schema changes (JSON string)
      component.on_attribute_change("ui-schema", fn(value) {
        case ui_parser.parse(value) {
          Ok(ui) -> Ok(UiSchemaChanged(ui))
          Error(error) -> {
            io.println_error(
              "formosh: ui-schema parse error: " <> string.inspect(error),
            )
            Error(Nil)
          }
        }
      }),
      // Listen for `validator` JS property — embedder sets
      // `element.validator = (values) => [...]` on the DOM node.
      component.on_property_change(
        "validator",
        decode.map(decode.dynamic, ValidatorChanged),
      ),
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

/// Set initial values for the form as a JSON string.
pub fn initial_values_string(json: String) -> Attribute(msg) {
  attribute.attribute("initial-values", json)
}

/// Control visibility of readOnly fields (default: True).
///
/// When True, fields with `readOnly: true` in the schema are rendered
/// as disabled inputs. When False, they are hidden entirely.
pub fn show_readonly_fields(show: Bool) -> Attribute(msg) {
  attribute.attribute("show-readonly-fields", case show {
    True -> "true"
    False -> "false"
  })
}

/// Render the form as a static, read-only summary (label → value) instead
/// of editable inputs. Submit/Reset controls are hidden. Pair with
/// `schema_string` + `initial_values_string` to display stored values.
pub fn read_only(value: Bool) -> Attribute(msg) {
  attribute.attribute("read-only", case value {
    True -> "true"
    False -> "false"
  })
}

/// Set the base URL for file uploads.
///
/// Files are uploaded via POST to this URL with multipart/form-data.
/// Delete requests use DELETE {url}/{filename}.
pub fn upload_base_url(url: String) -> Attribute(msg) {
  attribute.attribute("upload-base-url", url)
}

/// Set the UiSchema as a JSON string attribute.
///
/// UiSchema separates presentation hints (widgets, order, placeholder,
/// help text, etc.) from the JSON Schema data definition. See
/// `formosh/schema/ui_schema` for the supported `ui:*` fields.
pub fn ui_schema_string(json: String) -> Attribute(msg) {
  attribute.attribute("ui-schema", json)
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
    // Initial values to populate the form with
    initial_values: dict.Dict(String, Value),
    // Whether to show readOnly fields (True) or hide them (False)
    show_readonly_fields: Bool,
    // Render the whole form as a static read-only summary (review mode)
    read_only: Bool,
    // Base URL for file uploads
    upload_base_url: Option(String),
    // Parsed UiSchema (presentation hints parallel to `schema`)
    ui_schema: UiSchema,
    // Optional cross-field validator received via the `validator` JS property
    validator: Option(Validator(FormModel)),
  )
}

fn init(_flags) -> #(Model, Effect(Msg)) {
  #(
    Model(
      form_model: None,
      submit_url: None,
      submit_method: "POST",
      initial_values: dict.new(),
      show_readonly_fields: True,
      read_only: False,
      upload_base_url: None,
      ui_schema: empty_ui_schema(),
      validator: None,
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
  InitialValuesChanged(dict.Dict(String, Value))
  ShowReadonlyFieldsChanged(Bool)
  ReadOnlyChanged(Bool)
  UploadBaseUrlChanged(String)
  UiSchemaChanged(UiSchema)
  ValidatorChanged(Dynamic)

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

  // Initialize form with the schema, submit config, initial values, and ui_schema
  let form_model =
    init_with_full_config(
      schema,
      submit_config,
      model.show_readonly_fields,
      model.initial_values,
      model.ui_schema,
    )
  // Resolve union branches then conditional schema (if/then/else) based on
  // initial values, then top up arrays revealed by those values (a single
  // pass: appending rows can never flip a condition — the matcher compares
  // scalars).
  let resolved_schema =
    model.recompute_resolved_schema(
      schema,
      form_model.values,
      form_model.selected_branches,
    )
  let reconciled_values =
    defaults.ensure_min_items(
      resolved_schema.properties,
      form_model.values,
      form_model.selected_branches,
    )
  let form_model_resolved =
    FormModel(
      ..form_model,
      values: reconciled_values,
      resolved_schema: resolved_schema,
      upload_base_url: model.upload_base_url,
      validator: model.validator,
      read_only: model.read_only,
    )
  // Validate the form initially to check required fields
  let validated_form = validate_all_fields(form_model_resolved)
  Model(..model, form_model: Some(validated_form))
}

/// Diagnostic warn for a form that (re)initialised into the "blocked only by
/// hidden errors" state (see `update.warn_only_hidden_blocks_effect`). The
/// submit button is disabled from the first render in that state, so
/// `FormSubmit` never fires — the warn has to be emitted here, where the
/// fresh `validate_all_fields` of `reinitialize_form_with_schema` just ran,
/// rather than from the submit handler.
fn hidden_blocks_warn(model: Model) -> Effect(Msg) {
  case model.form_model {
    Some(form_model) -> update.warn_only_hidden_blocks_effect(form_model)
    None -> effect.none()
  }
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    SchemaChanged(schema) -> {
      // Store the schema but reinitialize the form with current config
      let new_model = reinitialize_form_with_schema(model, schema)
      #(
        new_model,
        effect.batch([
          // Emit a ready event to notify parent
          event.emit(
            "formosh-ready",
            json.object([
              #("schema", json.string("loaded")),
            ]),
          ),
          // Diagnose a form that loaded already blocked by hidden-field errors.
          hidden_blocks_warn(new_model),
        ]),
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

    InitialValuesChanged(values) -> {
      let new_model = Model(..model, initial_values: values)
      // If schema already loaded, reinitialize with new initial values
      let final_model = case new_model.form_model {
        Some(form_model) ->
          reinitialize_form_with_schema(new_model, form_model.schema)
        None -> new_model
      }
      // New initial values can introduce or clear hidden-field errors.
      #(final_model, hidden_blocks_warn(final_model))
    }

    ShowReadonlyFieldsChanged(show) -> {
      let new_model = Model(..model, show_readonly_fields: show)
      let final_model = case new_model.form_model {
        Some(form_model) ->
          reinitialize_form_with_schema(new_model, form_model.schema)
        None -> new_model
      }
      // Toggling show=false can newly suppress a readOnly required field.
      #(final_model, hidden_blocks_warn(final_model))
    }

    ReadOnlyChanged(read_only) -> {
      // Presentation-only toggle: patch the flag in place (like
      // `UiSchemaChanged`) so current values and validation state survive,
      // rather than reinitialising the form from defaults.
      let new_model = Model(..model, read_only: read_only)
      let final_model = case new_model.form_model {
        Some(form_model) ->
          Model(
            ..new_model,
            form_model: Some(FormModel(..form_model, read_only: read_only)),
          )
        None -> new_model
      }
      #(final_model, effect.none())
    }

    UploadBaseUrlChanged(url) -> {
      let new_model = Model(..model, upload_base_url: Some(url))
      // Update existing form model if present
      let final_model = case new_model.form_model {
        Some(form_model) ->
          Model(
            ..new_model,
            form_model: Some(
              FormModel(..form_model, upload_base_url: Some(url)),
            ),
          )
        None -> new_model
      }
      #(final_model, effect.none())
    }

    UiSchemaChanged(ui) -> {
      let new_model = Model(..model, ui_schema: ui)
      // UiSchema is presentation-only — applying it in-place keeps the
      // current form values and validation state. Renderers re-resolve
      // hints from `FormModel.ui_schema` on every render.
      let final_model = case new_model.form_model {
        Some(form_model) ->
          Model(
            ..new_model,
            form_model: Some(FormModel(..form_model, ui_schema: ui)),
          )
        None -> new_model
      }
      #(final_model, effect.none())
    }

    ValidatorChanged(js_fn) -> {
      let v = cross_validator.from_js(js_fn)
      let new_model = Model(..model, validator: Some(v))
      // If the form is already initialised, patch the validator in place
      // and re-run validation so cross-field errors appear immediately.
      let final_model = case new_model.form_model {
        Some(form_model) -> {
          let patched = FormModel(..form_model, validator: Some(v))
          Model(..new_model, form_model: Some(validate_all_fields(patched)))
        }
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

          // When used as a web component, submission results are communicated
          // to the parent via emitted events — clear submission_result to avoid
          // rendering the raw server response inside the component's own view.
          let final_form = case form_msg {
            FormSubmitted(_) ->
              FormModel(..updated_form, submission_result: None)
            _ -> updated_form
          }

          #(
            Model(..model, form_model: Some(final_form)),
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
          attribute.class("formosh-loading"),
          attribute.attribute("part", "loading"),
        ],
        [
          element.text("Waiting for schema..."),
        ],
      )
    }
  }
}

// EFFECTS ---------------------------------------------------------------------

/// Convert the form values tree to JSON object.
fn values_to_json(values: Value) -> json.Json {
  json_utils.value_to_json(values)
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
      #("values", values_to_json(model.get_resolved_values(form_model))),
      #("isValid", json.bool(form_model.is_valid)),
      #("isDirty", json.bool(form_model.is_dirty)),
    ]),
  )
}
