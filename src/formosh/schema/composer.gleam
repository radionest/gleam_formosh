/// allOf composition flattening.
///
/// Runs once inside `parser.parse_schema`, after `$ref` resolution: every
/// node's `all_of` members are deep-merged into the node and the field
/// cleared, so downstream modules only ever see plain merged properties.
/// The document root goes through the same path — it parses as a
/// `SchemaProperty` and is converted to `JsonSchema` afterwards.
///
/// Merge contract (design D3-D6): members fold in array order and the
/// node's own keywords override last (mirrors the $ref local-override
/// precedent); same-key properties merge field-by-field recursively; bounds
/// combine stricter-wins; `required` unions; conditionals append with member
/// rules first. Scalar keywords (`title`, `default`, `enum`, `oneOf`,
/// `pattern`, `format`, `multipleOf`) take the later value wholesale —
/// enum/oneOf are overridden, not intersected (D5).
import formosh/schema/properties
import formosh/schema/resolver
import formosh/schema/types.{
  type ConditionalRule, type FieldType, type ParseError, type SchemaProperty,
  ArrayConstraints, ConditionalRule, IntegerType, NumberConstraints, NumberType,
  SchemaProperty, StringConstraints, UnsatisfiableSchema,
}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// Format the descent path (accumulated head-first) as a JSON-pointer-ish
/// breadcrumb for error messages.
fn path_string(path: List(String)) -> String {
  case path {
    [] -> "#"
    segments -> "#/" <> string.join(list.reverse(segments), "/")
  }
}

fn unsatisfiable(path: List(String), reason: String) -> ParseError {
  UnsatisfiableSchema(
    "unsatisfiable schema at " <> path_string(path) <> ": " <> reason,
  )
}

/// Traverse an Option through a fallible function, preserving None.
fn try_optional(
  value: Option(a),
  f: fn(a) -> Result(b, ParseError),
) -> Result(Option(b), ParseError) {
  case value {
    Some(v) -> result.map(f(v), Some)
    None -> Ok(None)
  }
}

/// Intersect two optional type declarations by instance-set semantics:
/// absence fills, equal keeps, number ∧ integer narrows to integer
/// (integer instances satisfy both), disjoint pairs validate nothing —
/// the same class as a `false` member, so they fail the parse.
fn intersect_types(
  base: Option(FieldType),
  overlay: Option(FieldType),
  path: List(String),
) -> Result(Option(FieldType), ParseError) {
  case base, overlay {
    None, t -> Ok(t)
    t, None -> Ok(t)
    Some(a), Some(b) if a == b -> Ok(Some(a))
    Some(NumberType), Some(IntegerType) | Some(IntegerType), Some(NumberType) ->
      Ok(Some(IntegerType))
    Some(a), Some(b) ->
      Error(unsatisfiable(
        path,
        "conflicting types " <> string.inspect(a) <> " vs " <> string.inspect(b),
      ))
  }
}

/// Flatten a property subtree: descend into children first so every side of
/// the merge is already composition-free, then collapse this node's members
/// and merge the node's own keywords last. Fallible: unsatisfiable
/// compositions (disjoint types, crossed bounds) fail the parse.
pub fn flatten_property(
  prop: SchemaProperty,
) -> Result(SchemaProperty, ParseError) {
  do_flatten(prop, [])
}

fn do_flatten(
  prop: SchemaProperty,
  path: List(String),
) -> Result(SchemaProperty, ParseError) {
  use flat_properties <- result.try(
    try_optional(prop.properties, fn(props) {
      list.try_map(props, fn(entry) {
        do_flatten(entry.1, [entry.0, ..path])
        |> result.map(fn(p) { #(entry.0, p) })
      })
    }),
  )
  use flat_items <- result.try(
    try_optional(prop.items, do_flatten(_, ["items", ..path])),
  )
  use flat_one_of <- result.try(
    try_optional(prop.one_of, list.try_map(_, do_flatten(_, ["oneOf", ..path]))),
  )
  use flat_conditionals <- result.try(
    list.try_map(prop.conditionals, flatten_rule(_, path)),
  )
  let flattened =
    SchemaProperty(
      ..prop,
      properties: flat_properties,
      items: flat_items,
      one_of: flat_one_of,
      conditionals: flat_conditionals,
      all_of: None,
    )

  case option.unwrap(prop.all_of, []) {
    // No effective members (absent, `[]`, or all `true` no-ops): pure no-op.
    // The node's own keywords are not a composition — they keep lenient
    // single-schema semantics and skip the satisfiability checks.
    [] -> Ok(flattened)
    members -> {
      use flat_members <- result.try(list.try_map(members, do_flatten(_, path)))
      use folded <- result.try(
        list.try_fold(flat_members, types.empty_property(), fn(acc, m) {
          merge_pair(acc, m, path)
        }),
      )
      merge_pair(folded, flattened, path)
    }
  }
}

/// Flatten composition inside a conditional's branches so `then: {allOf}` /
/// `if: {allOf}` are already merged when the runtime resolver fires.
fn flatten_rule(
  rule: ConditionalRule,
  path: List(String),
) -> Result(ConditionalRule, ParseError) {
  use if_flat <- result.try(do_flatten(rule.if_schema, ["if", ..path]))
  use then_flat <- result.try(
    try_optional(rule.then_schema, do_flatten(_, ["then", ..path])),
  )
  use else_flat <- result.try(
    try_optional(rule.else_schema, do_flatten(_, ["else", ..path])),
  )
  Ok(ConditionalRule(
    if_schema: if_flat,
    then_schema: then_flat,
    else_schema: else_flat,
  ))
}

/// Deep-merge two properties: `overlay` wins per field, `base` fills gaps.
/// Fallible: a disjoint type intersection or bounds crossed by the merge
/// (string/number/array) are unsatisfiable and fail the parse.
fn merge_pair(
  base: SchemaProperty,
  overlay: SchemaProperty,
  path: List(String),
) -> Result(SchemaProperty, ParseError) {
  use field_type <- result.try(intersect_types(
    base.field_type,
    overlay.field_type,
    path,
  ))
  use string_constraints <- result.try(
    merge_string_constraints(
      base.string_constraints,
      overlay.string_constraints,
    )
    |> check_string_constraints(path),
  )
  use number_constraints <- result.try(
    merge_number_constraints(
      base.number_constraints,
      overlay.number_constraints,
    )
    |> check_number_constraints(path),
  )
  use array_constraints <- result.try(
    merge_array_constraints(base.array_constraints, overlay.array_constraints)
    |> check_array_constraints(path),
  )
  use items <- result.try(case base.items, overlay.items {
    Some(b), Some(o) -> merge_pair(b, o, ["items", ..path]) |> result.map(Some)
    b, o -> Ok(option.or(o, b))
  })
  use merged_properties <- result.try(case base.properties, overlay.properties {
    Some(b), Some(o) ->
      properties.merge_with(b, o, fn(key, bp, op) {
        merge_pair(bp, op, [key, ..path])
      })
      |> result.map(Some)
    b, o -> Ok(option.or(o, b))
  })
  Ok(SchemaProperty(
    field_type: field_type,
    title: option.or(overlay.title, base.title),
    description: option.or(overlay.description, base.description),
    default: option.or(overlay.default, base.default),
    enum_values: option.or(overlay.enum_values, base.enum_values),
    one_of: option.or(overlay.one_of, base.one_of),
    ref: option.or(overlay.ref, base.ref),
    string_constraints: string_constraints,
    number_constraints: number_constraints,
    array_constraints: array_constraints,
    items: items,
    properties: merged_properties,
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
  ))
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

/// Reject a merged string constraint pair that validates nothing (minLength
/// > maxLength) instead of silently shipping an unsatisfiable form.
fn check_string_constraints(
  c: Option(types.StringConstraints),
  path: List(String),
) -> Result(Option(types.StringConstraints), ParseError) {
  case c {
    Some(StringConstraints(min_length: Some(min), max_length: Some(max), ..))
      if min > max
    ->
      Error(unsatisfiable(
        path,
        "minLength "
          <> int.to_string(min)
          <> " > maxLength "
          <> int.to_string(max),
      ))
    _ -> Ok(c)
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

/// Reject a merged number constraint pair that validates nothing (minimum
/// > maximum, or touching exclusive bounds) instead of silently shipping an
/// unsatisfiable form.
fn check_number_constraints(
  c: Option(types.NumberConstraints),
  path: List(String),
) -> Result(Option(types.NumberConstraints), ParseError) {
  case c {
    Some(NumberConstraints(minimum: Some(min), maximum: Some(max), ..))
      if min >. max
    ->
      Error(unsatisfiable(
        path,
        "minimum "
          <> float.to_string(min)
          <> " > maximum "
          <> float.to_string(max),
      ))
    Some(NumberConstraints(
      exclusive_minimum: Some(emin),
      exclusive_maximum: Some(emax),
      ..,
    ))
      if emin >=. emax
    ->
      Error(unsatisfiable(
        path,
        "exclusiveMinimum "
          <> float.to_string(emin)
          <> " >= exclusiveMaximum "
          <> float.to_string(emax),
      ))
    _ -> Ok(c)
  }
}

fn merge_array_constraints(
  base: Option(types.ArrayConstraints),
  overlay: Option(types.ArrayConstraints),
) -> Option(types.ArrayConstraints) {
  case base, overlay {
    Some(b), Some(o) ->
      Some(ArrayConstraints(
        min_items: combine(b.min_items, o.min_items, int.max),
        max_items: combine(b.max_items, o.max_items, int.min),
      ))
    b, o -> option.or(o, b)
  }
}

/// Reject a merged array constraint pair that validates nothing (minItems
/// > maxItems) instead of silently shipping an unsatisfiable form.
fn check_array_constraints(
  c: Option(types.ArrayConstraints),
  path: List(String),
) -> Result(Option(types.ArrayConstraints), ParseError) {
  case c {
    Some(ArrayConstraints(min_items: Some(min), max_items: Some(max)))
      if min > max
    ->
      Error(unsatisfiable(
        path,
        "minItems "
          <> int.to_string(min)
          <> " > maxItems "
          <> int.to_string(max),
      ))
    _ -> Ok(c)
  }
}
