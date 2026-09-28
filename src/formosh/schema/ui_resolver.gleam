/// Path-based UiSchema lookup and hint resolution.
///
/// `lookup` walks the UiSchema tree by `FieldPath` segments — `PropertySegment`
/// descends into `.properties`, `ArraySegment` descends into `.items` (index
/// ignored, since items is a template applied to every row). `resolve_hints`
/// turns the looked-up `UiProperty` into the effective `RenderHints`.
///
/// UiSchema is the only presentation-hint source; JSON Schema nodes
/// contribute none. Leaf renderers read the resulting `RenderHints` via
/// `FieldRenderCtx.hints`.
import formosh/form/path.{type FieldPath, ArraySegment, PropertySegment}
import formosh/schema/types.{type RenderHints, HiddenWidget, RenderHints}
import formosh/schema/ui_schema.{
  type UiProperty, type UiSchema, empty_ui_property,
}
import gleam/list
import gleam/option.{Some}

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

/// Predicate that decides whether a field is suppressed from the UI for the
/// given resolved `hints`, `is_readonly`, and `show_readonly_fields` flag.
///
/// Owned here (alongside `resolve_hints`) so the render-time gate in
/// `field_dispatcher.render_field_at_path` and the submit-time walker in
/// `form/visibility.invisible_paths` cannot drift apart. Adding a new
/// widget with suppression semantics or a new readOnly rule? Update this
/// predicate, not the call sites.
pub fn is_suppressed(
  hints: RenderHints,
  is_readonly: Bool,
  show_readonly_fields: Bool,
) -> Bool {
  let is_hidden = hints.widget == Some(HiddenWidget)
  let is_readonly_suppressed = is_readonly && !show_readonly_fields
  is_hidden || is_readonly_suppressed
}

/// Resolve the effective `RenderHints` for `field_path` from the UiSchema.
/// UiSchema is the only hint source (the `x-*` fallback was removed in
/// v0.11). `addable`/`removable`/`orderable` stay `None` when unset —
/// renderers treat `None` as enabled.
pub fn resolve_hints(ui_schema: UiSchema, field_path: FieldPath) -> RenderHints {
  let ui_prop = lookup(ui_schema, field_path)
  RenderHints(
    widget: ui_prop.widget,
    options: ui_prop.options,
    upload_config: ui_prop.upload,
    placeholder: ui_prop.placeholder,
    help: ui_prop.help,
    autofocus: ui_prop.autofocus,
    disabled: ui_prop.disabled,
    readonly: ui_prop.readonly,
    title: ui_prop.title,
    description: ui_prop.description,
    order: ui_prop.order,
    addable: ui_prop.addable,
    removable: ui_prop.removable,
    orderable: ui_prop.orderable,
  )
}
