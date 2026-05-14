/// Array container renderer.
///
/// Renders the array label, item-level frames (number, remove button),
/// and the add-item button. Child field rendering is delegated back to
/// the caller via `render_child` — this keeps a single source of truth
/// for widget dispatch (see `field_dispatcher.render_field_at_path`).
import formosh/fields/field_common
import formosh/form/model.{
  type FormModel, type FormMsg, AddArrayItemPath, RemoveArrayItemPath,
}
import formosh/form/path.{type FieldPath}
import formosh/schema/conditional_resolver
import formosh/schema/types.{type SchemaProperty, type Value}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute.{class, type_}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// Render an array field as a labelled container of items.
///
/// Each item gets a header (index + remove button) followed by its child
/// fields. Items resolve their own conditionals against the row's own
/// values, so every row is treated independently.
///
/// The dispatcher passes itself as `render_child` so any child field —
/// including nested arrays and objects — goes through the same widget
/// dispatch as top-level fields.
pub fn render_container(
  field_path: FieldPath,
  property: SchemaProperty,
  model: FormModel,
  is_required: Bool,
  is_disabled: Bool,
  is_readonly: Bool,
  render_child: fn(FieldPath, SchemaProperty, FormModel, Bool, Bool, Bool) ->
    Element(FormMsg),
) -> Element(FormMsg) {
  let array_name = path.get_field_name(field_path)
  let description = property.description

  let items = case model.get_value_at_path(model, field_path) {
    Some(types.ArrayValue(xs)) -> xs
    _ -> []
  }

  html.div([class("array-field")], [
    field_common.render_container_label(
      array_name,
      property,
      is_required,
      "array-label",
    ),
    case description {
      Some(desc) -> html.p([class("field-description")], [html.text(desc)])
      None -> element.none()
    },
    html.div(
      [class("array-items")],
      list.index_map(items, fn(item, index) {
        render_array_item(
          field_path,
          property,
          item,
          index,
          model,
          is_disabled,
          is_readonly,
          render_child,
        )
      }),
    ),
    case is_readonly || !property.addable {
      True -> element.none()
      False ->
        html.button(
          [
            type_("button"),
            class("add-array-item"),
            event.on_click(AddArrayItemPath(field_path)),
          ],
          [html.text("Добавить элемент")],
        )
    },
  ])
}

/// Render a single row: header with index + remove button, plus child fields.
fn render_array_item(
  array_path: FieldPath,
  property: SchemaProperty,
  item: Value,
  index: Int,
  model: FormModel,
  is_disabled: Bool,
  is_readonly: Bool,
  render_child: fn(FieldPath, SchemaProperty, FormModel, Bool, Bool, Bool) ->
    Element(FormMsg),
) -> Element(FormMsg) {
  case property.items {
    Some(item_schema) ->
      html.div([class("array-item")], [
        html.div([class("array-item-header")], [
          html.span([class("array-item-index")], [
            html.text("№ " <> int.to_string(index + 1)),
          ]),
          case is_readonly || !property.removable {
            True -> element.none()
            False ->
              html.button(
                [
                  type_("button"),
                  class("remove-array-item"),
                  event.on_click(RemoveArrayItemPath(array_path, index)),
                ],
                [html.text("Удалить")],
              )
          },
        ]),
        html.div(
          [class("array-item-fields")],
          render_item_fields(
            array_path,
            item_schema,
            item,
            index,
            model,
            is_disabled,
            is_readonly,
            render_child,
          ),
        ),
      ])
    None -> element.none()
  }
}

/// Render every child field of a single row.
///
/// Resolves the item schema against the row's own values (so item-level
/// `if/then/else` rules take effect), then dispatches every visible
/// property through `render_child`.
fn render_item_fields(
  array_path: FieldPath,
  item_schema: SchemaProperty,
  item: Value,
  index: Int,
  model: FormModel,
  is_disabled: Bool,
  is_readonly: Bool,
  render_child: fn(FieldPath, SchemaProperty, FormModel, Bool, Bool, Bool) ->
    Element(FormMsg),
) -> List(Element(FormMsg)) {
  let resolved =
    conditional_resolver.resolve_conditional_property(item_schema, item)
  let item_path = list.append(array_path, [path.ArraySegment(index)])

  case resolved.properties {
    Some(props) ->
      list.map(props, fn(entry) {
        let #(child_name, child_prop) = entry
        let child_path =
          list.append(item_path, [path.PropertySegment(child_name)])
        let child_required = list.contains(resolved.required, child_name)
        let child_readonly = is_readonly || child_prop.read_only
        render_child(
          child_path,
          child_prop,
          model,
          child_required,
          is_disabled,
          child_readonly,
        )
      })
    None -> []
  }
}
