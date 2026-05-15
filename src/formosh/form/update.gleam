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
import formosh/schema/properties
import formosh/schema/types.{type Value}
import formosh/schema/validator
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
pub fn update(model: FormModel, msg: FormMsg) -> #(FormModel, Effect(FormMsg)) {
  case msg {
    // Path-based handlers — work directly against the single Value tree.
    UpdateFieldPath(field_path, value) -> {
      let new_values = path.set_at_path(model.values, field_path, value)
      let resolved_schema =
        conditional_resolver.resolve_recursive(model.schema, new_values)
      let touched_model = model.mark_field_touched(model, field_path)
      let new_model =
        model.FormModel(
          ..touched_model,
          values: new_values,
          resolved_schema: resolved_schema,
          is_dirty: True,
        )
      let validated_model = validate_all_fields(new_model)
      #(validated_model, effect.none())
    }

    AddArrayItemPath(field_path) -> {
      let new_values =
        path.add_array_item_at_path(
          model.values,
          field_path,
          types.ObjectValue([]),
        )
      let new_model =
        model.FormModel(..model, values: new_values, is_dirty: True)
      let validated_model = validate_all_fields(new_model)
      #(validated_model, effect.none())
    }

    RemoveArrayItemPath(field_path, index) -> {
      let new_values =
        path.remove_array_item_at_path(model.values, field_path, index)
      let new_touched =
        list.filter_map(model.touched_fields, fn(p) {
          case path.reindex_after_array_removal(p, field_path, index) {
            Some(new_p) -> Ok(new_p)
            None -> Error(Nil)
          }
        })
      let new_model =
        model.FormModel(
          ..model,
          values: new_values,
          touched_fields: new_touched,
          is_dirty: True,
        )
      let validated_model = validate_all_fields(new_model)
      #(validated_model, effect.none())
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

      // Append server_url to the array value
      let current_array = case path.get_at_path(model.values, field_path) {
        Some(types.ArrayValue(items)) -> items
        _ -> []
      }
      let updated_array =
        list.append(current_array, [types.StringValue(server_url)])
      let new_values =
        path.set_at_path(
          model.values,
          field_path,
          types.ArrayValue(updated_array),
        )

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
      let current_array = case path.get_at_path(model.values, field_path) {
        Some(types.ArrayValue(items)) -> items
        _ -> []
      }
      let updated_array =
        list.filter(current_array, fn(item) {
          item != types.StringValue(server_url)
        })
      let new_values =
        path.set_at_path(
          model.values,
          field_path,
          types.ArrayValue(updated_array),
        )

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
  case properties.get(model.resolved_schema.properties, field_name) {
    Some(property) -> {
      let field_path = path.from_field_name(field_name)
      let value = model.get_value_at_path(model, field_path)
      let errors =
        validator.validate_field(
          field_path,
          value,
          property,
          model.is_required_at_path(model, field_path),
        )

      case errors {
        [] -> model.clear_errors_at_path(model, field_path)
        _ -> {
          list.fold(
            errors,
            model.clear_errors_at_path(model, field_path),
            fn(acc, error) { model.add_error_at_path(acc, field_path, error) },
          )
        }
      }
    }
    None -> model
  }
}

/// Validate all fields in the form against their schema definitions.
///
/// Runs validation in two passes:
///   1. Top-level fields against `resolved_schema.properties`.
///   2. For every top-level field, recursively validate nested object/array
///      structures via `validator.validate_nested`. Item-level conditionals
///      (`if/then/else`, `allOf`) are re-evaluated per row/per object.
///
/// Errors for nested fields are keyed under a path-style name matching
/// `path.to_string` (`<parent>.[<index>].<field>` for array items,
/// `<parent>.<field>` for object properties) so they don't collide with
/// top-level keys.
///
/// ## Parameters
/// - `model`: The current form model
///
/// ## Returns
/// A new FormModel with validation errors for all invalid fields
pub fn validate_all_fields(model: FormModel) -> FormModel {
  let after_top =
    model.resolved_schema.properties
    |> list.map(fn(entry) { entry.0 })
    |> list.fold(model.clear_all_errors(model), validate_field)

  list.fold(after_top.resolved_schema.properties, after_top, fn(acc, entry) {
    let #(field_name, property) = entry
    let field_path = path.from_field_name(field_name)
    let field_value = path.get_at_path(acc.values, field_path)
    let nested_errors =
      validator.validate_nested(field_path, property, field_value)
    list.fold(nested_errors, acc, fn(m, err) {
      model.add_error_at_path(m, err.field, err)
    })
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
      let config = case model.find_property_at_path(model, field_path) {
        Ok(prop) -> prop.upload_config
        Error(_) -> None
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

/// Convert the form values tree to JSON.
fn values_to_json(values: Value) -> json.Json {
  json_utils.value_to_json(values)
}
