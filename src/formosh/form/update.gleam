// Update functions for form MVU

import formosh/ffi/console
import formosh/ffi/image_upload as image_upload_ffi
import formosh/form/defaults
import formosh/form/json_utils
import formosh/form/model.{
  type FormModel, type FormMsg, AddArrayItemPath, ClearFieldPath, CustomSubmit,
  FileUploadError, FileUploading, FormSubmit, FormSubmitted, HttpSubmit,
  MoveArrayItemPath, NoSubmit, RemoveArrayItemPath, ResetForm, SubmissionError,
  SubmissionSuccess, UpdateFieldPath, ValidateForm, WidgetEvent, image_msg,
}
import formosh/form/path
import formosh/form/widget_msg.{
  AnswerZone, DragCancel, DragEnd, DragMove, DragStart, ExitDone, ExitLeft,
  ExitRight, FillRemaining, ImageCompleted, ImageFailed, ImageRemoved,
  ImageRequested, ImageStarted, ImageUpload, SwipeReview, ToggleHideAnswered,
}
import formosh/schema/conditional_resolver
import formosh/schema/properties
import formosh/schema/types.{type Value}
import formosh/schema/ui_resolver
import formosh/schema/validator
import formosh/validation/cross_validator
import formosh/validation/error
import gleam/bool
import gleam/dict
import gleam/http/response
import gleam/io
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
      let reconciled_values =
        defaults.ensure_min_items(resolved_schema.properties, new_values)
      let touched_model = model.mark_field_touched(model, field_path)
      let new_model =
        model.FormModel(
          ..touched_model,
          values: reconciled_values,
          resolved_schema: resolved_schema,
          is_dirty: True,
        )
      let validated_model = validate_all_fields(new_model)
      #(validated_model, effect.none())
    }

    ClearFieldPath(field_path) -> {
      let new_values = path.remove_at_path(model.values, field_path)
      let resolved_schema =
        conditional_resolver.resolve_recursive(model.schema, new_values)
      let reconciled_values =
        defaults.ensure_min_items(resolved_schema.properties, new_values)
      let touched_model = model.mark_field_touched(model, field_path)
      let new_model =
        model.FormModel(
          ..touched_model,
          values: reconciled_values,
          resolved_schema: resolved_schema,
          is_dirty: True,
          // Re-opening a zone (swipe-review undo / summary correction) cancels
          // any in-flight fly-off for that path so it can't linger in `exiting`.
          swipe_exiting: list.filter(model.swipe_exiting, fn(p) {
            p.0 != field_path
          }),
        )
      let validated_model = validate_all_fields(new_model)
      #(validated_model, effect.none())
    }

    AddArrayItemPath(field_path) -> {
      // Build the new row from the item schema so manual rows carry the
      // same field defaults as auto-created ones. The value-resolved
      // lookup also finds arrays revealed by per-row conditionals.
      let new_item = case
        model.find_resolved_property_at_path(model, field_path)
      {
        Ok(prop) ->
          case prop.items {
            Some(item_schema) -> defaults.new_array_item(item_schema)
            None -> types.ObjectValue([])
          }
        Error(_) -> types.ObjectValue([])
      }
      let new_values =
        path.add_array_item_at_path(model.values, field_path, new_item)
      let reconciled_values =
        defaults.ensure_min_items(model.resolved_schema.properties, new_values)
      let new_model =
        model.FormModel(..model, values: reconciled_values, is_dirty: True)
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

    MoveArrayItemPath(field_path, from, to) -> {
      let new_values =
        path.move_array_item_at_path(model.values, field_path, from, to)
      // No-op move (same index, out of range, or path is not an array): the
      // values are untouched, so leave touched_fields and the dirty flag alone
      // — reindexing here would desync touched paths from values.
      use <- bool.guard(new_values == model.values, #(model, effect.none()))
      let new_touched =
        list.map(model.touched_fields, fn(p) {
          path.reindex_after_array_move(p, field_path, from, to)
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
          warn_if_only_hidden_blocks(validated_model)
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

    WidgetEvent(ImageUpload(image_event)) ->
      handle_image_upload_event(model, image_event)

    WidgetEvent(SwipeReview(swipe_event)) ->
      handle_swipe_review_event(model, swipe_event)
  }
}

/// Handle swipe-review widget events: bulk-finish, the live drag lifecycle
/// (start / move / end / cancel), a tap commit (`AnswerZone`), and the fly-off
/// completion (`ExitDone`). Drag start/move/cancel only mutate the transient
/// `swipe_drag`; an answer is committed on a tap, a release past threshold, or
/// bulk-finish — committing flies the card off (hide mode) via `commit_zone`.
fn handle_swipe_review_event(
  model: FormModel,
  event: widget_msg.SwipeReviewEvent,
) -> #(FormModel, Effect(FormMsg)) {
  case event {
    FillRemaining(paths, code) -> #(
      apply_answers(model, list.map(paths, fn(p) { #(p, code) })),
      effect.none(),
    )

    DragStart(path, start_x, pos_code, neg_code, threshold) -> {
      let drag =
        model.SwipeDrag(path, start_x, 0.0, pos_code, neg_code, threshold)
      #(model.FormModel(..model, swipe_drag: Some(drag)), effect.none())
    }

    DragMove(x) ->
      case model.swipe_drag {
        Some(d) -> #(
          model.FormModel(
            ..model,
            swipe_drag: Some(model.SwipeDrag(..d, dx: x -. d.start_x)),
          ),
          effect.none(),
        )
        None -> #(model, effect.none())
      }

    DragEnd ->
      case model.swipe_drag {
        Some(d) -> {
          let cleared = model.FormModel(..model, swipe_drag: None)
          case d.dx >=. d.threshold, d.dx <=. 0.0 -. d.threshold {
            True, _ -> commit_zone(model, d.path, d.pos_code, ExitRight)
            _, True -> commit_zone(model, d.path, d.neg_code, ExitLeft)
            _, _ -> #(cleared, effect.none())
          }
        }
        None -> #(model, effect.none())
      }

    DragCancel -> #(model.FormModel(..model, swipe_drag: None), effect.none())

    ToggleHideAnswered -> #(
      model.FormModel(
        ..model,
        swipe_hide_answered: !model.swipe_hide_answered,
        swipe_exiting: [],
      ),
      effect.none(),
    )

    AnswerZone(field_path, code, dir) ->
      commit_zone(model, field_path, code, dir)

    ExitDone(field_path) -> #(
      model.FormModel(
        ..model,
        swipe_exiting: list.filter(model.swipe_exiting, fn(p) {
          p.0 != field_path
        }),
      ),
      effect.none(),
    )
  }
}

/// Set each `#(path, code)` zone answer, re-resolve conditionals, mark the
/// paths touched, and re-validate — the shared commit path for bulk-finish and
/// a past-threshold swipe release.
fn apply_answers(
  model: FormModel,
  answers: List(#(path.FieldPath, String)),
) -> FormModel {
  let new_values =
    list.fold(answers, model.values, fn(acc, pair) {
      path.set_at_path(acc, pair.0, types.StringValue(pair.1))
    })
  let resolved_schema =
    conditional_resolver.resolve_recursive(model.schema, new_values)
  let reconciled_values =
    defaults.ensure_min_items(resolved_schema.properties, new_values)
  let touched_model =
    list.fold(answers, model, fn(m, pair) {
      model.mark_field_touched(m, pair.0)
    })
  let new_model =
    model.FormModel(
      ..touched_model,
      values: reconciled_values,
      resolved_schema: resolved_schema,
      is_dirty: True,
    )
  validate_all_fields(new_model)
}

/// Commit a single zone answer (shared by tap `AnswerZone` and a past-threshold
/// swipe release) and, in hide-answered mode only, mark the card as exiting so
/// the renderer keeps it on-screen flying off until its `transitionend`.
fn commit_zone(
  model: FormModel,
  field_path: path.FieldPath,
  code: String,
  dir: widget_msg.ExitDir,
) -> #(FormModel, Effect(FormMsg)) {
  let committed = apply_answers(model, [#(field_path, code)])
  let exiting = case model.swipe_hide_answered {
    True -> list.key_set(committed.swipe_exiting, field_path, dir)
    False -> committed.swipe_exiting
  }
  #(
    model.FormModel(..committed, swipe_drag: None, swipe_exiting: exiting),
    effect.none(),
  )
}

/// Handle the image-upload widget lifecycle events.
fn handle_image_upload_event(
  model: FormModel,
  event: widget_msg.ImageUploadEvent,
) -> #(FormModel, Effect(FormMsg)) {
  case event {
    ImageRequested(field_path) -> {
      let upload_effect = create_upload_effect(model, field_path)
      #(model, upload_effect)
    }

    ImageStarted(field_path, temp_id, preview_url) -> {
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

    ImageCompleted(field_path, temp_id, server_url) -> {
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

    ImageFailed(field_path, temp_id, error) -> {
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
      let hints =
        ui_resolver.resolve_hints(model.ui_schema, field_path, property)
      let errors =
        validator.validate_field(
          field_path,
          value,
          property,
          model.is_required_at_path(model, field_path),
          hints.widget,
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
/// Runs validation in three passes:
///   1. Top-level fields against `resolved_schema.properties`.
///   2. For every top-level field, recursively validate nested object/array
///      structures via `validator.validate_nested`. Item-level conditionals
///      (`if/then/else`, `allOf`) are re-evaluated per row/per object.
///   3. If a cross-field custom validator is configured, run it against the
///      now-fully-populated model and merge its errors via
///      `add_error_at_path`. This is where rules like "sum ≤ total" or
///      "endDate > startDate" plug in.
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

  let after_nested =
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

  case after_nested.validator, after_nested.touched_fields {
    None, _ -> after_nested
    // Skip the custom validator until the user has touched something. This
    // prevents pre-touch errors from invisibly blocking submit (UI hides
    // them via touched-gate, but `is_valid` already flipped to False).
    Some(_), [] -> after_nested
    Some(v), _ -> {
      let cross_errors =
        cross_validator.run(v, after_nested, serialize_values)
        |> list.filter(filter_cross_error(_, after_nested))
      list.fold(cross_errors, after_nested, fn(m, err) {
        model.add_error_at_path(m, err.field, err)
      })
    }
  }
}

/// Filter pass for a single cross-validator error.
///
/// Drops:
///   - empty paths (would land under key "" and silently block submit)
///   - paths that don't resolve to any field in the resolved schema (typos,
///     ghost errors that the UI can never render)
///   - paths where the schema already produced an error (avoid stacking
///     "required" + "sum exceeds" on the same field — schema error wins
///     until the user fixes it)
fn filter_cross_error(err: error.ValidationError, m: FormModel) -> Bool {
  case err.field {
    [] -> False
    _ ->
      case model.find_property_at_path(m, err.field) {
        Error(_) -> {
          io.println_error(
            "formosh: dropping validator error for unknown path: "
            <> path.to_string(err.field),
          )
          False
        }
        Ok(_) -> !model.has_errors_at_path(m, err.field)
      }
  }
}

/// Serialise a form model's values to a JSON string for FFI consumption.
fn serialize_values(m: FormModel) -> String {
  m.values
  |> json_utils.value_to_json
  |> json.to_string
}

/// Diagnostic for the strict submit gate: when the only blocking errors are
/// on UI-suppressed paths, the user sees a disabled submit button with no
/// associated message anywhere on the page. Emit a single `console.warn`
/// listing the offending paths so the developer can locate the schema bug
/// (typically a hidden/readOnly-suppressed field that is `required` but has
/// no `default` and no programmatic value).
fn warn_if_only_hidden_blocks(model: FormModel) -> Nil {
  case model.is_valid_for_submit(model) {
    False -> Nil
    True -> {
      let hidden = model.hidden_errors(model)
      case dict.is_empty(hidden) {
        True -> Nil
        False -> console.warn(format_hidden_errors_warning(hidden))
      }
    }
  }
}

fn format_hidden_errors_warning(
  hidden: dict.Dict(String, List(error.ValidationError)),
) -> String {
  let lines =
    hidden
    |> dict.to_list
    |> list.flat_map(fn(entry) {
      let #(path_key, errors) = entry
      list.map(errors, fn(err) { "  - " <> path_key <> ": " <> err.message })
    })
  "[formosh] Submit blocked by errors on UI-suppressed fields:\n"
  <> string.join(lines, "\n")
  <> "\nThese paths are hidden (`x-widget`/`ui:widget: \"hidden\"`) or"
  <> " readOnly with `show_readonly_fields: false`. Supply a JSON Schema"
  <> " `default`, set the value programmatically, or drop `required`."
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
        Ok(prop) ->
          ui_resolver.resolve_hints(model.ui_schema, field_path, prop).upload_config
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
            dispatch(image_msg(ImageStarted(field_path, temp_id, preview_url)))
            Nil
          },
          fn(temp_id, server_url) {
            dispatch(image_msg(ImageCompleted(field_path, temp_id, server_url)))
            Nil
          },
          fn(temp_id, error) {
            dispatch(image_msg(ImageFailed(field_path, temp_id, error)))
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
