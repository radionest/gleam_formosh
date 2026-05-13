// Form model for MVU architecture

import formosh/form/path.{type FieldPath}
import formosh/schema/types.{
  type JsonSchema, type SchemaProperty, type ValidationError, type Value,
  ArrayValue, NullValue, ObjectType, ObjectValue, has_property_key,
}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option}

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
    // Whether to display readOnly fields
    show_readonly_fields: Bool,
    // Base URL for file uploads (from web component attribute)
    upload_base_url: Option(String),
    // In-flight upload states: field_path_string -> list of uploads
    upload_states: Dict(String, List(FileUploadState)),
  )
}

/// State of a file upload in progress.
pub type FileUploadState {
  FileUploading(temp_id: String, preview_url: String)
  FileUploadError(temp_id: String, error: String)
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

  // Image upload lifecycle
  ImageUploadRequested(path: FieldPath)
  ImageUploadStarted(path: FieldPath, temp_id: String, preview_url: String)
  ImageUploadCompleted(path: FieldPath, temp_id: String, server_url: String)
  ImageUploadFailed(path: FieldPath, temp_id: String, error: String)
  ImageRemoved(path: FieldPath, server_url: String)
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
  init_with_full_config(schema, submit_config, False, dict.new())
}

/// Initialize a new form model with full configuration including readOnly and initial values.
///
/// Creates a form with all configuration options.
///
/// ## Parameters
/// - `schema`: The JSON Schema definition for this form
/// - `submit_config`: Optional submission configuration
/// - `show_readonly_fields`: Whether to display readOnly fields
/// - `initial_values`: Initial values to populate the form with
///
/// ## Returns
/// A new FormModel with the provided configuration
pub fn init_with_full_config(
  schema: JsonSchema,
  submit_config: Option(SubmitConfig),
  show_readonly_fields: Bool,
  initial_values: Dict(String, Value),
) -> FormModel {
  let values_with_defaults =
    apply_schema_defaults(schema.properties, initial_values)
  FormModel(
    schema: schema,
    resolved_schema: schema,
    values: values_with_defaults,
    errors: dict.new(),
    is_submitting: False,
    is_dirty: False,
    is_valid: True,
    touched_fields: [],
    disabled_fields: [],
    submission_result: option.None,
    submit_config: submit_config,
    show_readonly_fields: show_readonly_fields,
    upload_base_url: option.None,
    upload_states: dict.new(),
  )
}

// Merge JSON Schema defaults into top-level form values. Existing non-null
// entries are preserved; missing or NullValue entries are filled from
// `property.default`. Recurses into ObjectValue / ArrayValue so partially
// hydrated nested structures get their missing leaves filled as well.
fn apply_schema_defaults(
  properties: List(#(String, SchemaProperty)),
  values: Dict(String, Value),
) -> Dict(String, Value) {
  list.fold(properties, values, fn(acc, pair) {
    let #(field_name, property) = pair
    // Top-level NullValue is treated as "absent" so a schema `default`
    // can fill it. This is intentional and applies only during init/reset
    // — runtime field updates flow through `UpdateFieldPath` and do not
    // re-enter this code, so explicit user clears (NullValue dispatched
    // from empty inputs) are not silently turned back into defaults.
    let current = case dict.get(acc, field_name) {
      Ok(NullValue) -> option.None
      Ok(v) -> option.Some(v)
      Error(_) -> option.None
    }
    case apply_defaults_to_value(property, current) {
      option.Some(v) -> dict.insert(acc, field_name, v)
      option.None -> acc
    }
  })
}

// Compute the post-default value for a single field. Returns None when the
// field has no current value and no schema default would produce one
// (so the caller leaves the key absent rather than inserting an empty hole).
fn apply_defaults_to_value(
  property: SchemaProperty,
  current: Option(Value),
) -> Option(Value) {
  case current {
    option.None -> defaults_for_missing(property)
    option.Some(ObjectValue(fields)) ->
      option.Some(merge_object_defaults(property, fields))
    option.Some(ArrayValue(items)) ->
      option.Some(map_array_item_defaults(property, items))
    option.Some(other) -> option.Some(other)
  }
}

// Build a value for a field that currently has nothing set:
// prefer `property.default`, otherwise synthesise an ObjectValue from
// sub-property defaults (so a missing nested object can still surface its
// inner defaults). Arrays are NOT auto-populated — without a hydrated
// array we cannot guess how many items to create.
fn defaults_for_missing(property: SchemaProperty) -> Option(Value) {
  case property.default {
    option.Some(d) -> option.Some(d)
    option.None ->
      case property.field_type, property.properties {
        option.Some(ObjectType), option.Some(sub_props) -> {
          let built =
            list.filter_map(sub_props, fn(pair) {
              let #(name, sub_prop) = pair
              case apply_defaults_to_value(sub_prop, option.None) {
                option.Some(v) -> Ok(#(name, v))
                option.None -> Error(Nil)
              }
            })
          case built {
            [] -> option.None
            _ -> option.Some(ObjectValue(built))
          }
        }
        _, _ -> option.None
      }
  }
}

// Recurse into an existing ObjectValue, filling missing sub-fields from
// their defaults. Schema-declared properties come first (preserving schema
// order), then any caller-supplied keys not declared in the schema are
// appended in their original order — this keeps additionalProperties /
// legacy fields from being silently dropped.
fn merge_object_defaults(
  property: SchemaProperty,
  fields: List(#(String, Value)),
) -> Value {
  case property.properties {
    option.Some(sub_props) -> {
      let merged = apply_schema_defaults(sub_props, dict.from_list(fields))
      let declared =
        list.filter_map(sub_props, fn(pair) {
          let #(name, _) = pair
          case dict.get(merged, name) {
            Ok(v) -> Ok(#(name, v))
            Error(_) -> Error(Nil)
          }
        })
      let declared_names = list.map(sub_props, fn(pair) { pair.0 })
      let extra =
        list.filter(fields, fn(pair) { !list.contains(declared_names, pair.0) })
      ObjectValue(list.append(declared, extra))
    }
    option.None -> ObjectValue(fields)
  }
}

// Recurse into each existing array item using the items-schema. We do not
// create new items — defaults only apply inside elements the caller
// already hydrated. `apply_defaults_to_value` is total for any
// `Some(_)` input, so we can `let assert` the result.
fn map_array_item_defaults(
  property: SchemaProperty,
  items: List(Value),
) -> Value {
  case property.items {
    option.Some(item_schema) ->
      ArrayValue(
        list.map(items, fn(item) {
          let assert option.Some(v) =
            apply_defaults_to_value(item_schema, option.Some(item))
          v
        }),
      )
    option.None -> ArrayValue(items)
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
    // Reset to base schema with no conditionals applied;
    // re-apply schema defaults to stay consistent with init.
    values: apply_schema_defaults(model.schema.properties, dict.new()),
    errors: dict.new(),
    is_submitting: False,
    is_dirty: False,
    is_valid: True,
    touched_fields: [],
    disabled_fields: [],
    submission_result: option.None,
    submit_config: model.submit_config,
    show_readonly_fields: model.show_readonly_fields,
    upload_base_url: model.upload_base_url,
    upload_states: dict.new(),
  )
}

/// Get all current form values as a dictionary.
///
/// Returns the complete set of form field values, including values from
/// inactive conditional branches. For filtered values that exclude hidden
/// fields, use `get_resolved_values` instead.
///
/// ## Parameters
/// - `model`: The form model containing field values
///
/// ## Returns
/// A dictionary mapping field names to their current values
pub fn get_form_values(model: FormModel) -> Dict(String, Value) {
  model.values
}

/// Get form values filtered by the current resolved schema.
///
/// Returns only values for fields present in `resolved_schema.properties`.
/// Fields from inactive conditional branches (if/then/else) are excluded.
/// Internal `model.values` is not modified — hidden field values are
/// preserved and will reappear if the condition toggles back.
pub fn get_resolved_values(model: FormModel) -> Dict(String, Value) {
  dict.filter(model.values, fn(key, _value) {
    has_property_key(model.resolved_schema.properties, key)
  })
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
    [path.PropertySegment(name)] ->
      dict.get(model.values, name) |> option.from_result
    [path.PropertySegment(name), ..rest] ->
      case dict.get(model.values, name) {
        Ok(types.ArrayValue(items)) -> traverse_array_path(items, rest)
        Ok(types.ObjectValue(obj)) -> traverse_object_path(obj, rest)
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

/// Check if a field at any depth is required by the current resolved schema.
///
/// Traverses `model.resolved_schema` along `field_path`, reading the
/// `required` list of each containing object/array-item. Top-level
/// `if/then/else` conditionals are already applied (root is resolved); item-level
/// conditionals inside `items.allOf` are not yet resolved here (PR 5).
///
/// Returns False for empty paths, paths that don't resolve to a property
/// (intermediate scalar, missing key), or paths starting with `ArraySegment`.
pub fn is_required_at_path(model: FormModel, field_path: FieldPath) -> Bool {
  required_in_node(
    model.resolved_schema.properties,
    model.resolved_schema.required,
    field_path,
  )
}

fn required_in_node(
  properties: List(#(String, SchemaProperty)),
  required: List(String),
  field_path: FieldPath,
) -> Bool {
  case field_path {
    [path.PropertySegment(name)] -> list.contains(required, name)
    [path.PropertySegment(name), path.PropertySegment(child), ..rest] ->
      case list.key_find(properties, name) {
        Ok(prop) ->
          case prop.properties {
            option.Some(sub) ->
              required_in_node(sub, prop.required, [
                path.PropertySegment(child),
                ..rest
              ])
            option.None -> False
          }
        Error(_) -> False
      }
    [path.PropertySegment(name), path.ArraySegment(_), ..rest] ->
      case list.key_find(properties, name) {
        Ok(prop) ->
          case prop.items {
            option.Some(items_schema) ->
              case items_schema.properties {
                option.Some(item_props) ->
                  required_in_node(item_props, items_schema.required, rest)
                option.None -> False
              }
            option.None -> False
          }
        Error(_) -> False
      }
    _ -> False
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
    Ok(errors) -> errors != []
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

/// Add a validation error to a field at the given path.
pub fn add_error_at_path(
  model: FormModel,
  field_path: FieldPath,
  error: ValidationError,
) -> FormModel {
  let path_key = path.to_string(field_path)
  let current = get_errors_at_path(model, field_path)
  let new_errors = list.append(current, [error])
  FormModel(
    ..model,
    errors: dict.insert(model.errors, path_key, new_errors),
    is_valid: False,
  )
}

/// Clear all validation errors for a field at the given path.
pub fn clear_errors_at_path(
  model: FormModel,
  field_path: FieldPath,
) -> FormModel {
  let path_key = path.to_string(field_path)
  let new_errors = dict.delete(model.errors, path_key)
  FormModel(..model, errors: new_errors, is_valid: dict.size(new_errors) == 0)
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
