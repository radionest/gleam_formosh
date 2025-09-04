// Form model for MVU architecture

import gleam/dict.{type Dict}
import gleam/option.{type Option}
import gleam/list
import schema/types.{type FieldValue, type JsonSchema, type ValidationError}

// Form state model
pub type FormModel {
  FormModel(
    // The JSON Schema definition
    schema: JsonSchema,
    // Current form values
    values: Dict(String, FieldValue),
    // Form validation errors
    errors: Dict(String, List(ValidationError)),
    // Form metadata
    is_submitting: Bool,
    is_dirty: Bool,
    is_valid: Bool,
    // Touched fields (for showing errors)
    touched_fields: List(String),
    // Disabled fields
    disabled_fields: List(String),
    // Form submission result
    submission_result: Option(SubmissionResult),
  )
}

// Result of form submission
pub type SubmissionResult {
  SubmissionSuccess(message: String)
  SubmissionError(message: String)
}

// Messages for form updates
pub type FormMsg {
  // Field value changes
  FieldChanged(field_name: String, value: FieldValue)
  // Field focus/blur events
  FieldFocused(field_name: String)
  FieldBlurred(field_name: String)
  // Form submission
  FormSubmit
  FormSubmitted(Result(String, String))
  // Validation
  ValidateField(field_name: String)
  ValidateForm
  // Reset form
  ResetForm
  ClearField(field_name: String)
  // Enable/Disable fields
  EnableField(field_name: String)
  DisableField(field_name: String)
  // Array field operations
  AddArrayItem(field_name: String)
  RemoveArrayItem(field_name: String, index: Int)
  ArrayItemChanged(field_name: String, index: Int, item_field: String, value: FieldValue)
}

// Initialize a new form model from schema
pub fn init(schema: JsonSchema) -> FormModel {
  FormModel(
    schema: schema,
    values: dict.new(),
    errors: dict.new(),
    is_submitting: False,
    is_dirty: False,
    is_valid: True,
    touched_fields: [],
    disabled_fields: [],
    submission_result: option.None,
  )
}

// Check if a field is required
pub fn is_field_required(model: FormModel, field_name: String) -> Bool {
  list.contains(model.schema.required, field_name)
}

// Check if a field has errors
pub fn field_has_errors(model: FormModel, field_name: String) -> Bool {
  case dict.get(model.errors, field_name) {
    Ok(errors) -> list.length(errors) > 0
    Error(_) -> False
  }
}

// Check if a field has been touched
pub fn is_field_touched(model: FormModel, field_name: String) -> Bool {
  list.contains(model.touched_fields, field_name)
}

// Check if a field is disabled
pub fn is_field_disabled(model: FormModel, field_name: String) -> Bool {
  list.contains(model.disabled_fields, field_name)
}

// Get field value
pub fn get_field_value(model: FormModel, field_name: String) -> Option(FieldValue) {
  case dict.get(model.values, field_name) {
    Ok(value) -> option.Some(value)
    Error(_) -> option.None
  }
}

// Get field errors
pub fn get_field_errors(
  model: FormModel,
  field_name: String,
) -> List(ValidationError) {
  case dict.get(model.errors, field_name) {
    Ok(errors) -> errors
    Error(_) -> []
  }
}

// Set field value
pub fn set_field_value(
  model: FormModel,
  field_name: String,
  value: FieldValue,
) -> FormModel {
  FormModel(
    ..model,
    values: dict.insert(model.values, field_name, value),
    is_dirty: True,
  )
}

// Add field error
pub fn add_field_error(
  model: FormModel,
  field_name: String,
  error: ValidationError,
) -> FormModel {
  let current_errors = get_field_errors(model, field_name)
  let new_errors = list.append(current_errors, [error])
  
  FormModel(
    ..model,
    errors: dict.insert(model.errors, field_name, new_errors),
    is_valid: False,
  )
}

// Clear field errors
pub fn clear_field_errors(model: FormModel, field_name: String) -> FormModel {
  FormModel(
    ..model,
    errors: dict.delete(model.errors, field_name),
    is_valid: dict.size(model.errors) == 1,
  )
}

// Clear all errors
pub fn clear_all_errors(model: FormModel) -> FormModel {
  FormModel(
    ..model,
    errors: dict.new(),
    is_valid: True,
  )
}

// Mark field as touched
pub fn mark_field_touched(model: FormModel, field_name: String) -> FormModel {
  case is_field_touched(model, field_name) {
    True -> model
    False ->
      FormModel(
        ..model,
        touched_fields: list.append(model.touched_fields, [field_name]),
      )
  }
}

// Reset form to initial state
pub fn reset(model: FormModel) -> FormModel {
  FormModel(
    schema: model.schema,
    values: dict.new(),
    errors: dict.new(),
    is_submitting: False,
    is_dirty: False,
    is_valid: True,
    touched_fields: [],
    disabled_fields: [],
    submission_result: option.None,
  )
}

// Get all form values as dictionary
pub fn get_form_values(model: FormModel) -> Dict(String, FieldValue) {
  model.values
}

// Check if form can be submitted
pub fn can_submit(model: FormModel) -> Bool {
  model.is_valid && !model.is_submitting && model.is_dirty
}