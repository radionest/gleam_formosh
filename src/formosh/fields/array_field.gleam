/// Array container renderer.
///
/// Renders the array label, item-level frames (number, remove button),
/// and the add-item button. Child field rendering is delegated back to
/// the caller via `render_child` — this keeps a single source of truth
/// for widget dispatch (see `field_dispatcher.render_field_at_path`).
import formosh/fields/field_common.{type FieldRenderCtx}
import formosh/form/model.{
  type FormModel, type FormMsg, AddArrayItemPath, RemoveArrayItemPath,
}
import formosh/form/path
import formosh/schema/conditional_resolver
import formosh/schema/properties
import formosh/schema/types.{type SchemaProperty, type Value}
import formosh/schema/ui_resolver
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
  ctx: FieldRenderCtx,
  model: FormModel,
  render_child: fn(FieldRenderCtx, FormModel) -> Element(FormMsg),
) -> Element(FormMsg) {
  let array_name = path.get_field_name(ctx.path)
  let description = ctx.property.description

  let items = case ctx.value {
    Some(types.ArrayValue(xs)) -> xs
    Some(_) -> []
    None -> []
  }

  // `resolve_hints` always wraps `addable`/`removable` in `Some`
  // (UiSchema override or `SchemaProperty.addable` Bool fallback), so the
  // outer `option.unwrap` default below is just a defensive no-op.
  let addable = option.unwrap(ctx.hints.addable, True)

  html.div([class("array-field")], [
    field_common.render_container_label(
      field_name: array_name,
      property: ctx.property,
      is_required: ctx.is_required,
      css_class: "array-label",
      hints: ctx.hints,
    ),
    case description {
      Some(desc) -> html.p([class("field-description")], [html.text(desc)])
      None -> element.none()
    },
    html.div(
      [class("array-items")],
      list.index_map(items, fn(item, index) {
        render_array_item(ctx, item, index, model, render_child)
      }),
    ),
    case ctx.is_readonly || !addable {
      True -> element.none()
      False ->
        html.button(
          [
            type_("button"),
            class("add-array-item"),
            event.on_click(AddArrayItemPath(ctx.path)),
          ],
          [html.text("Добавить элемент")],
        )
    },
  ])
}

/// Render a single row: header with index + remove button, plus child fields.
fn render_array_item(
  ctx: FieldRenderCtx,
  item: Value,
  index: Int,
  model: FormModel,
  render_child: fn(FieldRenderCtx, FormModel) -> Element(FormMsg),
) -> Element(FormMsg) {
  case ctx.property.items {
    Some(item_schema) ->
      html.div([class("array-item")], [
        html.div([class("array-item-header")], [
          html.span([class("array-item-index")], [
            html.text("№ " <> int.to_string(index + 1)),
          ]),
          case ctx.is_readonly || !option.unwrap(ctx.hints.removable, True) {
            True -> element.none()
            False ->
              html.button(
                [
                  type_("button"),
                  class("remove-array-item"),
                  event.on_click(RemoveArrayItemPath(ctx.path, index)),
                ],
                [html.text("Удалить")],
              )
          },
        ]),
        html.div(
          [class("array-item-fields")],
          render_item_fields(ctx, item_schema, item, index, model, render_child),
        ),
      ])
    None -> element.none()
  }
}

/// Render every child field of a single row.
///
/// Resolves the item schema against the row's own values (so item-level
/// `if/then/else` rules take effect), then dispatches every visible
/// property through `render_child`. `is_disabled` is inherited as-is from
/// the array container; `is_readonly` is OR-inherited with each child's
/// own `read_only`.
fn render_item_fields(
  ctx: FieldRenderCtx,
  item_schema: SchemaProperty,
  item: Value,
  index: Int,
  model: FormModel,
  render_child: fn(FieldRenderCtx, FormModel) -> Element(FormMsg),
) -> List(Element(FormMsg)) {
  let resolved =
    conditional_resolver.resolve_conditional_property(item_schema, item)
  let item_path = list.append(ctx.path, [path.ArraySegment(index)])

  // For array items, the row order is controlled by the array's `items`
  // template, looked up via the row's path.
  let item_hints =
    ui_resolver.resolve_hints(model.ui_schema, item_path, item_schema)
  case resolved.properties {
    Some(props) ->
      properties.apply_order(props, item_hints.order)
      |> list.map(fn(entry) {
        let #(child_name, child_prop) = entry
        let child_path =
          list.append(item_path, [path.PropertySegment(child_name)])
        let child_ctx =
          field_common.make_child_ctx(
            parent: ctx,
            model: model,
            path: child_path,
            property: child_prop,
            is_required: list.contains(resolved.required, child_name),
          )
        render_child(child_ctx, model)
      })
    None -> []
  }
}
