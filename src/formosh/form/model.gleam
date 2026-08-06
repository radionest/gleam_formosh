// Form model for MVU architecture

import formosh/form/defaults
import formosh/form/path.{type FieldPath}
import formosh/form/union_resolver
import formosh/form/visibility
import formosh/form/widget_msg.{
  type ExitDir, type ImageUploadEvent, type SwipeReviewEvent, type WidgetMsg,
}
import formosh/schema/conditional_resolver
import formosh/schema/properties
import formosh/schema/types.{
  type JsonSchema, type SchemaProperty, type Value, ObjectValue,
}
import formosh/schema/ui_schema.{type UiSchema, empty_ui_schema}
import formosh/validation/cross_validator.{type Validator}
import formosh/validation/error.{type ValidationError}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option}
import gleam/set.{type Set}
import gleam/string

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
    // Active union branch per field path. Mirrors touched_fields: FieldPath
    // keys reindex with the same path helpers on array remove/move.
    selected_branches: List(#(FieldPath, Int)),
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
    // Presentation settings parallel to `schema`. `ui_resolver.resolve_hints`
    // merges this with each `SchemaProperty.render_hints` at render time.
    ui_schema: UiSchema,
    // Optional cross-field custom validator. Invoked at the end of
    // `update.validate_all_fields` after the schema-driven passes; its
    // errors are merged into `errors` via `add_error_at_path`.
    validator: Option(Validator(FormModel)),
    // Whether the whole form renders as a static, non-editable summary
    // (label → value) instead of input widgets. Set via the component's
    // `read-only` attribute. Distinct from `show_readonly_fields`, which
    // only toggles visibility of schema `readOnly` fields in edit mode.
    read_only: Bool,
    // Transient swipe-review drag state (None unless a row is being dragged).
    swipe_drag: Option(SwipeDrag),
    // Swipe-review view mode: True hides answered zones (shrinking sheet),
    // False keeps every zone visible and editable. Default True.
    swipe_hide_answered: Bool,
    // Swipe-review cards committed but still animating off-screen (any order).
    // Each is kept rendered (flying off) until its `transitionend` clears it.
    // Only populated in hide-answered mode. Empty unless a fly-off is in flight.
    swipe_exiting: List(#(FieldPath, ExitDir)),
  )
}

/// State of a file upload in progress.
pub type FileUploadState {
  FileUploading(temp_id: String, preview_url: String)
  FileUploadError(temp_id: String, error: String)
}

/// Transient state of an in-progress horizontal swipe on a swipe-review zone
/// row. Held on the model only while a drag is active; cleared on release.
/// `dx` is the live offset (current pointer X minus `start_x`); a release with
/// `dx >= threshold` commits `pos_code`, `dx <= -threshold` commits `neg_code`.
pub type SwipeDrag {
  SwipeDrag(
    path: FieldPath,
    start_x: Float,
    dx: Float,
    pos_code: String,
    neg_code: String,
    threshold: Float,
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
  ClearFieldPath(path: FieldPath)
  AddArrayItemPath(path: FieldPath)
  RemoveArrayItemPath(path: FieldPath, index: Int)
  MoveArrayItemPath(path: FieldPath, from_index: Int, to_index: Int)
  SelectUnionBranchPath(path: FieldPath, index: Int)

  // Form submission
  FormSubmit
  FormSubmitted(Result(String, String))

  // Validation
  ValidateForm

  // Reset form
  ResetForm

  // Widget-specific events (image-upload today; more in v0.8 widget registry)
  WidgetEvent(WidgetMsg)
}

/// Build a `FormMsg` from an `ImageUploadEvent` — collapses the
/// `WidgetEvent(ImageUpload(...))` wrapper at emission sites.
pub fn image_msg(event: ImageUploadEvent) -> FormMsg {
  WidgetEvent(widget_msg.ImageUpload(event))
}

/// Build a `FormMsg` from a `SwipeReviewEvent` — collapses the
/// `WidgetEvent(SwipeReview(...))` wrapper at emission sites.
pub fn swipe_msg(event: SwipeReviewEvent) -> FormMsg {
  WidgetEvent(widget_msg.SwipeReview(event))
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
  init_with_full_config(
    schema,
    submit_config,
    False,
    dict.new(),
    empty_ui_schema(),
  )
}

/// Initialize a new form model with full configuration including readOnly and initial values.
///
/// Creates a form with all configuration options.
///
/// ## Parameters
/// - `schema`: The JSON Schema definition for this form
/// - `submit_config`: Optional submission configuration
/// - `show_readonly_fields`: Whether to display readOnly fields
/// - `initial_values`: Initial values keyed by **top-level property name**.
///   Keys are not dot-notation paths — `"user.name"` is treated as a single
///   top-level key, not unflattened. For nested fields, supply nested
///   `Value` trees, e.g. `ObjectValue([#("name", StringValue("..."))])`.
///
/// ## Returns
/// A new FormModel with the provided configuration
pub fn init_with_full_config(
  schema: JsonSchema,
  submit_config: Option(SubmitConfig),
  show_readonly_fields: Bool,
  initial_values: Dict(String, Value),
  ui_schema: UiSchema,
) -> FormModel {
  // Public API still accepts a flat Dict of top-level values. Internally
  // we store one ObjectValue tree, so convert at the boundary and let the
  // (now Value-typed) defaults pass walk it like any nested object.
  let initial_value = ObjectValue(dict.to_list(initial_values))
  let values_with_defaults =
    defaults.apply_schema_defaults(schema.properties, initial_value)
    |> defaults.ensure_min_items(schema.properties, _, [])
  FormModel(
    schema: schema,
    resolved_schema: schema,
    values: values_with_defaults,
    errors: dict.new(),
    is_submitting: False,
    is_dirty: False,
    is_valid: True,
    touched_fields: [],
    selected_branches: [],
    disabled_fields: [],
    submission_result: option.None,
    submit_config: submit_config,
    show_readonly_fields: show_readonly_fields,
    upload_base_url: option.None,
    upload_states: dict.new(),
    ui_schema: ui_schema,
    validator: option.None,
    read_only: False,
    swipe_drag: option.None,
    swipe_hide_answered: True,
    swipe_exiting: [],
  )
}

/// Recompute `resolved_schema` for a schema/values/selected-branches triple.
///
/// The single entry point for every `resolved_schema` recompute site: union
/// resolution runs first, materializing each `any_of` node to its active
/// branch (stored `selected` entry, else inferred from `values`, else
/// branch 0), then conditional resolution (`if/then/else`) sees the
/// materialized branches — a conditional declared inside the active branch
/// must see it already materialized (design D4).
pub fn recompute_resolved_schema(
  schema: JsonSchema,
  values: Value,
  selected: List(#(FieldPath, Int)),
) -> JsonSchema {
  union_resolver.resolve_form_schema(schema, values, selected)
  |> conditional_resolver.resolve_recursive(values)
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
  // Re-apply schema defaults to stay consistent with init, then
  // materialize `resolved_schema` through the same wrapper every other
  // recompute site uses (union resolution + conditionals) — with no stored
  // selection, each union node falls back to its branch-0 default (design
  // D8) instead of staying raw.
  let reset_values =
    defaults.apply_schema_defaults(model.schema.properties, ObjectValue([]))
    |> defaults.ensure_min_items(model.schema.properties, _, [])
  let resolved_schema =
    recompute_resolved_schema(model.schema, reset_values, [])
  FormModel(
    schema: model.schema,
    resolved_schema: resolved_schema,
    values: reset_values,
    errors: dict.new(),
    is_submitting: False,
    is_dirty: False,
    is_valid: True,
    touched_fields: [],
    selected_branches: [],
    disabled_fields: [],
    submission_result: option.None,
    submit_config: model.submit_config,
    show_readonly_fields: model.show_readonly_fields,
    upload_base_url: model.upload_base_url,
    upload_states: dict.new(),
    ui_schema: model.ui_schema,
    validator: model.validator,
    read_only: model.read_only,
    swipe_drag: option.None,
    swipe_hide_answered: True,
    swipe_exiting: [],
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
          properties.has_key(model.resolved_schema.properties, pair.0)
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
  props: List(#(String, SchemaProperty)),
  required: List(String),
  field_path: FieldPath,
) -> Bool {
  case field_path {
    [path.PropertySegment(name)] -> list.contains(required, name)
    [path.PropertySegment(name), path.PropertySegment(child), ..rest] ->
      case properties.get(props, name) {
        option.Some(prop) ->
          case prop.properties {
            option.Some(sub) ->
              required_in_node(sub, prop.required, [
                path.PropertySegment(child),
                ..rest
              ])
            option.None -> False
          }
        option.None -> False
      }
    [path.PropertySegment(name), path.ArraySegment(_), ..rest] ->
      case properties.get(props, name) {
        option.Some(prop) ->
          case prop.items {
            option.Some(items_schema) ->
              case items_schema.properties {
                option.Some(item_props) ->
                  required_in_node(item_props, items_schema.required, rest)
                option.None -> False
              }
            option.None -> False
          }
        option.None -> False
      }
    _ -> False
  }
}

/// Resolve the `SchemaProperty` at any depth in the current resolved schema.
///
/// Walks `model.resolved_schema.properties` along `field_path`, descending
/// into `prop.properties` for `PropertySegment` and into `prop.items` for
/// `ArraySegment`. Returns `Error(Nil)` for empty paths, paths starting
/// with `ArraySegment`, or paths that don't land on a declared property
/// (missing key, or a scalar/array property without further structure).
///
/// Useful for any feature that needs the schema metadata of a nested
/// field — e.g. resolving `upload_config` for `image-upload` widgets that
/// live inside array items or nested objects.
pub fn find_property_at_path(
  model: FormModel,
  field_path: FieldPath,
) -> Result(SchemaProperty, Nil) {
  lookup_property(model.resolved_schema.properties, field_path)
}

fn lookup_property(
  props: List(#(String, SchemaProperty)),
  field_path: FieldPath,
) -> Result(SchemaProperty, Nil) {
  case field_path {
    [path.PropertySegment(name), ..rest] ->
      case properties.get(props, name) {
        option.Some(prop) -> walk_into_property(prop, rest)
        option.None -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn walk_into_property(
  property: SchemaProperty,
  rest: FieldPath,
) -> Result(SchemaProperty, Nil) {
  case rest {
    [] -> Ok(property)
    [path.PropertySegment(_), ..] ->
      case property.properties {
        option.Some(sub) -> lookup_property(sub, rest)
        option.None -> Error(Nil)
      }
    [path.ArraySegment(_), ..rest_after_array] ->
      case property.items {
        option.Some(items_schema) ->
          walk_into_property(items_schema, rest_after_array)
        option.None -> Error(Nil)
      }
  }
}

/// Like `find_property_at_path`, but resolves item-level unions and
/// conditionals against the actual row values while crossing each
/// `ArraySegment` (union first, then conditionals — design D4), so
/// properties revealed by a per-row `anyOf`/`if-then` (e.g. a
/// union-materialized nested array) are found. Falls back to the unresolved
/// item schema when the row value is absent.
pub fn find_resolved_property_at_path(
  model: FormModel,
  field_path: FieldPath,
) -> Result(SchemaProperty, Nil) {
  lookup_property_resolved(
    model.resolved_schema.properties,
    option.Some(model.values),
    [],
    field_path,
    model.selected_branches,
  )
}

fn lookup_property_resolved(
  props: List(#(String, SchemaProperty)),
  value: Option(Value),
  parent_path: FieldPath,
  field_path: FieldPath,
  selected: List(#(FieldPath, Int)),
) -> Result(SchemaProperty, Nil) {
  case field_path {
    [path.PropertySegment(name), ..rest] ->
      case properties.get(props, name) {
        option.Some(prop) -> {
          let child_value = case value {
            option.Some(ObjectValue(fields)) ->
              option.from_result(list.key_find(fields, name))
            _ -> option.None
          }
          let node_path = list.append(parent_path, [path.PropertySegment(name)])
          walk_into_property_resolved(
            prop,
            child_value,
            node_path,
            rest,
            selected,
          )
        }
        option.None -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn walk_into_property_resolved(
  property: SchemaProperty,
  value: Option(Value),
  node_path: FieldPath,
  rest: FieldPath,
  selected: List(#(FieldPath, Int)),
) -> Result(SchemaProperty, Nil) {
  case rest {
    [] -> Ok(property)
    [path.PropertySegment(_), ..] ->
      case property.properties {
        option.Some(sub) ->
          lookup_property_resolved(sub, value, node_path, rest, selected)
        option.None -> Error(Nil)
      }
    [path.ArraySegment(index), ..rest_after_array] ->
      case property.items {
        option.Some(items_schema) -> {
          let row_value = case value {
            option.Some(v) -> path.get_at_path(v, [path.ArraySegment(index)])
            option.None -> option.None
          }
          let item_path = list.append(node_path, [path.ArraySegment(index)])
          let resolved = case row_value {
            option.Some(row) ->
              union_resolver.resolve_effective_property(
                items_schema,
                row,
                item_path,
                selected,
              )
            option.None -> items_schema
          }
          walk_into_property_resolved(
            resolved,
            row_value,
            item_path,
            rest_after_array,
            selected,
          )
        }
        option.None -> Error(Nil)
      }
  }
}

/// Augment `selected_branches` with the inferred branch for every ancestor
/// union along `edited_path` (including the path itself) that has no
/// stored selection yet — computed against the model's CURRENT (pre-edit)
/// state. Post-PR review finding 3 (PR #88, approved change to design D8):
/// a user-driven edit (`UpdateFieldPath`/`ClearFieldPath`) persists the
/// branch inference was already showing, so a later edit that empties the
/// value driving that inference doesn't snap the chooser back to branch 0.
/// Programmatic paths (init, `apply_answers`, component re-init) do not
/// call this — they keep inferring fresh on every resolution, preserving
/// D8's re-init idempotency for those call sites.
///
/// Each prefix is resolved via `find_resolved_property_at_path` (not the
/// plain, non-per-row `find_property_at_path`) so a union nested inside an
/// array row is handled the same as a plain object path. `active_branch_index`
/// is always fed the fixed `model.selected_branches` snapshot — not the
/// accumulator — matching "inferred on the PRE-EDIT state"; this is
/// equivalent to threading the accumulator through since every prefix is a
/// distinct `FieldPath` key, but states the pre-edit intent directly.
pub fn persist_inferred_branches(
  model: FormModel,
  edited_path: FieldPath,
) -> List(#(FieldPath, Int)) {
  list.fold(
    path_prefixes(edited_path),
    model.selected_branches,
    fn(acc, prefix) {
      case list.key_find(model.selected_branches, prefix) {
        Ok(_) -> acc
        Error(_) ->
          case find_resolved_property_at_path(model, prefix) {
            Ok(prop) ->
              case prop.any_of {
                option.Some([_, _, ..]) -> {
                  let value = get_value_at_path(model, prefix)
                  let index =
                    union_resolver.active_branch_index(
                      prop,
                      value,
                      prefix,
                      model.selected_branches,
                    )
                  list.key_set(acc, prefix, index)
                }
                _ -> acc
              }
            Error(_) -> acc
          }
      }
    },
  )
}

/// All non-empty prefixes of `field_path`, ancestor-to-leaf, including the
/// full path itself: `[a, b, c]` -> `[[a], [a, b], [a, b, c]]`.
fn path_prefixes(field_path: FieldPath) -> List(FieldPath) {
  case field_path {
    [] -> []
    [segment, ..rest] -> [
      [segment],
      ..list.map(path_prefixes(rest), fn(p) { [segment, ..p] })
    ]
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

/// True when any recorded error lies at `prefix` or beneath it.
///
/// `has_errors_at_path` is an exact-match lookup; this scans the whole error
/// map structurally through each error's own `FieldPath`, so it catches
/// errors on nested fields of a subtree — including ones a cross-field
/// validator recorded, which the schema validator never produced.
pub fn has_errors_under_path(model: FormModel, prefix: FieldPath) -> Bool {
  dict.values(model.errors)
  |> list.any(fn(errors) {
    list.any(errors, fn(err) { path.is_prefix_of(prefix, err.field) })
  })
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

/// Remove every value, error, and touched entry rooted at `field_path` —
/// the reset step behind switching a union branch (`SelectUnionBranchPath`
/// in `update.gleam`): the previous branch's data must not leak into the
/// new branch's inferred defaults, its validation, or a submitted payload.
///
/// - `values`: delegates to `clear_subtree_values`, which picks between two
///   value-tree operations depending on `field_path`'s final segment — see
///   its doc for why a single `path.remove_at_path` call isn't enough.
/// - `errors` / `touched_fields`: flat collections keyed independently per
///   path, so each descendant entry has to be filtered out on its own —
///   `errors` by canonical-string key (`is_error_key_under_path`),
///   `touched_fields` by structural `FieldPath` list-prefix
///   (`has_path_prefix`). These are two different mechanisms; see each
///   helper's doc. Both already handle an `ArraySegment`-terminated
///   `field_path` correctly (index-aware matching), so — unlike `values` —
///   they need no corresponding split.
pub fn clear_subtree(model: FormModel, field_path: FieldPath) -> FormModel {
  let new_errors =
    dict.filter(model.errors, fn(key, _errors) {
      !is_error_key_under_path(key, field_path)
    })
  FormModel(
    ..model,
    values: clear_subtree_values(model, field_path),
    errors: new_errors,
    touched_fields: list.filter(model.touched_fields, fn(touched) {
      !has_path_prefix(field_path, touched)
    }),
    is_valid: dict.size(new_errors) == 0,
  )
}

/// Value-tree half of `clear_subtree`. A `PropertySegment`-terminated path
/// (a union nested under an object key) deletes the whole subtree via
/// `path.remove_at_path` in one step, exactly as before.
///
/// An `ArraySegment`-terminated path is different: it names a union that
/// IS an array's item schema directly (`items: {"anyOf": [...]}`, no
/// object wrapper in between), so there is no key to drop —
/// `path.remove_at_path` no-ops on this shape by design (path.gleam
/// ~:160). Deleting the row outright isn't an option either: array rows
/// carry no identity beyond their index, so removing one would shift every
/// later sibling's index, corrupting *its* selection/errors/touched state
/// — the exact corruption `RemoveArrayItemPath`'s reindexing (D9) exists to
/// prevent. The row is reset in place instead, via `array_row_reset_value`.
fn clear_subtree_values(model: FormModel, field_path: FieldPath) -> Value {
  case list.reverse(field_path) {
    [path.ArraySegment(_), ..rev_array_path] -> {
      let array_path = list.reverse(rev_array_path)
      path.set_at_path(
        model.values,
        field_path,
        array_row_reset_value(model, array_path),
      )
    }
    _ -> path.remove_at_path(model.values, field_path)
  }
}

/// The array-row equivalent of "absent": look up the row's array `items`
/// schema at `array_path` (via `find_resolved_property_at_path`, the same
/// resolved lookup `AddArrayItemPath`'s handler uses to find an array's
/// item schema) and build a fresh row from it with `defaults.new_array_item`
/// — the same helper `AddArrayItemPath` and `ensure_min_items` already use,
/// so a switched-away row looks exactly like a row nobody has touched yet,
/// whether the active branch was a scalar (-> `NullValue`) or an object
/// with its own field defaults. Falls back to `NullValue` — the same
/// fallback `new_array_item` itself uses for a schema-less/non-object item
/// — when the array's schema can't be resolved (should not happen for a
/// real `SelectUnionBranchPath` dispatch, but `clear_subtree` must stay
/// total).
fn array_row_reset_value(model: FormModel, array_path: FieldPath) -> Value {
  case find_resolved_property_at_path(model, array_path) {
    Ok(prop) ->
      case prop.items {
        option.Some(item_schema) -> defaults.new_array_item(item_schema)
        option.None -> types.NullValue
      }
    Error(_) -> types.NullValue
  }
}

/// True when `candidate` is `prefix` itself or a structural descendant of
/// it — e.g. `[value]` prefixes both `[value]` and `[value, city]`. Used
/// for `touched_fields`, which is keyed by `FieldPath`, not by string.
fn has_path_prefix(prefix: FieldPath, candidate: FieldPath) -> Bool {
  case prefix, candidate {
    [], _ -> True
    [p, ..prefix_rest], [c, ..candidate_rest] ->
      p == c && has_path_prefix(prefix_rest, candidate_rest)
    _, _ -> False
  }
}

/// True when the canonical `path.to_string` key `key` names `prefix`
/// itself or a descendant of it: `key == path.to_string(prefix)`, or `key`
/// continues past it with the `"."` join character. `path.to_string`
/// (`formosh/path_format` owns the canonical format) separates every
/// segment — property or array-index alike — with `"."`, so this single
/// check covers both a nested property (`"value.city"`) and a nested array
/// index (`"value.[0]"`); never re-implement the segment join here.
fn is_error_key_under_path(key: String, prefix: FieldPath) -> Bool {
  let prefix_key = path.to_string(prefix)
  key == prefix_key || string.starts_with(key, prefix_key <> ".")
}

/// Check if the form can be submitted.
///
/// A form can be submitted if it is valid (no validation errors) and not
/// currently being submitted. `is_dirty` is **not** checked — a form with
/// valid defaults can be submitted without any user interaction.
///
/// Strict gate: any error blocks submit, including errors on UI-suppressed
/// paths (`x-widget: "hidden"`, `readOnly` with `show_readonly_fields:
/// False`). Callers that want a permissive variant — ignoring errors a user
/// cannot see — should consult `is_valid_for_submit` instead.
///
/// ## Parameters
/// - `model`: The form model to check
///
/// ## Returns
/// True if the form can be submitted, False otherwise
pub fn can_submit(model: FormModel) -> Bool {
  model.is_valid && !model.is_submitting
}

/// Compute the set of canonical path keys whose fields are suppressed from
/// the UI for the current `resolved_schema` / `ui_schema` / `values`.
///
/// Delegates to `visibility.invisible_paths`. Computed on demand — there is
/// no cached field on `FormModel`. When a single code path needs both
/// `is_valid_for_submit` and `hidden_errors` (as
/// `update.warn_only_hidden_blocks_effect` does), call this once and feed the
/// result to `is_valid_for_submit_with` / `hidden_errors_with` to avoid
/// walking the schema twice.
pub fn invisible_paths(model: FormModel) -> Set(String) {
  visibility.invisible_paths(
    model.resolved_schema,
    model.ui_schema,
    model.values,
    model.show_readonly_fields,
  )
}

/// Errors keyed by canonical path that fall on UI-suppressed fields.
///
/// Formats the diagnostic `console.warn` for a submit blocked solely by
/// required-errors a user cannot address. The submit flow itself calls
/// `hidden_errors_with` (sharing one walker pass with `is_valid_for_submit_with`
/// inside `update.warn_only_hidden_blocks_effect`); this standalone variant
/// computes its own invisible-paths set for external callers.
pub fn hidden_errors(model: FormModel) -> Dict(String, List(ValidationError)) {
  hidden_errors_with(model, invisible_paths(model))
}

/// Variant of `hidden_errors` that takes a pre-computed invisible-paths set.
///
/// Use this when both `is_valid_for_submit_with` and `hidden_errors_with`
/// are called in the same flow — share one walker invocation between them.
pub fn hidden_errors_with(
  model: FormModel,
  invisible: Set(String),
) -> Dict(String, List(ValidationError)) {
  dict.filter(model.errors, fn(key, _errors) { set.contains(invisible, key) })
}

/// Permissive submit gate — `True` when every error a user can see is clear.
///
/// Errors on UI-suppressed paths are ignored. This is the opt-in alternative
/// to `can_submit` for callers who want submit to proceed when the only
/// remaining blockers are out of reach for the user (e.g. backend supplies
/// the hidden value, not the JSON Schema).
pub fn is_valid_for_submit(model: FormModel) -> Bool {
  is_valid_for_submit_with(model, invisible_paths(model))
}

/// Variant of `is_valid_for_submit` that takes a pre-computed invisible
/// paths set. See `hidden_errors_with`.
pub fn is_valid_for_submit_with(
  model: FormModel,
  invisible: Set(String),
) -> Bool {
  case model.is_submitting {
    True -> False
    False -> {
      let visible_errors =
        dict.filter(model.errors, fn(key, _errors) {
          !set.contains(invisible, key)
        })
      dict.is_empty(visible_errors)
    }
  }
}
