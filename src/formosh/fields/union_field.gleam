/// Union (`anyOf`, 2+ members) branch chooser + active-branch subform.
///
/// `ctx.property` arrives already materialized to the active branch (its
/// `field_type`/`properties`/etc. are the branch's own) WITH `any_of` still
/// carrying the full member list — that's the dispatcher's cue to render a
/// chooser here instead of the branch's widget directly (`union_resolver`
/// design D4). The chooser lets the user switch branches; the active
/// branch's own widget renders beneath it via `render_child`, dispatched at
/// the union's own path with `any_of` stripped so the dispatcher recurses
/// into the branch's widget instead of back into this module.
import formosh/fields/field_common.{type FieldRenderCtx, FieldRenderCtx}
import formosh/form/model.{type FormModel, type FormMsg, SelectUnionBranchPath}
import formosh/form/path
import formosh/form/union_resolver
import formosh/schema/types
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// Render a multi-branch union: a branch chooser (`part="union"` wrapper)
/// followed by the active branch's subform. The chooser follows the enum
/// widget heuristic — radio group for ≤5 branches, select dropdown for
/// more — and `ui:widget: "select" | "radio"` on the union's own path
/// forces the style, mirroring `string_field`'s enum rendering.
pub fn render(
  ctx: FieldRenderCtx,
  model: FormModel,
  render_child: fn(FieldRenderCtx, FormModel) -> Element(FormMsg),
) -> Element(FormMsg) {
  let members = option.unwrap(ctx.property.any_of, [])
  let active =
    union_resolver.active_branch_index(
      ctx.property,
      ctx.value,
      ctx.path,
      model.selected_branches,
    )
  let child_ctx =
    FieldRenderCtx(
      ..ctx,
      property: types.SchemaProperty(..ctx.property, any_of: None),
    )

  html.div(
    [attribute.class("formosh-union"), attribute.attribute("part", "union")],
    [render_chooser(ctx, members, active), render_child(child_ctx, model)],
  )
}

/// Pick the chooser control: `ui:widget` override wins outright; otherwise
/// the same ≤5-radio / >5-select threshold `string_field.render_enum` uses.
fn render_chooser(
  ctx: FieldRenderCtx,
  members: List(types.SchemaProperty),
  active: Int,
) -> Element(FormMsg) {
  case widget_name(ctx) {
    Some("select") -> render_select(ctx, members, active)
    Some("radio") -> render_radio_group(ctx, members, active)
    _ ->
      case list.length(members) <= 5 {
        True -> render_radio_group(ctx, members, active)
        False -> render_select(ctx, members, active)
      }
  }
}

/// Extract the `CustomWidget` payload as a string for dispatch decisions —
/// same small helper as `string_field.widget_name`, copied rather than
/// imported (that function is private to its module).
fn widget_name(ctx: FieldRenderCtx) -> Option(String) {
  case ctx.hints.widget {
    Some(types.CustomWidget(name)) -> Some(name)
    _ -> None
  }
}

/// Radio group chooser (≤5 branches by default). Each option's value is
/// the branch index as a string; a click dispatches `SelectUnionBranchPath`
/// with that (already-known) index directly — no string round-trip needed,
/// mirroring `string_field.render_radio_group`'s fixed-message `on_click`.
fn render_radio_group(
  ctx: FieldRenderCtx,
  members: List(types.SchemaProperty),
  active: Int,
) -> Element(FormMsg) {
  let field_id = path.to_string(ctx.path)
  let effective_disabled = ctx.is_disabled || ctx.is_readonly

  html.div(
    [
      attribute.class("formosh-union-radio-group"),
      attribute.attribute("part", "union-radio"),
    ],
    list.index_map(members, fn(member, index) {
      let str_val = int.to_string(index)
      let radio_id = field_id <> "_union_" <> str_val

      html.div(
        [
          attribute.class("formosh-radio-item"),
          attribute.attribute("part", "radio-item"),
        ],
        [
          html.input([
            attribute.type_("radio"),
            attribute.id(radio_id),
            attribute.name(field_id <> "_union"),
            attribute.value(str_val),
            attribute.checked(index == active),
            attribute.disabled(effective_disabled),
            event.on_click(SelectUnionBranchPath(ctx.path, index)),
          ]),
          html.label([attribute.for(radio_id)], [
            html.text(union_resolver.branch_label(member, index)),
          ]),
        ],
      )
    }),
  )
}

/// Select dropdown chooser (>5 branches by default, or `ui:widget:
/// "select"` override). The changed option's string value is the branch
/// index, parsed back with `int.parse` (defaulting to 0 on malformed
/// input — should not happen for a value this module itself generates).
fn render_select(
  ctx: FieldRenderCtx,
  members: List(types.SchemaProperty),
  active: Int,
) -> Element(FormMsg) {
  let field_id = path.to_string(ctx.path)
  let effective_disabled = ctx.is_disabled || ctx.is_readonly

  html.select(
    [
      attribute.id(field_id <> "_union"),
      attribute.name(field_id <> "_union"),
      attribute.class("formosh-union-select"),
      attribute.attribute("part", "union-select"),
      attribute.disabled(effective_disabled),
      event.on_change(fn(val) {
        SelectUnionBranchPath(ctx.path, parse_branch_index(val))
      }),
    ],
    list.index_map(members, fn(member, index) {
      let str_val = int.to_string(index)
      html.option(
        [attribute.value(str_val), attribute.selected(index == active)],
        union_resolver.branch_label(member, index),
      )
    }),
  )
}

fn parse_branch_index(raw: String) -> Int {
  case int.parse(raw) {
    Ok(i) -> i
    Error(_) -> 0
  }
}
