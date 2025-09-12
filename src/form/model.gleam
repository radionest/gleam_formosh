// Form model for MVU architecture

import form/path.{type FieldPath}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option}
import schema/types.{type JsonSchema, type ValidationError, type Value}

/// Configuration for form submission behavior.
/// 
/// This type allows customization of how the form handles submission,
/// including where to send data and how to handle responses.
pub type SubmitConfig {
  /// Submit form data to an HTTP endpoint
  HttpSubmit(url: String, method: String, headers: List(#(String, String)))
  /// Handle submission with a custom function
  CustomSubmit(handler: fn(FormModel) -> Result(String, String))
  /// No submission handler (form values can be retrieved manually)
  NoSubmit
}

/// The main form state model for the MVU architecture.
/// 
/// This type contains all the state needed to render and manage a form,
/// including the schema definition, current values, validation errors,
/// and form metadata like submission status.
pub type FormModel {
  FormModel(
    // The JSON Schema definition
    schema: JsonSchema,
    // The resolved schema with conditionals applied
    resolved_schema: JsonSchema,
    // Current form values
    values: Dict(String, Value),
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
    // Submission configuration
    submit_config: Option(SubmitConfig),
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
  // Path-based operations (simplified approach)
  UpdateFieldPath(path: FieldPath, value: Value)
  AddArrayItemPath(path: FieldPath)
  RemoveArrayItemPath(path: FieldPath, index: Int)

  // Form submission
  FormSubmit
  FormSubmitted(Result(String, String))

  // Validation
  ValidateForm

  // Reset form
  ResetForm
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
  init_with_config(schema, option.None)
}

/// Initialize a new form model with submission configuration.
/// 
/// Creates a form with optional submission handling configuration.
/// 
/// ## Parameters
/// - `schema`: The JSON Schema definition for this form
/// - `submit_config`: Optional submission configuration
/// 
/// ## Returns
/// A new FormModel with the provided configuration
pub fn init_with_config(
  schema: JsonSchema,
  submit_config: Option(SubmitConfig),
) -> FormModel {
  // Initially, resolved_schema is the same as the base schema
  // It will be updated when form values change
  FormModel(
    schema: schema,
    resolved_schema: schema,
    values: dict.new(),
    errors: dict.new(),
    is_submitting: False,
    is_dirty: False,
    is_valid: True,
    touched_fields: [],
    disabled_fields: [],
    submission_result: option.None,
    submit_config: submit_config,
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
/// - `Some(Value)` if the field has a value
/// - `None` if the field has not been set or doesn't exist
pub fn get_field_value(
  model: FormModel,
  field_name: String,
) -> Option(Value) {
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
  value: Value,
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
  let new_errors = dict.delete(model.errors, field_name)
  FormModel(
    ..model,
    errors: new_errors,
    is_valid: dict.size(new_errors) == 0,
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
  FormModel(..model, errors: dict.new(), is_valid: True)
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
    resolved_schema: model.schema,
    // Reset to base schema with no conditionals applied
    values: dict.new(),
    errors: dict.new(),
    is_submitting: False,
    is_dirty: False,
    is_valid: True,
    touched_fields: [],
    disabled_fields: [],
    submission_result: option.None,
    submit_config: model.submit_config,
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
pub fn get_form_values(model: FormModel) -> Dict(String, Value) {
  model.values
}

/// Get the value at a specific path in the form.
/// 
/// Traverses the form values following the given path to retrieve a value
/// from potentially nested structures (arrays, objects).
/// 
/// ## Parameters
/// - `model`: The form model containing field values
/// - `path`: The field path to traverse
/// 
/// ## Returns
/// - `Some(Value)` if a value exists at the path
/// - `None` if the path doesn't exist or has no value
pub fn get_value_at_path(
  model: FormModel,
  field_path: FieldPath,
) -> Option(Value) {
  case field_path {
    [] -> option.None
    [path.PropertySegment(name)] -> get_field_value(model, name)
    [path.PropertySegment(name), ..rest] ->
      case get_field_value(model, name) {
        option.Some(types.ArrayValue(items)) -> traverse_array_path(items, rest)
        option.Some(types.ObjectValue(obj)) -> traverse_object_path(obj, rest)
        _ -> option.None
      }
    [path.ArraySegment(_), ..] ->
      // Array segment at root level doesn't make sense
      option.None
  }
}

/// Helper function to traverse an array with a path.
fn traverse_array_path(
  items: List(types.Value),
  remaining_path: FieldPath,
) -> Option(Value) {
  case remaining_path {
    [] -> option.None
    [path.ArraySegment(index), ..rest] ->
      case list_at(items, index) {
        option.Some(types.ObjectValue(obj_fields)) ->
          case rest {
            [] -> option.None
            [path.PropertySegment(field_name)] ->
              case list.find(obj_fields, fn(f) { f.0 == field_name }) {
                Ok(#(_, val)) -> option.Some(val)
                Error(_) -> option.None
              }
            [path.PropertySegment(field_name), ..more] ->
              case list.find(obj_fields, fn(f) { f.0 == field_name }) {
                Ok(#(_, types.ArrayValue(nested_items))) ->
                  traverse_array_path(nested_items, more)
                Ok(#(_, types.ObjectValue(nested_obj))) ->
                  traverse_object_path(nested_obj, more)
                _ -> option.None
              }
            _ -> option.None
          }
        _ -> option.None
      }
    _ -> option.None
  }
}

/// Helper function to get list element by index.
fn list_at(items: List(a), index: Int) -> Option(a) {
  case index, items {
    0, [first, ..] -> option.Some(first)
    n, [_, ..rest] if n > 0 -> list_at(rest, n - 1)
    _, _ -> option.None
  }
}

/// Helper function to traverse an object with a path.
fn traverse_object_path(
  obj: List(#(String, types.Value)),
  remaining_path: FieldPath,
) -> Option(Value) {
  case remaining_path {
    [] -> option.None
    [path.PropertySegment(field_name)] ->
      case list.find(obj, fn(f) { f.0 == field_name }) {
        Ok(#(_, val)) -> option.Some(val)
        Error(_) -> option.None
      }
    [path.PropertySegment(field_name), ..rest] ->
      case list.find(obj, fn(f) { f.0 == field_name }) {
        Ok(#(_, types.ArrayValue(items))) -> traverse_array_path(items, rest)
        Ok(#(_, types.ObjectValue(nested_obj))) ->
          traverse_object_path(nested_obj, rest)
        _ -> option.None
      }
    _ -> option.None
  }
}

/// Check if a field at a specific path is required.
/// 
/// For root-level fields, checks the schema's required list.
/// For nested fields, would need schema traversal (not implemented yet).
/// 
/// ## Parameters
/// - `model`: The form model containing the schema
/// - `field_path`: The path to the field
/// 
/// ## Returns
/// True if the field is required, False otherwise
pub fn is_required_at_path(model: FormModel, field_path: FieldPath) -> Bool {
  case field_path {
    [path.PropertySegment(name)] -> is_field_required(model, name)
    _ ->
      // For nested paths, we'd need to traverse the schema
      // For now, default to not required for nested fields
      False
  }
}

/// Check if a field at a specific path has validation errors.
/// 
/// ## Parameters
/// - `model`: The form model containing error state
/// - `field_path`: The path to the field
/// 
/// ## Returns
/// True if the field has errors, False otherwise
pub fn has_errors_at_path(model: FormModel, field_path: FieldPath) -> Bool {
  let path_key = path.to_string(field_path)
  case dict.get(model.errors, path_key) {
    Ok(errors) -> list.length(errors) > 0
    Error(_) -> False
  }
}

/// Get validation errors for a field at a specific path.
/// 
/// ## Parameters
/// - `model`: The form model containing error state
/// - `field_path`: The path to the field
/// 
/// ## Returns
/// List of validation errors (empty if no errors)
pub fn get_errors_at_path(
  model: FormModel,
  field_path: FieldPath,
) -> List(ValidationError) {
  let path_key = path.to_string(field_path)
  case dict.get(model.errors, path_key) {
    Ok(errors) -> errors
    Error(_) -> []
  }
}

/// Set the value at a specific path in the form.
/// 
/// Updates a value at the given path, handling nested structures.
/// 
/// ## Parameters
/// - `model`: The current form model
/// - `field_path`: The path where to set the value
/// - `value`: The new value
/// 
/// ## Returns
/// A new FormModel with the updated value
pub fn set_value_at_path(
  model: FormModel,
  field_path: FieldPath,
  value: Value,
) -> FormModel {
  let path_key = path.to_string(field_path)
  FormModel(
    ..model,
    values: dict.insert(model.values, path_key, value),
    is_dirty: True,
  )
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
  model.is_valid && !model.is_submitting
}
