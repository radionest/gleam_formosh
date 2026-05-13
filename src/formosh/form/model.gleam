// Form model for MVU architecture

import formosh/form/path.{type FieldPath}
import formosh/schema/types.{
  type JsonSchema, type SchemaProperty, type Value, ArrayValue, NullValue,
  ObjectType, ObjectValue, has_property_key,
}
import formosh/validation/error.{type ValidationError}
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
    // Current form values as a single hierarchical Value tree (always
    // ObjectValue at the root). All path-based reads and writes go through
    // `path.get_at_path` / `path.set_at_path` directly — no Dict↔Value
    // conversion in update handlers.
    values: Value,
    // Form validation errors
    errors: Dict(String, List(ValidationError)),
    // Form metadata
    is_submitting: Bool,
    is_dirty: Bool,
    is_valid: Bool,
    // Touched fields (for showing errors)
    touched_fields: List(FieldPath),
    // Disabled fields
    disabled_fields: List(FieldPath),
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
  // Public API still accepts a flat Dict of top-level values. Internally
  // we store one ObjectValue tree, so convert at the boundary and let the
  // (now Value-typed) defaults pass walk it like any nested object.
  let initial_value = ObjectValue(dict.to_list(initial_values))
  let values_with_defaults =
    apply_schema_defaults(schema.properties, initial_value)
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

// Merge JSON Schema defaults into a hierarchical Value. Each declared
// property is walked: existing non-null entries are kept; missing or
// NullValue entries are filled from `property.default` (or, for ObjectType,
// from a synthesised inner default tree). Caller-supplied keys not declared
// in the schema are preserved verbatim and appended after the declared
// block, matching the previous Dict-based ordering guarantee.
//
// Form storage is one ObjectValue tree by construction (init/reset build
// one; every handler writes Value back through `path.set_at_path`), so the
// `let assert` enforces the invariant: a scalar or array at the form root
// would be a programming error, not a runtime data shape we silently fall
// back to.
fn apply_schema_defaults(
  properties: List(#(String, SchemaProperty)),
  value: Value,
) -> Value {
  let assert ObjectValue(fields) = value
  ObjectValue(merge_property_defaults(properties, fields))
}

// Walk the declared properties in schema order, materialising each entry's
// post-default value, then append any extra keys (additionalProperties,
// legacy fields) in their original order. NullValue is treated as "absent"
// so a schema `default` can fill it — see `apply_schema_defaults` doc for
// why this only applies during init/reset.
fn merge_property_defaults(
  properties: List(#(String, SchemaProperty)),
  fields: List(#(String, Value)),
) -> List(#(String, Value)) {
  let declared =
    list.filter_map(properties, fn(pair) {
      let #(field_name, property) = pair
      let current = case list.key_find(fields, field_name) {
        Ok(NullValue) -> option.None
        Ok(v) -> option.Some(v)
        Error(_) -> option.None
      }
      case apply_defaults_to_value(property, current) {
        option.Some(v) -> Ok(#(field_name, v))
        option.None -> Error(Nil)
      }
    })
  let declared_names = list.map(properties, fn(pair) { pair.0 })
  let extras =
    list.filter(fields, fn(pair) { !list.contains(declared_names, pair.0) })
  list.append(declared, extras)
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
// their defaults. Delegates to `merge_property_defaults` so schema order
// and extra-key preservation are handled in a single place.
fn merge_object_defaults(
  property: SchemaProperty,
  fields: List(#(String, Value)),
) -> Value {
  case property.properties {
    option.Some(sub_props) ->
      ObjectValue(merge_property_defaults(sub_props, fields))
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

/// Check if a field at a path has been touched (focused and then blurred).
///
/// Touched state is keyed by `FieldPath` so nested fields can be tracked
/// without ambiguity. Use the field's full path including any
/// `ArraySegment`/`PropertySegment` chain leading up to it.
pub fn is_field_touched(model: FormModel, field_path: FieldPath) -> Bool {
  list.contains(model.touched_fields, field_path)
}

/// Check if a field at a path is currently disabled.
pub fn is_field_disabled(model: FormModel, field_path: FieldPath) -> Bool {
  list.contains(model.disabled_fields, field_path)
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

/// Mark a field at the given path as touched.
pub fn mark_field_touched(model: FormModel, field_path: FieldPath) -> FormModel {
  case is_field_touched(model, field_path) {
    True -> model
    False ->
      FormModel(
        ..model,
        touched_fields: list.append(model.touched_fields, [field_path]),
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
    values: apply_schema_defaults(model.schema.properties, ObjectValue([])),
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

/// Get the full hierarchical form values.
///
/// Returns the complete `Value` tree (always rooted at `ObjectValue`),
/// including values from inactive conditional branches. For filtered
/// values that exclude top-level hidden fields, use `get_resolved_values`.
///
/// ## Parameters
/// - `model`: The form model containing field values
pub fn get_form_values(model: FormModel) -> Value {
  model.values
}

/// Get form values filtered by the current resolved schema.
///
/// Filters the root `ObjectValue` to only include top-level fields that
/// are present in `resolved_schema.properties`. Fields from inactive
/// top-level if/then/else branches are excluded. Nested inactive
/// conditional fields are NOT yet filtered — that requires resolved
/// schemas at every nesting level (planned for the recursive-nested PR 5).
/// Internal `model.values` is not modified, so hidden values reappear
/// if the condition toggles back.
pub fn get_resolved_values(model: FormModel) -> Value {
  case model.values {
    ObjectValue(fields) ->
      ObjectValue(
        list.filter(fields, fn(pair) {
          has_property_key(model.resolved_schema.properties, pair.0)
        }),
      )
    other -> other
  }
}

/// Get the value at a specific path in the form.
///
/// Delegates to `path.get_at_path` against the single hierarchical
/// `model.values` tree.
///
/// ## Returns
/// - `Some(Value)` if a value exists at the path
/// - `None` if the path doesn't exist or is empty
pub fn get_value_at_path(
  model: FormModel,
  field_path: FieldPath,
) -> Option(Value) {
  case field_path {
    [] -> option.None
    _ -> path.get_at_path(model.values, field_path)
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
