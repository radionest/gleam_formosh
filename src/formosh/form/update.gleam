// Update functions for form MVU

import formosh/ffi/image_upload as image_upload_ffi
import formosh/form/json_utils
import formosh/form/model.{
  type FormModel, type FormMsg, AddArrayItemPath, CustomSubmit, FileUploadError,
  FileUploading, FormSubmit, FormSubmitted, HttpSubmit, ImageRemoved,
  ImageUploadCompleted, ImageUploadFailed, ImageUploadRequested,
  ImageUploadStarted, NoSubmit, RemoveArrayItemPath, ResetForm, SubmissionError,
  SubmissionSuccess, UpdateFieldPath, ValidateForm,
}
import formosh/form/path
import formosh/schema/conditional_resolver
import formosh/schema/types.{type Value}
import formosh/schema/validator
import formosh/validation/field_requirements
import gleam/dict
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
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

    ImageUploadRequested(field_path) -> {
      let upload_effect = create_upload_effect(model, field_path)
      #(model, upload_effect)
    }

    ImageUploadStarted(field_path, temp_id, preview_url) -> {
      let path_key = path.to_string(field_path)
      let current =
        dict.get(model.upload_states, path_key)
        |> option.from_result()
        |> option.unwrap([])
      let new_states =
        dict.insert(
          model.upload_states,
          path_key,
          list.append(current, [FileUploading(temp_id, preview_url)]),
        )
      #(model.FormModel(..model, upload_states: new_states), effect.none())
    }

    ImageUploadCompleted(field_path, temp_id, server_url) -> {
      // Remove from upload_states
      let path_key = path.to_string(field_path)
      let new_states =
        remove_upload_state(model.upload_states, path_key, temp_id)

      // Revoke the blob preview URL
      let preview_url = get_preview_url(model.upload_states, path_key, temp_id)
      let _ = case preview_url {
        Some(url) -> image_upload_ffi.revoke_object_url(url)
        None -> Nil
      }

      // Add server_url to the array value
      let root_value = model_to_root_value(model)
      let current_array = case path.get_at_path(root_value, field_path) {
        Some(types.ArrayValue(items)) -> items
        _ -> []
      }
      let updated_array =
        list.append(current_array, [types.StringValue(server_url)])
      let updated_root =
        path.set_at_path(
          root_value,
          field_path,
          types.ArrayValue(updated_array),
        )
      let new_values = root_value_to_model_values(updated_root)

      let new_model =
        model.FormModel(
          ..model,
          values: new_values,
          upload_states: new_states,
          is_dirty: True,
        )
      let validated_model = validate_all_fields(new_model)
      #(validated_model, effect.none())
    }

    ImageUploadFailed(field_path, temp_id, error) -> {
      let path_key = path.to_string(field_path)

      // Revoke the blob preview URL if it exists
      let preview_url = get_preview_url(model.upload_states, path_key, temp_id)
      let _ = case preview_url {
        Some(url) -> image_upload_ffi.revoke_object_url(url)
        None -> Nil
      }

      // Replace FileUploading with FileUploadError
      let current =
        dict.get(model.upload_states, path_key)
        |> option.from_result()
        |> option.unwrap([])
      let updated =
        list.map(current, fn(state) {
          case state {
            FileUploading(id, _) if id == temp_id ->
              FileUploadError(temp_id, error)
            other -> other
          }
        })
      let new_states = dict.insert(model.upload_states, path_key, updated)
      #(model.FormModel(..model, upload_states: new_states), effect.none())
    }

    ImageRemoved(field_path, server_url) -> {
      // Remove URL from array value
      let root_value = model_to_root_value(model)
      let current_array = case path.get_at_path(root_value, field_path) {
        Some(types.ArrayValue(items)) -> items
        _ -> []
      }
      let updated_array =
        list.filter(current_array, fn(item) {
          item != types.StringValue(server_url)
        })
      let updated_root =
        path.set_at_path(
          root_value,
          field_path,
          types.ArrayValue(updated_array),
        )
      let new_values = root_value_to_model_values(updated_root)

      // Send DELETE request via FFI
      let delete_effect = case model.upload_base_url {
        Some(base_url) -> {
          let filename = extract_filename(server_url)
          effect.from(fn(_dispatch) {
            image_upload_ffi.delete_file(base_url, filename)
          })
        }
        None -> effect.none()
      }

      let new_model =
        model.FormModel(..model, values: new_values, is_dirty: True)
      let validated_model = validate_all_fields(new_model)
      #(validated_model, delete_effect)
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
  case dict.get(model.resolved_schema.properties, field_name) {
    Ok(property) -> {
      let value = model.get_field_value(model, field_name)
      let errors =
        validator.validate_field(
          field_name,
          value,
          property,
          field_requirements.is_required(model.resolved_schema, field_name),
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
/// Runs validation in two passes:
///   1. Top-level fields against `resolved_schema.properties`.
///   2. Each row of every array field against its `items` schema, with
///      item-level conditionals (`if/then/else`, `allOf`) re-evaluated
///      per row.
///
/// Errors for array-item fields are keyed under a path-style name
/// (`<array>.<index>.<field>`) so they don't collide with top-level keys.
///
/// ## Parameters
/// - `model`: The current form model
///
/// ## Returns
/// A new FormModel with validation errors for all invalid fields
pub fn validate_all_fields(model: FormModel) -> FormModel {
  let after_top =
    dict.keys(model.resolved_schema.properties)
    |> list.fold(model.clear_all_errors(model), validate_field)

  dict.to_list(after_top.resolved_schema.properties)
  |> list.fold(after_top, fn(acc, entry) {
    let #(array_name, property) = entry
    case property.field_type, property.items {
      Some(types.ArrayType), Some(item_schema) ->
        case dict.get(acc.values, array_name) {
          Ok(array_value) -> {
            let errors =
              validator.validate_array_items(
                array_name,
                item_schema,
                array_value,
              )
            list.fold(errors, acc, fn(m, err) {
              model.add_field_error(m, err.field, err)
            })
          }
          Error(_) -> acc
        }
      _, _ -> acc
    }
  })
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
      let json_data = values_to_json(model.get_resolved_values(model))
      // Make HTTP request based on method
      case method {
        "POST" ->
          rsvp.post(
            url,
            json_data,
            rsvp.expect_any_response(handle_http_response),
          )
        "PUT" ->
          rsvp.put(
            url,
            json_data,
            rsvp.expect_any_response(handle_http_response),
          )
        "PATCH" ->
          rsvp.patch(
            url,
            json_data,
            rsvp.expect_any_response(handle_http_response),
          )
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

/// Create an effect that opens the file picker and dispatches upload lifecycle messages.
fn create_upload_effect(
  model: FormModel,
  field_path: path.FieldPath,
) -> Effect(FormMsg) {
  case model.upload_base_url {
    None -> effect.none()
    Some(upload_url) -> {
      // Look up the property to get upload config
      let first_segment = case field_path {
        [path.PropertySegment(name), ..] -> Some(name)
        _ -> None
      }
      let config = case first_segment {
        Some(name) ->
          case dict.get(model.resolved_schema.properties, name) {
            Ok(prop) -> prop.upload_config
            Error(_) -> None
          }
        None -> None
      }
      let accept = case config {
        Some(c) -> c.accept
        None -> "image/*"
      }
      let max_file_size = case config {
        Some(types.UploadConfig(_, Some(size))) -> size
        _ -> 0
      }
      effect.from(fn(dispatch) {
        image_upload_ffi.open_file_picker(
          accept,
          max_file_size,
          upload_url,
          fn(temp_id, preview_url) {
            dispatch(ImageUploadStarted(field_path, temp_id, preview_url))
            Nil
          },
          fn(temp_id, server_url) {
            dispatch(ImageUploadCompleted(field_path, temp_id, server_url))
            Nil
          },
          fn(temp_id, error) {
            dispatch(ImageUploadFailed(field_path, temp_id, error))
            Nil
          },
        )
      })
    }
  }
}

/// Remove an upload state entry by temp_id.
fn remove_upload_state(
  states: dict.Dict(String, List(model.FileUploadState)),
  path_key: String,
  temp_id: String,
) -> dict.Dict(String, List(model.FileUploadState)) {
  case dict.get(states, path_key) {
    Ok(current) -> {
      let filtered =
        list.filter(current, fn(state) {
          case state {
            FileUploading(id, _) | FileUploadError(id, _) -> id != temp_id
          }
        })
      dict.insert(states, path_key, filtered)
    }
    Error(_) -> states
  }
}

/// Get the preview URL for a given temp_id from upload states.
fn get_preview_url(
  states: dict.Dict(String, List(model.FileUploadState)),
  path_key: String,
  temp_id: String,
) -> option.Option(String) {
  case dict.get(states, path_key) {
    Ok(current) ->
      list.find_map(current, fn(state) {
        case state {
          FileUploading(id, url) if id == temp_id -> Ok(url)
          _ -> Error(Nil)
        }
      })
      |> option.from_result()
    Error(_) -> None
  }
}

/// Extract filename from a URL path (last segment after "/").
fn extract_filename(url: String) -> String {
  url
  |> string.split("/")
  |> list.last()
  |> option.from_result()
  |> option.unwrap(url)
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
