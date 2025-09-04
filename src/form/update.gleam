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

// Main update function
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

// Helper function to convert FieldValue to JsonValue
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

// Validate a single field
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

// Validate field only if it has been touched
fn validate_field_if_touched(model: FormModel, field_name: String) -> FormModel {
  case model.is_field_touched(model, field_name) {
    True -> validate_field(model, field_name)
    False -> model
  }
}

// Validate all fields
fn validate_all_fields(model: FormModel) -> FormModel {
  dict.keys(model.schema.properties)
  |> list.fold(model.clear_all_errors(model), validate_field)
}

// Mark all fields as touched
fn mark_all_fields_touched(model: FormModel) -> FormModel {
  let all_fields = dict.keys(model.schema.properties)
  model.FormModel(
    ..model,
    touched_fields: all_fields,
  )
}

// Create form submission effect
fn submit_form_effect(_model: FormModel) -> Effect(FormMsg) {
  // In a real application, this would make an HTTP request
  // For now, we'll just simulate a successful submission
  effect.from(fn(dispatch) {
    // Simulate async submission
    dispatch(FormSubmitted(Ok("Form submitted successfully!")))
    Nil
  })
}