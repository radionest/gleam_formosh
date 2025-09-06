// Form model for MVU architecture

import gleam/dict.{type Dict}
import gleam/option.{type Option}
import gleam/list
import schema/types.{type FieldValue, type JsonSchema, type ValidationError}

/// The main form state model for the MVU architecture.
/// 
/// This type contains all the state needed to render and manage a form,
/// including the schema definition, current values, validation errors,
/// and form metadata like submission status.
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

/// Result of a form submission attempt.
/// 
/// This type represents the outcome of submitting a form, either success
/// or failure with an appropriate message for the user.
pub type SubmissionResult {
  SubmissionSuccess(message: String)
  SubmissionError(message: String)
}

/// Messages for form updates in the MVU architecture.
/// 
/// These messages represent all possible user interactions and system events
/// that can modify the form state. Each message corresponds to a specific
/// update operation in the form's update function.
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

/// Initialize a new form model from a JSON Schema.
/// 
/// Creates a fresh form state with empty values and no errors, ready to
/// receive user input. The form starts in a clean, unsubmitted state.
/// 
/// ## Parameters
/// - `schema`: The JSON Schema definition for this form
/// 
/// ## Returns
/// A new FormModel with default values
/// 
/// ## Example
/// ```gleam
/// let schema = JsonSchema(...)
/// let form = model.init(schema)
/// ```
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

/// Check if a field is required according to the schema.
/// 
/// Looks up whether a field name is in the required fields list of the schema.
/// This is used for validation and rendering required field indicators.
/// 
/// ## Parameters
/// - `model`: The form model containing the schema
/// - `field_name`: The name of the field to check
/// 
/// ## Returns
/// True if the field is required, False otherwise
pub fn is_field_required(model: FormModel, field_name: String) -> Bool {
  list.contains(model.schema.required, field_name)
}

/// Check if a field has any validation errors.
/// 
/// This is useful for conditional rendering of error states and styling.
/// 
/// ## Parameters
/// - `model`: The form model containing error state
/// - `field_name`: The name of the field to check
/// 
/// ## Returns
/// True if the field has one or more validation errors, False otherwise
pub fn field_has_errors(model: FormModel, field_name: String) -> Bool {
  case dict.get(model.errors, field_name) {
    Ok(errors) -> list.length(errors) > 0
    Error(_) -> False
  }
}

/// Check if a field has been touched (focused and then blurred).
/// 
/// Touched fields are typically used to determine when to show validation
/// errors - usually errors are only shown after a user has interacted with
/// a field to avoid showing errors on initial page load.
/// 
/// ## Parameters
/// - `model`: The form model containing touch state
/// - `field_name`: The name of the field to check
/// 
/// ## Returns
/// True if the field has been touched, False otherwise
pub fn is_field_touched(model: FormModel, field_name: String) -> Bool {
  list.contains(model.touched_fields, field_name)
}

/// Check if a field is currently disabled.
/// 
/// Disabled fields cannot be edited and are typically rendered with
/// different styling to indicate their state.
/// 
/// ## Parameters
/// - `model`: The form model containing disabled field state
/// - `field_name`: The name of the field to check
/// 
/// ## Returns
/// True if the field is disabled, False otherwise
pub fn is_field_disabled(model: FormModel, field_name: String) -> Bool {
  list.contains(model.disabled_fields, field_name)
}

/// Get the current value of a field.
/// 
/// Retrieves the current value for a named field from the form's value store.
/// 
/// ## Parameters
/// - `model`: The form model containing field values
/// - `field_name`: The name of the field to retrieve
/// 
/// ## Returns
/// - `Some(FieldValue)` if the field has a value
/// - `None` if the field has not been set or doesn't exist
pub fn get_field_value(model: FormModel, field_name: String) -> Option(FieldValue) {
  case dict.get(model.values, field_name) {
    Ok(value) -> option.Some(value)
    Error(_) -> option.None
  }
}

/// Get all validation errors for a specific field.
/// 
/// Returns the list of validation errors associated with a field name.
/// This is used for displaying error messages in the UI.
/// 
/// ## Parameters
/// - `model`: The form model containing error state
/// - `field_name`: The name of the field to get errors for
/// 
/// ## Returns
/// A list of ValidationError objects. Empty list means no errors.
pub fn get_field_errors(
  model: FormModel,
  field_name: String,
) -> List(ValidationError) {
  case dict.get(model.errors, field_name) {
    Ok(errors) -> errors
    Error(_) -> []
  }
}

/// Set the value of a field and mark the form as dirty.
/// 
/// Updates a field's value in the form model and marks the form as dirty
/// (indicating it has been modified from its initial state).
/// 
/// ## Parameters
/// - `model`: The current form model
/// - `field_name`: The name of the field to update
/// - `value`: The new value for the field
/// 
/// ## Returns
/// A new FormModel with the updated field value and dirty state
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

/// Add a validation error to a field.
/// 
/// Appends a new validation error to the field's error list and marks
/// the form as invalid.
/// 
/// ## Parameters
/// - `model`: The current form model
/// - `field_name`: The name of the field to add the error to
/// - `error`: The validation error to add
/// 
/// ## Returns
/// A new FormModel with the added error and updated validity state
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

/// Clear all validation errors for a specific field.
/// 
/// Removes all validation errors associated with a field name and updates
/// the form's overall validity if this was the last field with errors.
/// 
/// ## Parameters
/// - `model`: The current form model
/// - `field_name`: The name of the field to clear errors for
/// 
/// ## Returns
/// A new FormModel with the field's errors cleared
pub fn clear_field_errors(model: FormModel, field_name: String) -> FormModel {
  FormModel(
    ..model,
    errors: dict.delete(model.errors, field_name),
    is_valid: dict.size(model.errors) == 1,
  )
}

/// Clear all validation errors from the form.
/// 
/// Removes all validation errors from all fields and marks the form as valid.
/// This is typically used when starting a fresh validation cycle.
/// 
/// ## Parameters
/// - `model`: The current form model
/// 
/// ## Returns
/// A new FormModel with all errors cleared and valid state
pub fn clear_all_errors(model: FormModel) -> FormModel {
  FormModel(
    ..model,
    errors: dict.new(),
    is_valid: True,
  )
}

/// Mark a field as touched (user has interacted with it).
/// 
/// Adds a field to the touched fields list if it's not already there.
/// Touched state is used to determine when to show validation errors.
/// 
/// ## Parameters
/// - `model`: The current form model
/// - `field_name`: The name of the field to mark as touched
/// 
/// ## Returns
/// A new FormModel with the field marked as touched
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

/// Reset the form to its initial state.
/// 
/// Clears all field values, errors, and resets all form state flags while
/// preserving the original schema. This is like creating a fresh form.
/// 
/// ## Parameters
/// - `model`: The current form model (schema is preserved)
/// 
/// ## Returns
/// A new FormModel in initial state with the same schema
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

/// Get all current form values as a dictionary.
/// 
/// Returns the complete set of form field values. This is useful for
/// form submission or serialization.
/// 
/// ## Parameters
/// - `model`: The form model containing field values
/// 
/// ## Returns
/// A dictionary mapping field names to their current values
pub fn get_form_values(model: FormModel) -> Dict(String, FieldValue) {
  model.values
}

/// Check if the form can be submitted.
/// 
/// A form can be submitted if it is valid (no validation errors),
/// not currently being submitted, and has been modified (is dirty).
/// 
/// ## Parameters
/// - `model`: The form model to check
/// 
/// ## Returns
/// True if the form can be submitted, False otherwise
pub fn can_submit(model: FormModel) -> Bool {
  model.is_valid && !model.is_submitting && model.is_dirty
}