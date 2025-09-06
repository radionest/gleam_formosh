// Update functions for form MVU

import gleam/dict
import gleam/list
import gleam/option.{Some}
import lustre/effect.{type Effect}
import form/model.{
  type FormModel, type FormMsg, AddArrayItem, ArrayItemChanged, DisableField,
  EnableField, FieldBlurred, FieldChanged, FieldFocused, FormSubmit,
  FormSubmitted, RemoveArrayItem, ResetForm, SubmissionError,
  SubmissionSuccess, ValidateField, ValidateForm,
}
import schema/validator
import schema/types

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
pub fn update(model: FormModel, msg: FormMsg) -> #(FormModel, Effect(FormMsg)) {
  case msg {
    FieldChanged(field_name, value) -> {
      let new_model =
        model
        |> model.set_field_value(field_name, value)
        |> validate_field_if_touched(field_name)
      
      #(new_model, effect.none())
    }

    FieldFocused(_field_name) -> {
      // Just track that field is focused, no state change needed
      #(model, effect.none())
    }

    FieldBlurred(field_name) -> {
      let new_model =
        model
        |> model.mark_field_touched(field_name)
        |> validate_field(field_name)
      
      #(new_model, effect.none())
    }

    FormSubmit -> {
      // Validate all fields before submission
      let validated_model = validate_all_fields(model)
      
      case model.can_submit(validated_model) {
        True -> {
          let submitting_model = model.FormModel(
            ..validated_model,
            is_submitting: True,
          )
          
          // Create submission effect
          let submit_effect = submit_form_effect(submitting_model)
          
          #(submitting_model, submit_effect)
        }
        False -> {
          // Mark all fields as touched to show errors
          let touched_model = mark_all_fields_touched(validated_model)
          #(touched_model, effect.none())
        }
      }
    }

    FormSubmitted(result) -> {
      case result {
        Ok(message) -> {
          let new_model = model.FormModel(
            ..model,
            is_submitting: False,
            submission_result: Some(SubmissionSuccess(message)),
          )
          #(new_model, effect.none())
        }
        Error(message) -> {
          let new_model = model.FormModel(
            ..model,
            is_submitting: False,
            submission_result: Some(SubmissionError(message)),
          )
          #(new_model, effect.none())
        }
      }
    }

    ValidateField(field_name) -> {
      let new_model = validate_field(model, field_name)
      #(new_model, effect.none())
    }

    ValidateForm -> {
      let new_model = validate_all_fields(model)
      #(new_model, effect.none())
    }

    ResetForm -> {
      let new_model = model.reset(model)
      #(new_model, effect.none())
    }

    model.ClearField(field_name) -> {
      let new_model =
        model
        |> model.set_field_value(field_name, types.NullValue)
        |> model.clear_field_errors(field_name)
      
      #(new_model, effect.none())
    }

    EnableField(field_name) -> {
      let new_model = model.FormModel(
        ..model,
        disabled_fields: list.filter(
          model.disabled_fields,
          fn(field) { field != field_name },
        ),
      )
      #(new_model, effect.none())
    }

    DisableField(field_name) -> {
      let new_model = case model.is_field_disabled(model, field_name) {
        True -> model
        False ->
          model.FormModel(
            ..model,
            disabled_fields: list.append(model.disabled_fields, [field_name]),
          )
      }
      #(new_model, effect.none())
    }

    AddArrayItem(field_name) -> {
      // Add a new empty item to the array field
      let current_value = model.get_field_value(model, field_name)
        |> option.unwrap(types.NullValue)
      
      let new_value = case current_value {
        types.ArrayValue(items) ->
          types.ArrayValue(list.append(items, [types.JsonObject([])]))
        _ ->
          types.ArrayValue([types.JsonObject([])])
      }
      
      let new_model = model.set_field_value(model, field_name, new_value)
      #(new_model, effect.none())
    }

    RemoveArrayItem(field_name, index) -> {
      // Remove an item from the array field at the given index
      let current_value = model.get_field_value(model, field_name)
        |> option.unwrap(types.NullValue)
      
      let new_value = case current_value {
        types.ArrayValue(items) -> {
          let filtered = list.index_fold(items, [], fn(acc, item, i) {
            case i == index {
              True -> acc
              False -> list.append(acc, [item])
            }
          })
          types.ArrayValue(filtered)
        }
        _ -> current_value
      }
      
      let new_model = model.set_field_value(model, field_name, new_value)
      #(new_model, effect.none())
    }

    ArrayItemChanged(field_name, index, item_field, value) -> {
      // Update a specific field within an array item
      echo #(field_name, index, item_field, value)
      let current_value = model.get_field_value(model, field_name)
        |> option.unwrap(types.NullValue)
      
      let new_value = case current_value {
        types.ArrayValue(items) -> {
          let updated = list.index_map(items, fn(item, i) {
            case i == index {
              True -> {
                case item {
                  types.JsonObject(fields) -> {
                    // Find and update the specific field
                    let updated_fields = list.map(fields, fn(field) {
                      let #(key, val) = field
                      case key == item_field {
                        True -> #(key, field_value_to_json_value(value))
                        False -> #(key, val)
                      }
                    })
                    types.JsonObject(updated_fields)
                  }
                  _ -> item
                }
              }
              False -> item
            }
          })
          types.ArrayValue(updated)
        }
        _ -> current_value
      }
      
      let new_model = model.set_field_value(model, field_name, new_value)
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
fn field_value_to_json_value(value: types.FieldValue) -> types.JsonValue {
  case value {
    types.StringValue(s) -> types.JsonString(s)
    types.NumberValue(n) -> types.JsonNumber(n)
    types.IntegerValue(i) -> types.JsonNumber(int.to_float(i))
    types.BooleanValue(b) -> types.JsonBool(b)
    types.ArrayValue(items) -> types.JsonArray(items)
    types.ObjectValue(fields) -> types.JsonObject(fields)
    types.NullValue -> types.JsonNull
  }
}

import gleam/int

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
      let errors = validator.validate_field(
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

/// Validate a field only if it has been touched by the user.
/// 
/// This provides a better user experience by avoiding validation errors
/// on fields the user hasn't interacted with yet.
/// 
/// ## Parameters
/// - `model`: The current form model
/// - `field_name`: The name of the field to conditionally validate
/// 
/// ## Returns
/// A new FormModel with validation run only if the field was touched
fn validate_field_if_touched(model: FormModel, field_name: String) -> FormModel {
  case model.is_field_touched(model, field_name) {
    True -> validate_field(model, field_name)
    False -> model
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

/// Mark all schema-defined fields as touched.
/// 
/// This is typically used when form submission fails validation,
/// to ensure all validation errors are visible to the user.
/// 
/// ## Parameters
/// - `model`: The current form model
/// 
/// ## Returns
/// A new FormModel with all fields marked as touched
fn mark_all_fields_touched(model: FormModel) -> FormModel {
  let all_fields = dict.keys(model.schema.properties)
  model.FormModel(
    ..model,
    touched_fields: all_fields,
  )
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