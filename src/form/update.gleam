// Update functions for form MVU

import form/converter
import form/model.{
  type FormModel, type FormMsg, AddArrayItemPath, FormSubmit, FormSubmitted,
  RemoveArrayItemPath, ResetForm, SubmissionError, SubmissionSuccess,
  UpdateFieldPath, ValidateForm,
}
import form/path
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import lustre/effect.{type Effect}
import schema/types
import schema/validator

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
/// - `FieldChanged`: Update field value and validate if touched
/// - `FieldFocused`: Track field focus (no state change)
/// - `FieldBlurred`: Mark field as touched and validate
/// - `FormSubmit`: Validate and submit the form
/// - `FormSubmitted`: Handle submission result
/// - `ValidateField`/`ValidateForm`: Trigger validation
/// - `ResetForm`: Reset form to initial state
/// - `EnableField`/`DisableField`: Control field enabled state
/// - Array operations: `AddArrayItem`, `RemoveArrayItem`, `ArrayItemChanged`
/// Convert model values to a hierarchical FieldValue root for path operations.
/// 
/// This helper function converts the flat dictionary of field values in the model
/// to a hierarchical FieldValue object that can be used with path-based operations.
/// 
/// ## Parameters
/// - `model`: The form model containing the values dictionary
/// 
/// ## Returns
/// A FieldValue (ObjectValue) representing the hierarchical form data
fn model_to_root_value(model: FormModel) -> types.FieldValue {
  case dict.to_list(model.values) {
    [] -> types.ObjectValue([])
    values -> {
      let fields =
        list.map(values, fn(entry) {
          let #(key, val) = entry
          #(key, converter.field_value_to_json_value(val))
        })
      types.ObjectValue(fields)
    }
  }
}

/// Convert a hierarchical FieldValue root back to model values dictionary.
/// 
/// This helper function converts the hierarchical FieldValue object returned from
/// path operations back to the flat dictionary format used by the model.
/// 
/// ## Parameters
/// - `root_value`: The hierarchical FieldValue to convert
/// 
/// ## Returns
/// A dictionary of field names to FieldValues
fn root_value_to_model_values(
  root_value: types.FieldValue,
) -> dict.Dict(String, types.FieldValue) {
  case root_value {
    types.ObjectValue(fields) -> {
      list.fold(fields, dict.new(), fn(acc, field) {
        let #(key, json_val) = field
        case converter.json_to_field_value(json_val) {
          Some(field_val) -> dict.insert(acc, key, field_val)
          None -> acc
        }
      })
    }
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

      let new_model =
        model.FormModel(..model, values: new_values, is_dirty: True)
      #(new_model, effect.none())
    }

    AddArrayItemPath(path) -> {
      let root_value = model_to_root_value(model)
      let updated_root =
        path.add_array_item_at_path(root_value, path, types.JsonObject([]))
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

/// Convert a FieldValue to JsonValue for serialization.
/// 
/// This helper function is used when updating array items to convert the
/// strongly-typed FieldValue into a JsonValue that can be stored in the
/// JSON object structure.
/// 
/// ## Parameters
/// - `value`: The FieldValue to convert
/// 
/// ## Returns
/// The corresponding JsonValue representation
/// Convert a JsonValue to FieldValue.
/// 
/// This helper function is used when converting from JsonValue 
/// back to FieldValue after path-based updates.
/// 
/// ## Parameters
/// - `value`: The JsonValue to convert
/// 
/// ## Returns
/// The corresponding FieldValue representation wrapped in Option
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
          model.is_field_required(model, field_name),
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
fn validate_all_fields(model: FormModel) -> FormModel {
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
fn submit_form_effect(_model: FormModel) -> Effect(FormMsg) {
  // In a real application, this would make an HTTP request
  // For now, we'll just simulate a successful submission
  effect.from(fn(dispatch) {
    // Simulate async submission
    dispatch(FormSubmitted(Ok("Form submitted successfully!")))
    Nil
  })
}
