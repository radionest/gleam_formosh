/// Path-based lookup and merge for UiSchema.
///
/// `lookup` walks the UiSchema tree by `FieldPath` segments — `PropertySegment`
/// descends into `.properties`, `ArraySegment` descends into `.items` (index
/// ignored, since items is a template applied to every row). `resolve_hints`
/// merges the looked-up `UiProperty` with the schema's x-* `RenderHints` —
/// UiSchema wins on collisions, x-* values are used as fallback.
///
/// This is the single place where presentation data from UiSchema and from
/// JSON Schema x-* extensions are reconciled. Leaf renderers read the
/// resulting `RenderHints` via `FieldRenderCtx.hints` and stay agnostic of
/// the source.
import formosh/form/path.{type FieldPath, ArraySegment, PropertySegment}
import formosh/schema/types.{type RenderHints, type SchemaProperty, RenderHints}
import formosh/schema/ui_schema.{
  type UiProperty, type UiSchema, empty_ui_property,
}
import gleam/list
import gleam/option

/// Look up the `UiProperty` at the given path in `ui_schema`.
///
/// Returns `empty_ui_property()` if any step misses (no such field name in
/// `properties`, no `items` template for an array segment, etc.). Root path
/// (`[]`) also returns `empty_ui_property()` — root-level options live on
/// `UiSchema` itself, not on a `UiProperty`.
pub fn lookup(ui_schema: UiSchema, field_path: FieldPath) -> UiProperty {
  case field_path {
    [] -> empty_ui_property()
    [PropertySegment(name), ..rest] ->
      case list.key_find(ui_schema.properties, name) {
        Ok(prop) -> walk(prop, rest)
        Error(_) -> empty_ui_property()
      }
    _ -> empty_ui_property()
  }
}

fn walk(prop: UiProperty, rest: FieldPath) -> UiProperty {
  case rest {
    [] -> prop
    [PropertySegment(name), ..tail] ->
      case list.key_find(prop.properties, name) {
        Ok(child) -> walk(child, tail)
        Error(_) -> empty_ui_property()
      }
    [ArraySegment(_), ..tail] ->
      case prop.items {
        option.Some(items_prop) -> walk(items_prop, tail)
        option.None -> empty_ui_property()
      }
  }
}

/// Merge UiSchema with x-* fallback to produce the effective `RenderHints`.
///
/// UiSchema fields win on collisions (widget, upload); x-* fallback applies
/// only when the UiSchema field is `None`. Pure UI fields (placeholder,
/// help, autofocus, ...) come exclusively from UiSchema — JSON Schema does
/// not have analogues to fall back to.
pub fn resolve_hints(
  ui_schema: UiSchema,
  field_path: FieldPath,
  schema_property: SchemaProperty,
) -> RenderHints {
  let ui_prop = lookup(ui_schema, field_path)
  let x_hints = schema_property.render_hints
  RenderHints(
    widget: option.or(ui_prop.widget, x_hints.widget),
    upload_config: option.or(ui_prop.upload, x_hints.upload_config),
    placeholder: ui_prop.placeholder,
    help: ui_prop.help,
    autofocus: ui_prop.autofocus,
    disabled: ui_prop.disabled,
    readonly: ui_prop.readonly,
    title: ui_prop.title,
    description: ui_prop.description,
    order: ui_prop.order,
    // `addable`/`removable` get an x-* fallback through `SchemaProperty`
    // (they're parsed from `x-addable`/`x-removable` into Bool fields
    // there). UiSchema wins on `Some`; otherwise the schema's Bool comes
    // through wrapped in `Some` so callers can read `hints.addable`
    // uniformly without consulting `property.addable`.
    addable: option.or(ui_prop.addable, option.Some(schema_property.addable)),
    removable: option.or(
      ui_prop.removable,
      option.Some(schema_property.removable),
    ),
  )
}
