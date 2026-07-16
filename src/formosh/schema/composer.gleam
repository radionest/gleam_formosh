/// allOf composition flattening.
///
/// Runs once inside `parser.parse_schema`, after `resolver.resolve_refs`:
/// every node's `all_of` members are deep-merged into the node and the field
/// cleared, so downstream modules only ever see plain merged properties.
///
/// Merge contract (design.md D3-D6): members fold in array order and the
/// node's own keywords override last (mirrors the $ref local-override
/// precedent); same-key properties merge field-by-field recursively; bounds
/// combine stricter-wins; `required` unions; conditionals append with member
/// rules first.
import formosh/schema/properties
import formosh/schema/resolver
import formosh/schema/types.{
  type ConditionalRule, type JsonSchema, type SchemaProperty, ArrayConstraints,
  ConditionalRule, JsonSchema, NumberConstraints, SchemaProperty,
  StringConstraints,
}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

/// Flatten every `allOf` in the schema tree into plain merged keywords.
/// Total: never fails; unsatisfiable bound combinations are re-normalized.
pub fn flatten_schema(schema: JsonSchema) -> JsonSchema {
  let m =
    schema.all_of
    |> option.unwrap([])
    |> list.map(flatten_property)
    |> list.fold(types.empty_property(), merge_pair)

  // Flatten root-local properties BEFORE the collision merge — merge_pair
  // clears all_of, so an unflattened local child would lose its members.
  let local_properties =
    list.map(schema.properties, fn(entry) {
      #(entry.0, flatten_property(entry.1))
    })
  let merged_properties = case m.properties {
    Some(member_props) ->
      properties.merge_with(member_props, local_properties, merge_pair)
    None -> local_properties
  }

  JsonSchema(
    ..schema,
    title: option.or(schema.title, m.title),
    description: option.or(schema.description, m.description),
    properties: merged_properties,
    required: list.append(m.required, schema.required) |> list.unique(),
    conditionals: list.append(m.conditionals, schema.conditionals)
      |> list.map(flatten_rule),
    string_constraints: merge_string_constraints(
      m.string_constraints,
      schema.string_constraints,
    ),
    number_constraints: merge_number_constraints(
      m.number_constraints,
      schema.number_constraints,
    ),
    all_of: None,
  )
}

/// Flatten a property subtree: descend into children first so every side of
/// the merge is already composition-free, then collapse this node's members
/// and merge the node's own keywords last. Descending BEFORE the merge
/// matters: on a same-key collision `merge_pair` clears `all_of`, so a
/// child that still carried unmerged members would lose them silently.
pub fn flatten_property(prop: SchemaProperty) -> SchemaProperty {
  let flattened =
    SchemaProperty(
      ..prop,
      properties: option.map(prop.properties, fn(props) {
        list.map(props, fn(entry) { #(entry.0, flatten_property(entry.1)) })
      }),
      items: option.map(prop.items, flatten_property),
      one_of: option.map(prop.one_of, list.map(_, flatten_property)),
      conditionals: list.map(prop.conditionals, flatten_rule),
      all_of: None,
    )

  prop.all_of
  |> option.unwrap([])
  |> list.map(flatten_property)
  |> list.fold(types.empty_property(), merge_pair)
  |> merge_pair(flattened)
}

/// Flatten composition inside a conditional's branches so `then: {allOf}` /
/// `if: {allOf}` are already merged when the runtime resolver fires.
fn flatten_rule(rule: ConditionalRule) -> ConditionalRule {
  ConditionalRule(
    if_schema: flatten_property(rule.if_schema),
    then_schema: option.map(rule.then_schema, flatten_property),
    else_schema: option.map(rule.else_schema, flatten_property),
  )
}

/// Deep-merge two properties: `overlay` wins per field, `base` fills gaps.
fn merge_pair(base: SchemaProperty, overlay: SchemaProperty) -> SchemaProperty {
  SchemaProperty(
    field_type: option.or(overlay.field_type, base.field_type),
    title: option.or(overlay.title, base.title),
    description: option.or(overlay.description, base.description),
    default: option.or(overlay.default, base.default),
    enum_values: option.or(overlay.enum_values, base.enum_values),
    one_of: option.or(overlay.one_of, base.one_of),
    ref: option.or(overlay.ref, base.ref),
    string_constraints: merge_string_constraints(
      base.string_constraints,
      overlay.string_constraints,
    ),
    number_constraints: merge_number_constraints(
      base.number_constraints,
      overlay.number_constraints,
    ),
    array_constraints: merge_array_constraints(
      base.array_constraints,
      overlay.array_constraints,
    ),
    items: case base.items, overlay.items {
      Some(b), Some(o) -> Some(merge_pair(b, o))
      b, o -> option.or(o, b)
    },
    properties: case base.properties, overlay.properties {
      Some(b), Some(o) -> Some(properties.merge_with(b, o, merge_pair))
      b, o -> option.or(o, b)
    },
    required: list.append(base.required, overlay.required) |> list.unique(),
    read_only: base.read_only || overlay.read_only,
    addable: base.addable && overlay.addable,
    removable: base.removable && overlay.removable,
    render_hints: resolver.merge_render_hints(
      overlay.render_hints,
      base.render_hints,
    ),
    conditionals: list.append(base.conditionals, overlay.conditionals),
    all_of: None,
  )
}

/// Combine two optional values with `pick` when both are present.
fn combine(a: Option(t), b: Option(t), pick: fn(t, t) -> t) -> Option(t) {
  case a, b {
    Some(x), Some(y) -> Some(pick(x, y))
    x, y -> option.or(y, x)
  }
}

fn merge_string_constraints(
  base: Option(types.StringConstraints),
  overlay: Option(types.StringConstraints),
) -> Option(types.StringConstraints) {
  case base, overlay {
    Some(b), Some(o) ->
      Some(StringConstraints(
        min_length: combine(b.min_length, o.min_length, int.max),
        max_length: combine(b.max_length, o.max_length, int.min),
        pattern: option.or(o.pattern, b.pattern),
        format: option.or(o.format, b.format),
      ))
    b, o -> option.or(o, b)
  }
}

fn merge_number_constraints(
  base: Option(types.NumberConstraints),
  overlay: Option(types.NumberConstraints),
) -> Option(types.NumberConstraints) {
  case base, overlay {
    Some(b), Some(o) ->
      Some(NumberConstraints(
        minimum: combine(b.minimum, o.minimum, float.max),
        maximum: combine(b.maximum, o.maximum, float.min),
        exclusive_minimum: combine(
          b.exclusive_minimum,
          o.exclusive_minimum,
          float.max,
        ),
        exclusive_maximum: combine(
          b.exclusive_maximum,
          o.exclusive_maximum,
          float.min,
        ),
        multiple_of: option.or(o.multiple_of, b.multiple_of),
      ))
    b, o -> option.or(o, b)
  }
}

fn merge_array_constraints(
  base: Option(types.ArrayConstraints),
  overlay: Option(types.ArrayConstraints),
) -> Option(types.ArrayConstraints) {
  case base, overlay {
    Some(b), Some(o) -> {
      let min_items = combine(b.min_items, o.min_items, int.max)
      let max_items = combine(b.max_items, o.max_items, int.min)
      // Unsatisfiable after combining: minItems wins — same normalization
      // as the parser, otherwise ensure_min_items wedges the form.
      case min_items, max_items {
        Some(min), Some(max) if min > max ->
          Some(ArrayConstraints(min_items: Some(min), max_items: Some(min)))
        _, _ ->
          Some(ArrayConstraints(min_items: min_items, max_items: max_items))
      }
    }
    b, o -> option.or(o, b)
  }
}
