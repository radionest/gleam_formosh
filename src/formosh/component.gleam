// Reusable form component for Formosh
// This module provides a Lustre component that can be embedded in applications
// with configurable submission endpoint and other properties.

import formosh/internal/component_core as core
import formosh/schema/serializer
import formosh/schema/types.{type JsonSchema, type Value}
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import lustre
import lustre/attribute.{type Attribute}
import lustre/component
import lustre/element.{type Element}
import lustre/event

// COMPONENT CONFIGURATION -----------------------------------------------------

/// Register the form component as a Web Component.
/// 
/// This allows the component to be used as a custom HTML element:
/// ```html
/// <formosh-form 
///   schema='{"type": "object", ...}'
///   submit-url="https://api.example.com/submit">
/// </formosh-form>
/// ```
pub fn register() -> Result(Nil, lustre.Error) {
  let component =
    lustre.component(core.init, core.update, core.view, [
      // Listen for schema changes (JSON string)
      component.on_attribute_change("schema", core.parse_schema_attr),
      // Listen for submit URL changes
      component.on_attribute_change("submit-url", fn(value) {
        Ok(core.SubmitUrlChanged(value))
      }),
      // Listen for submit method changes (GET, POST, PUT, etc.)
      component.on_attribute_change("submit-method", fn(value) {
        Ok(core.SubmitMethodChanged(value))
      }),
      // Listen for initial values changes (JSON string)
      component.on_attribute_change(
        "initial-values",
        core.parse_initial_values_attr,
      ),
      // Listen for show-readonly-fields changes
      component.on_attribute_change("show-readonly-fields", fn(value) {
        Ok(core.ShowReadonlyFieldsChanged(core.parse_bool_attr(value)))
      }),
      // Listen for read-only (review) mode toggle
      component.on_attribute_change("read-only", fn(value) {
        Ok(core.ReadOnlyChanged(core.parse_bool_attr(value)))
      }),
      // Listen for upload-base-url changes
      component.on_attribute_change("upload-base-url", fn(value) {
        Ok(core.UploadBaseUrlChanged(value))
      }),
      // Listen for ui-schema changes (JSON string)
      component.on_attribute_change("ui-schema", core.parse_ui_schema_attr),
      // Listen for `validator` JS property — embedder sets
      // `element.validator = (values) => [...]` on the DOM node.
      component.on_property_change(
        "validator",
        decode.map(decode.dynamic, core.ValidatorChanged),
      ),
    ])

  lustre.register(component, "formosh-form")
}

/// Create a form component element with attributes.
/// 
/// This function provides a convenient way to create the component
/// programmatically within a Lustre application.
/// 
/// ## Example
/// ```gleam
/// import formosh/component
/// 
/// let form = component.element([
///   component.schema(my_schema),
///   component.submit_url("https://api.example.com/submit"),
///   component.on_submit(HandleFormSubmit),
/// ])
/// ```
pub fn element(attributes: List(Attribute(msg))) -> Element(msg) {
  element.element("formosh-form", attributes, [])
}

// ATTRIBUTES ------------------------------------------------------------------

/// Set the JSON Schema for the form.
///
/// This can be either a JSON string or a JsonSchema object when used
/// programmatically.
pub fn schema(schema: JsonSchema) -> Attribute(msg) {
  let json_obj = serializer.schema_to_json(schema)
  let json_string = json.to_string(json_obj)
  attribute.attribute("schema", json_string)
}

/// Set the JSON Schema as a string attribute.
pub fn schema_string(schema_json: String) -> Attribute(msg) {
  attribute.attribute("schema", schema_json)
}

/// Set the submission URL for the form.
pub fn submit_url(url: String) -> Attribute(msg) {
  attribute.attribute("submit-url", url)
}

/// Set the HTTP method for form submission (default: POST).
pub fn submit_method(method: String) -> Attribute(msg) {
  attribute.attribute("submit-method", method)
}

/// Set initial values for the form as a JSON string.
pub fn initial_values_string(json: String) -> Attribute(msg) {
  attribute.attribute("initial-values", json)
}

/// Control visibility of readOnly fields (default: True).
///
/// When True, fields with `readOnly: true` in the schema are rendered
/// as disabled inputs. When False, they are hidden entirely.
pub fn show_readonly_fields(show: Bool) -> Attribute(msg) {
  attribute.attribute("show-readonly-fields", case show {
    True -> "true"
    False -> "false"
  })
}

/// Render the form as a static, read-only summary (label → value) instead
/// of editable inputs. Submit/Reset controls are hidden. Pair with
/// `schema_string` + `initial_values_string` to display stored values.
pub fn read_only(value: Bool) -> Attribute(msg) {
  attribute.attribute("read-only", case value {
    True -> "true"
    False -> "false"
  })
}

/// Set the base URL for file uploads.
///
/// Files are uploaded via POST to this URL with multipart/form-data.
/// Delete requests use DELETE {url}/{filename}.
pub fn upload_base_url(url: String) -> Attribute(msg) {
  attribute.attribute("upload-base-url", url)
}

/// Set the UiSchema as a JSON string attribute.
///
/// UiSchema separates presentation hints (widgets, order, placeholder,
/// help text, etc.) from the JSON Schema data definition. See
/// `formosh/schema/ui_schema` for the supported `ui:*` fields.
pub fn ui_schema_string(json: String) -> Attribute(msg) {
  attribute.attribute("ui-schema", json)
}

/// Listen for form submission events.
///
/// The handler receives the form data as a JSON object in the event detail.
pub fn on_submit(handler: fn(dict.Dict(String, Value)) -> msg) -> Attribute(msg) {
  event.on("formosh-submit", {
    decode.at(["detail", "values"], decode.dynamic)
    |> decode.map(fn(_data) {
      // TODO: Properly decode the form values from dynamic
      handler(dict.new())
    })
  })
}

/// Listen for form validation events.
pub fn on_validate(handler: fn(Bool) -> msg) -> Attribute(msg) {
  event.on("formosh-validate", {
    decode.at(["detail", "isValid"], decode.bool)
    |> decode.map(handler)
  })
}

/// Listen for form change events.
pub fn on_change(handler: fn(dict.Dict(String, Value)) -> msg) -> Attribute(msg) {
  event.on("formosh-change", {
    decode.at(["detail", "values"], decode.dynamic)
    |> decode.map(fn(_data) {
      // TODO: Properly decode the form values from dynamic
      handler(dict.new())
    })
  })
}
