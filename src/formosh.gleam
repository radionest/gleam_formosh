// Main module for Formosh - JSON Schema based form generator

import form/model.{
  type FormModel, type FormMsg, type SubmitConfig, CustomSubmit, HttpSubmit,
  NoSubmit,
}
import form/update
import form/view
import gleam/dict.{type Dict}
import gleam/option
import lustre
import lustre/effect
import schema/parser
import schema/types.{type JsonSchema, type Value}

/// Configuration options for creating a form.
///
/// This type contains all the configuration needed to create a form,
/// including the schema and submission handling.
pub type FormConfig {
  FormConfig(
    schema: JsonSchema,
    submit_config: SubmitConfig,
    /// Optional CSS class prefix for styling
    css_prefix: String,
    /// Whether to show validation errors immediately or only after blur
    show_errors_on_change: Bool,
    /// Whether to display readOnly fields (default: False - hidden)
    show_readonly_fields: Bool,
    /// Initial values to populate the form with
    initial_values: Dict(String, Value),
  )
}

/// Create a form configuration with default settings.
/// 
/// This is a convenience function for creating a basic form configuration
/// with sensible defaults.
/// 
/// ## Parameters
/// - `schema`: The JSON Schema definition for the form
/// 
/// ## Returns
/// A FormConfig with default settings (no submission handler, standard CSS prefix)
/// 
/// ## Example
/// ```gleam
/// let config = formosh.config(schema)
///   |> formosh.with_submit_url("https://api.example.com/submit")
/// ```
pub fn config(schema: JsonSchema) -> FormConfig {
  FormConfig(
    schema: schema,
    submit_config: NoSubmit,
    css_prefix: "formosh",
    show_errors_on_change: False,
    show_readonly_fields: False,
    initial_values: dict.new(),
  )
}

/// Add an HTTP submission handler to the form configuration.
/// 
/// ## Parameters
/// - `config`: The form configuration to update
/// - `url`: The URL to submit the form to
/// 
/// ## Returns
/// Updated FormConfig with HTTP submission
pub fn with_submit_url(config: FormConfig, url: String) -> FormConfig {
  FormConfig(
    ..config,
    submit_config: HttpSubmit(url: url, method: "POST", headers: [
      #("Content-Type", "application/json"),
    ]),
  )
}

/// Add an HTTP submission handler with custom method and headers.
/// 
/// ## Parameters
/// - `config`: The form configuration to update
/// - `url`: The URL to submit the form to
/// - `method`: HTTP method (GET, POST, PUT, etc.)
/// - `headers`: List of HTTP headers
/// 
/// ## Returns
/// Updated FormConfig with custom HTTP submission
pub fn with_http_submit(
  config: FormConfig,
  url: String,
  method: String,
  headers: List(#(String, String)),
) -> FormConfig {
  FormConfig(
    ..config,
    submit_config: HttpSubmit(url: url, method: method, headers: headers),
  )
}

/// Add a custom submission handler function.
/// 
/// ## Parameters
/// - `config`: The form configuration to update
/// - `handler`: Function that processes form submission
/// 
/// ## Returns
/// Updated FormConfig with custom submission handler
pub fn with_custom_submit(
  config: FormConfig,
  handler: fn(model.FormModel) -> Result(String, String),
) -> FormConfig {
  FormConfig(..config, submit_config: CustomSubmit(handler: handler))
}

/// Set the CSS class prefix for form elements.
/// 
/// ## Parameters
/// - `config`: The form configuration to update
/// - `prefix`: The CSS class prefix to use
/// 
/// ## Returns
/// Updated FormConfig with new CSS prefix
pub fn with_css_prefix(config: FormConfig, prefix: String) -> FormConfig {
  FormConfig(..config, css_prefix: prefix)
}

/// Configure whether to show validation errors immediately on change.
///
/// ## Parameters
/// - `config`: The form configuration to update
/// - `show`: Whether to show errors on change (true) or only on blur (false)
///
/// ## Returns
/// Updated FormConfig with error display setting
pub fn with_show_errors_on_change(config: FormConfig, show: Bool) -> FormConfig {
  FormConfig(..config, show_errors_on_change: show)
}

/// Configure whether to show readOnly fields in the form.
///
/// By default, readOnly fields are hidden from the user. When enabled,
/// they are displayed as readonly inputs that cannot be edited.
///
/// ## Parameters
/// - `config`: The form configuration to update
/// - `show`: Whether to show readOnly fields (true) or hide them (false)
///
/// ## Returns
/// Updated FormConfig with readOnly display setting
pub fn with_show_readonly_fields(config: FormConfig, show: Bool) -> FormConfig {
  FormConfig(..config, show_readonly_fields: show)
}

/// Set initial values for form fields.
///
/// These values will be used to pre-populate form fields, including
/// readOnly fields that are filled programmatically.
///
/// ## Parameters
/// - `config`: The form configuration to update
/// - `values`: Dictionary of field names to their initial values
///
/// ## Returns
/// Updated FormConfig with initial values
///
/// ## Example
/// ```gleam
/// let config = formosh.config(schema)
///   |> formosh.with_initial_values(dict.from_list([
///     #("patient_id", StringValue("12345")),
///     #("study_date", StringValue("2024-01-15")),
///   ]))
/// ```
pub fn with_initial_values(
  config: FormConfig,
  values: Dict(String, Value),
) -> FormConfig {
  FormConfig(..config, initial_values: values)
}

/// Create a form application from a JSON Schema definition.
/// 
/// This is the main entry point for creating forms. It takes a parsed JSON Schema
/// and returns a FormApp that can be converted to a Lustre application.
/// 
/// ## Example
/// ```gleam
/// let schema = JsonSchema(...)
/// let app = formosh.from_schema(schema)
/// lustre.start(app, "#form-container", Nil)
/// ```
pub fn from_schema(schema: JsonSchema) -> lustre.App(Nil, FormModel, FormMsg) {
  let default_config = config(schema)
  from_config(default_config)
}

/// Create a form application from a configuration.
/// 
/// This function creates a form with custom configuration including
/// submission handling and display options.
/// 
/// ## Parameters
/// - `config`: The form configuration
/// 
/// ## Returns
/// A Lustre application ready to be started
/// 
/// ## Example
/// ```gleam
/// let config = formosh.config(schema)
///   |> formosh.with_submit_url("https://api.example.com/submit")
///   |> formosh.with_css_prefix("my-form")
/// let app = formosh.from_config(config)
/// lustre.start(app, "#form-container", Nil)
/// ```
pub fn from_config(config: FormConfig) -> lustre.App(Nil, FormModel, FormMsg) {
  create_form_with_config(config)
}

/// Internal function to create a Lustre application from a configuration.
///
/// This function sets up the MVU architecture by providing the init, update,
/// and view functions needed for a Lustre application.
fn create_form_with_config(
  config: FormConfig,
) -> lustre.App(Nil, FormModel, FormMsg) {
  lustre.application(
    fn(_) {
      #(
        model.init_with_full_config(
          config.schema,
          option.Some(config.submit_config),
          config.show_readonly_fields,
          config.initial_values,
        ),
        effect.none(),
      )
    },
    update.update,
    view.view,
  )
}

/// Create a form application from a JSON Schema string.
/// 
/// This is a convenience function that combines JSON parsing and form creation.
/// It takes a JSON string containing a valid JSON Schema and returns either
/// a FormApp or a parsing error.
/// 
/// ## Parameters
/// - `json_string`: A valid JSON string containing a JSON Schema definition
/// 
/// ## Returns
/// - `Ok(lustre.App)` if the JSON was valid and could be converted to a form
/// - `Error(ParseError)` if the JSON was invalid or couldn't be parsed
/// 
/// ## Example
/// ```gleam
/// let json = "{\"title\": \"My Form\", \"type\": \"object\", ...}"
/// case formosh.from_json_string(json) {
///   Ok(app) -> lustre.start(app, "#form-container", Nil)
///   Error(parse_error) -> // Handle parsing error
/// }
/// ```
pub fn from_json_string(
  json_string: String,
) -> Result(lustre.App(Nil, FormModel, FormMsg), parser.ParseError) {
  case parser.parse_schema(json_string) {
    Ok(schema) -> Ok(from_schema(schema))
    Error(err) -> Error(err)
  }
}

/// Create a form application from a JSON string with configuration.
/// 
/// Combines JSON parsing with custom configuration options.
/// 
/// ## Parameters
/// - `json_string`: A valid JSON string containing a JSON Schema definition
/// - `submit_config`: Submission configuration for the form
/// 
/// ## Returns
/// - `Ok(lustre.App)` if successful
/// - `Error(ParseError)` if JSON parsing fails
pub fn from_json_string_with_config(
  json_string: String,
  submit_config: SubmitConfig,
) -> Result(lustre.App(Nil, FormModel, FormMsg), parser.ParseError) {
  case parser.parse_schema(json_string) {
    Ok(schema) -> {
      let form_config =
        FormConfig(
          schema: schema,
          submit_config: submit_config,
          css_prefix: "formosh",
          show_errors_on_change: False,
          show_readonly_fields: False,
          initial_values: dict.new(),
        )
      Ok(from_config(form_config))
    }
    Error(err) -> Error(err)
  }
}

/// Get all current form values.
/// 
/// ## Parameters
/// - `model`: The form model
/// 
/// ## Returns
/// Dictionary of field names to their current values
pub fn get_values(model: model.FormModel) -> dict.Dict(String, types.Value) {
  model.values
}
