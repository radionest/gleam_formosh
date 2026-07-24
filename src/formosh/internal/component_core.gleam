// Web-component MVU core (Model, Msg, init, update, view) for the Formosh
// form web component. Extracted from `formosh/component` so same-package
// tests can exercise it directly; `formosh/component` wires this core into
// the registered custom element.

import formosh/form/defaults
import formosh/form/json_utils
import formosh/form/model.{
  type FormModel, type FormMsg, FormModel, FormSubmit, FormSubmitted, HttpSubmit,
  init_with_full_config,
}
import formosh/form/update.{validate_all_fields}
import formosh/form/view
import formosh/schema/parser
import formosh/schema/types.{type JsonSchema, type Value}
import formosh/schema/ui_parser
import formosh/schema/ui_schema.{type UiSchema, empty_ui_schema}
import formosh/validation/cross_validator.{type Validator}
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/io
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/event

// MODEL -----------------------------------------------------------------------

/// Component-specific model that wraps the form model.
pub type Model {
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

pub fn init(_flags) -> #(Model, Effect(Msg)) {
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
pub type Msg {
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

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
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

// ATTRIBUTE PARSERS -------------------------------------------------------------

/// Parse the `schema` attribute (JSON Schema string) into a `SchemaChanged`
/// message. Logs a diagnostic and returns `Error(Nil)` on invalid input, per
/// `lustre/component.on_attribute_change`'s contract.
pub fn parse_schema_attr(value: String) -> Result(Msg, Nil) {
  case parser.parse_schema(value) {
    Ok(schema) -> Ok(SchemaChanged(schema))
    Error(error) -> {
      io.println_error("formosh: schema parse error: " <> string.inspect(error))
      Error(Nil)
    }
  }
}

/// Parse the `initial-values` attribute (JSON object string) into an
/// `InitialValuesChanged` message.
pub fn parse_initial_values_attr(value: String) -> Result(Msg, Nil) {
  case json_utils.json_string_to_values(value) {
    Ok(values) -> Ok(InitialValuesChanged(values))
    Error(_) -> {
      io.println_error("formosh: initial-values parse error")
      Error(Nil)
    }
  }
}

/// Parse the `ui-schema` attribute (JSON string) into a `UiSchemaChanged`
/// message.
pub fn parse_ui_schema_attr(value: String) -> Result(Msg, Nil) {
  case ui_parser.parse(value) {
    Ok(ui) -> Ok(UiSchemaChanged(ui))
    Error(error) -> {
      io.println_error(
        "formosh: ui-schema parse error: " <> string.inspect(error),
      )
      Error(Nil)
    }
  }
}

/// Parse a boolean-flag attribute (`show-readonly-fields`, `read-only`).
/// Strict: only the exact string `"true"` is truthy.
pub fn parse_bool_attr(value: String) -> Bool {
  value == "true"
}

// VIEW ------------------------------------------------------------------------

pub fn view(model: Model) -> Element(Msg) {
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

/// Build the JSON payload for a submission result event.
pub fn submit_result_payload(result: Result(String, String)) -> json.Json {
  case result {
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
}

/// Build the JSON payload for a form-change event.
pub fn change_event_payload(form_model: FormModel) -> json.Json {
  json.object([
    #("values", json_utils.value_to_json(model.get_resolved_values(form_model))),
    #("isValid", json.bool(form_model.is_valid)),
    #("isDirty", json.bool(form_model.is_dirty)),
  ])
}

/// Emit the submission result to parent component.
fn emit_submit_result(result: Result(String, String)) -> Effect(Msg) {
  event.emit("formosh-submit", submit_result_payload(result))
}

/// Emit a custom event when the form changes.
fn emit_change_event(form_model: FormModel) -> Effect(Msg) {
  event.emit("formosh-change", change_event_payload(form_model))
}
