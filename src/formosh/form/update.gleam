// Update functions for form MVU

import formosh/form/json_utils
import formosh/form/model.{
  type FormModel, type FormMsg, AddArrayItemPath, CustomSubmit, FormSubmit,
  FormSubmitted, HttpSubmit, NoSubmit, RemoveArrayItemPath, ResetForm,
  SubmissionError, SubmissionSuccess, UpdateFieldPath, ValidateForm,
}
import formosh/form/path
import formosh/schema/conditional_resolver
import formosh/schema/types.{type Value}
import formosh/schema/validator
import formosh/validation/field_requirements
import gleam/dict
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import lustre/effect.{type Effect}
import rsvp

/// Main update function for the form MVU architecture.
/// 
/// This function handles all form-related messages and updates the form state
/// accordingly. It follows the standard Elm/Lustre update pattern, taking the
/// current model and a message, then returning a new model and optional effects.
/// 
/// ## Parameters
/// - `model`: The current form model state
/// - `msg`: The message representing the user action or system event
/// 
/// ## Returns
/// A tuple containing the new model state and any effects to execute
/// 
/// ## Supported Messages
/// - `UpdateFieldPath(path, value)`: Update field value at specific path
/// - `AddArrayItemPath(path)`: Add new item to array at path
/// - `RemoveArrayItemPath(path, index)`: Remove array item at index
/// - `FormSubmit`: Validate and submit the form
/// - `FormSubmitted(result)`: Handle submission result (internal)
/// - `SubmissionSuccess(message)`: Submission succeeded (internal)
/// - `SubmissionError(message)`: Submission failed (internal)
/// - `ValidateForm`: Validate entire form
/// - `ResetForm`: Reset form to initial state
/// Convert model values to a hierarchical Value root for path operations.
/// 
/// This helper function converts the flat dictionary of field values in the model
/// to a hierarchical Value object that can be used with path-based operations.
/// 
/// ## Parameters
/// - `model`: The form model containing the values dictionary
/// 
/// ## Returns
/// A Value (ObjectValue) representing the hierarchical form data
fn model_to_root_value(model: FormModel) -> types.Value {
  case dict.to_list(model.values) {
    [] -> types.ObjectValue([])
    values -> types.ObjectValue(values)
  }
}

/// Convert a hierarchical Value root back to model values dictionary.
/// 
/// This helper function converts the hierarchical Value object returned from
/// path operations back to the flat dictionary format used by the model.
/// 
/// ## Parameters
/// - `root_value`: The hierarchical Value to convert
/// 
/// ## Returns
/// A dictionary of field names to Values
fn root_value_to_model_values(
  root_value: types.Value,
) -> dict.Dict(String, types.Value) {
  case root_value {
    types.ObjectValue(fields) -> dict.from_list(fields)
    _ -> dict.new()
  }
}

pub fn update(model: FormModel, msg: FormMsg) -> #(FormModel, Effect(FormMsg)) {
  case msg {
    // Path-based handlers (simplified approach)
    UpdateFieldPath(path, value) -> {
      let root_value = model_to_root_value(model)
      let updated_root = path.set_at_path(root_value, path, value)
      let new_values = root_value_to_model_values(updated_root)

      // Recalculate resolved schema based on new values
      let resolved_schema =
        conditional_resolver.resolve_conditional_schema(
          model.schema,
          new_values,
        )

      let new_model =
        model.FormModel(
          ..model,
          values: new_values,
          resolved_schema: resolved_schema,
          is_dirty: True,
        )
      let validated_model = validate_all_fields(new_model)
      #(validated_model, effect.none())
    }

    AddArrayItemPath(path) -> {
      let root_value = model_to_root_value(model)
      let updated_root =
        path.add_array_item_at_path(root_value, path, types.ObjectValue([]))
      let new_values = root_value_to_model_values(updated_root)

      let new_model = model.FormModel(..model, values: new_values)
      #(new_model, effect.none())
    }

    RemoveArrayItemPath(path, index) -> {
      let root_value = model_to_root_value(model)
      let updated_root = path.remove_array_item_at_path(root_value, path, index)
      let new_values = root_value_to_model_values(updated_root)

      let new_model = model.FormModel(..model, values: new_values)
      #(new_model, effect.none())
    }

    FormSubmit -> {
      // Validate all fields before submission
      let validated_model = validate_all_fields(model)

      case model.can_submit(validated_model) {
        True -> {
          let submitting_model =
            model.FormModel(..validated_model, is_submitting: True)

          // Create submission effect
          let submit_effect = submit_form_effect(submitting_model)

          #(submitting_model, submit_effect)
        }
        False -> {
          #(validated_model, effect.none())
        }
      }
    }

    FormSubmitted(result) -> {
      case result {
        Ok(message) -> {
          let new_model =
            model.FormModel(
              ..model,
              is_submitting: False,
              submission_result: Some(SubmissionSuccess(message)),
            )
          #(new_model, effect.none())
        }
        Error(message) -> {
          let new_model =
            model.FormModel(
              ..model,
              is_submitting: False,
              submission_result: Some(SubmissionError(message)),
            )
          #(new_model, effect.none())
        }
      }
    }

    ValidateForm -> {
      let new_model = validate_all_fields(model)
      #(new_model, effect.none())
    }

    ResetForm -> {
      let new_model = model.reset(model)
      #(new_model, effect.none())
    }
  }
}

/// Validate a single field against its schema definition.
/// 
/// This function looks up the field's schema property and runs validation
/// against the current field value, updating the model with any errors found.
/// 
/// ## Parameters
/// - `model`: The current form model
/// - `field_name`: The name of the field to validate
/// 
/// ## Returns
/// A new FormModel with updated validation errors for the field
fn validate_field(model: FormModel, field_name: String) -> FormModel {
  case dict.get(model.schema.properties, field_name) {
    Ok(property) -> {
      let value = model.get_field_value(model, field_name)
      let errors =
        validator.validate_field(
          field_name,
          value,
          property,
          field_requirements.is_required(model.schema, field_name),
        )

      case errors {
        [] -> model.clear_field_errors(model, field_name)
        _ -> {
          list.fold(
            errors,
            model.clear_field_errors(model, field_name),
            fn(acc, error) { model.add_field_error(acc, field_name, error) },
          )
        }
      }
    }
    Error(_) -> model
  }
}

/// Validate all fields in the form against their schema definitions.
/// 
/// This function runs validation on every field defined in the schema,
/// typically used before form submission to ensure all data is valid.
/// 
/// ## Parameters
/// - `model`: The current form model
/// 
/// ## Returns
/// A new FormModel with validation errors for all invalid fields
pub fn validate_all_fields(model: FormModel) -> FormModel {
  dict.keys(model.schema.properties)
  |> list.fold(model.clear_all_errors(model), validate_field)
}

/// Create an effect for form submission.
/// 
/// This function creates an effect that simulates form submission.
/// In a real application, this would typically make an HTTP request
/// to submit the form data to a server.
/// 
/// ## Parameters
/// - `_model`: The form model (currently unused but available for real implementations)
/// 
/// ## Returns
/// An Effect that will dispatch a FormSubmitted message with the result
/// 
/// ## Note
/// This is currently a simulation that always succeeds. In a real application,
/// you would:
/// 1. Serialize the form data
/// 2. Make an HTTP request
/// 3. Handle success/error responses
/// 4. Dispatch appropriate FormSubmitted messages
fn submit_form_effect(model: FormModel) -> Effect(FormMsg) {
  case model.submit_config {
    Some(HttpSubmit(url, method, _headers)) -> {
      // Convert form values to JSON
      let json_data = values_to_json(model.values)
      let json_string = json.to_string(json_data)

      // Make HTTP request based on method
      case method {
        "POST" ->
          rsvp.post(
            url,
            json_data,
            rsvp.expect_any_response(handle_http_response),
          )
        "PUT" -> {
          // Use rsvp.send for PUT requests
          case request.to(url) {
            Ok(req) -> {
              let put_request =
                req
                |> request.set_method(http.Put)
                |> request.set_header("content-type", "application/json")
                |> request.set_body(json_string)

              rsvp.send(
                put_request,
                rsvp.expect_any_response(handle_http_response),
              )
            }
            Error(_) ->
              effect.from(fn(dispatch) {
                dispatch(FormSubmitted(Error("Invalid URL: " <> url)))
                Nil
              })
          }
        }
        "GET" ->
          // For GET, we would need to add query params - not implemented yet
          effect.from(fn(dispatch) {
            dispatch(FormSubmitted(Error("GET method not yet supported")))
            Nil
          })
        _ ->
          effect.from(fn(dispatch) {
            dispatch(
              FormSubmitted(Error("Unsupported HTTP method: " <> method)),
            )
            Nil
          })
      }
    }

    Some(CustomSubmit(handler)) -> {
      // Use custom handler function
      effect.from(fn(dispatch) {
        case handler(model) {
          Ok(message) -> dispatch(FormSubmitted(Ok(message)))
          Error(error) -> dispatch(FormSubmitted(Error(error)))
        }
        Nil
      })
    }

    Some(NoSubmit) | None -> {
      // No submission configured - just mark as successful
      effect.from(fn(dispatch) {
        dispatch(FormSubmitted(Ok("Form validated successfully")))
        Nil
      })
    }
  }
}

/// Handle HTTP response from form submission.
fn handle_http_response(
  result: Result(response.Response(String), rsvp.Error),
) -> FormMsg {
  case result {
    Ok(resp) -> {
      // Check status code for success
      case resp.status >= 200 && resp.status < 300 {
        True -> FormSubmitted(Ok(resp.body))
        False -> FormSubmitted(Error("Server error: " <> resp.body))
      }
    }
    Error(error) -> {
      let error_message = case error {
        rsvp.NetworkError -> "Network connection failed"
        rsvp.HttpError(resp) -> "HTTP error: " <> resp.body
        rsvp.BadUrl(url) -> "Invalid URL: " <> url
        rsvp.JsonError(_) -> "Invalid response format"
        rsvp.BadBody -> "Invalid request body format"
        rsvp.UnhandledResponse(resp) -> "Unexpected response: " <> resp.body
      }
      FormSubmitted(Error(error_message))
    }
  }
}

/// Convert form values dictionary to JSON.
fn values_to_json(values: dict.Dict(String, Value)) -> json.Json {
  values
  |> dict.to_list()
  |> list.map(fn(pair) {
    let #(key, val) = pair
    #(key, json_utils.value_to_json(val))
  })
  |> json.object()
}
