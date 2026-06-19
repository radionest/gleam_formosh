/// UiSchema — parallel tree of presentation settings keyed by FieldPath.
///
/// Mirrors the JSON Schema shape so that authors can drop UI hints next to
/// the data definition without polluting the schema. Each `UiProperty`
/// optionally overrides widget choice, label/help text, behavioural flags
/// (autofocus/disabled/readonly), array structural controls (addable/
/// removable), and child ordering. Nested structures use `properties` for
/// object children and `items` for the array element template (so a single
/// `items.field` setting applies to every row in the array).
import formosh/schema/types.{type UploadConfig, type Value, type Widget}
import gleam/dict.{type Dict}
import gleam/option.{type Option, None}

/// UI hints for a single field, parallel to `SchemaProperty`.
///
/// All fields are optional overrides. A `None` value means "fall through to
/// the schema-level default or x-* extension"; `Some` wins during merge.
/// `properties` and `items` carry hints for nested fields — `lookup` in
/// `ui_resolver` walks them by FieldPath segments.
pub type UiProperty {
  UiProperty(
    /// Widget override (corresponds to `ui:widget`).
    widget: Option(Widget),
    /// Widget-specific options bag (`ui:options`).
    options: Dict(String, Value),
    /// Child ordering for object containers (`ui:order`).
    order: Option(List(String)),
    /// Placeholder text for inputs (`ui:placeholder`).
    placeholder: Option(String),
    /// Help text below input (`ui:help`) — overrides `description`.
    help: Option(String),
    /// `autofocus` HTML attribute (`ui:autofocus`).
    autofocus: Option(Bool),
    /// Runtime disable flag (`ui:disabled`).
    disabled: Option(Bool),
    /// Readonly override (`ui:readonly`) — augments JSON Schema `readOnly`.
    readonly: Option(Bool),
    /// Label override (`ui:title`) — overrides schema's `title`.
    title: Option(String),
    /// Description override (`ui:description`) — overrides schema's
    /// `description`.
    description: Option(String),
    /// Array-level "show add button" toggle (`ui:addable`).
    addable: Option(Bool),
    /// Array-level "show remove button" toggle (`ui:removable`).
    removable: Option(Bool),
    /// Array-level "show reorder buttons" toggle (`ui:orderable`).
    orderable: Option(Bool),
    /// Upload widget configuration (`ui:accept`, `ui:maxFileSize`).
    upload: Option(UploadConfig),
    /// UI hints for object children, keyed by property name.
    properties: List(#(String, UiProperty)),
    /// UI hints template for array elements — applies to every row.
    items: Option(UiProperty),
  )
}

/// Root UiSchema for a form.
///
/// Holds the top-level `ui:order` (applied to root-level fields) and child
/// `UiProperty` nodes keyed by top-level field name.
pub type UiSchema {
  UiSchema(properties: List(#(String, UiProperty)), order: Option(List(String)))
}

/// Empty `UiProperty` with no overrides — used as fallback when lookup
/// misses or when no UiSchema is supplied.
pub fn empty_ui_property() -> UiProperty {
  UiProperty(
    widget: None,
    options: dict.new(),
    order: None,
    placeholder: None,
    help: None,
    autofocus: None,
    disabled: None,
    readonly: None,
    title: None,
    description: None,
    addable: None,
    removable: None,
    orderable: None,
    upload: None,
    properties: [],
    items: None,
  )
}

/// Empty `UiSchema` — the default value when no `ui-schema` attribute or
/// config option is supplied. All lookups return `empty_ui_property()`, so
/// every field falls back to its schema-level defaults.
pub fn empty_ui_schema() -> UiSchema {
  UiSchema(properties: [], order: None)
}
