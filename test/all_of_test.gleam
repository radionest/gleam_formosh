/// Tests for allOf composition merging (issue #54).
/// Unit level: composer.flatten_property on constructed records.
/// Integration level: parser.parse_schema on JSON.
import formosh/schema/composer
import formosh/schema/parser
import formosh/schema/properties
import formosh/schema/resolver
import formosh/schema/serializer
import formosh/schema/types.{
  ArrayConstraints, IntegerType, NumberConstraints, ObjectType, SchemaProperty,
  StringConstraints, StringType, UnsatisfiableSchema,
}
import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

fn prop_with(
  build: fn(types.SchemaProperty) -> types.SchemaProperty,
) -> types.SchemaProperty {
  build(types.empty_property())
}

pub fn flatten_merges_member_properties_in_order_test() {
  let member_a =
    prop_with(fn(p) {
      SchemaProperty(..p, properties: Some([#("a", types.empty_property())]))
    })
  let member_b =
    prop_with(fn(p) {
      SchemaProperty(..p, properties: Some([#("b", types.empty_property())]))
    })
  let node =
    prop_with(fn(p) {
      SchemaProperty(
        ..p,
        field_type: Some(ObjectType),
        properties: Some([#("local", types.empty_property())]),
        all_of: Some([member_a, member_b]),
      )
    })

  let assert Ok(flat) = composer.flatten_property(node)

  flat.all_of |> should.equal(None)
  let assert Some(props) = flat.properties
  properties.keys(props) |> should.equal(["a", "b", "local"])
}

pub fn flatten_collision_merges_field_by_field_test() {
  // «$ref base + local title override» must keep the inherited type and
  // constraints (design.md D3).
  let base_member =
    prop_with(fn(p) {
      SchemaProperty(
        ..p,
        properties: Some([
          #(
            "name",
            SchemaProperty(
              ..types.empty_property(),
              field_type: Some(StringType),
              string_constraints: Some(StringConstraints(
                min_length: Some(2),
                max_length: None,
                pattern: None,
                format: None,
              )),
            ),
          ),
        ]),
      )
    })
  let node =
    prop_with(fn(p) {
      SchemaProperty(
        ..p,
        properties: Some([
          #(
            "name",
            SchemaProperty(..types.empty_property(), title: Some("Custom")),
          ),
        ]),
        all_of: Some([base_member]),
      )
    })

  let assert Ok(flat) = composer.flatten_property(node)
  let assert Some(props) = flat.properties
  let assert Some(name) = properties.get(props, "name")

  name.title |> should.equal(Some("Custom"))
  name.field_type |> should.equal(Some(StringType))
  let assert Some(sc) = name.string_constraints
  sc.min_length |> should.equal(Some(2))
}

pub fn flatten_required_unions_test() {
  let m1 = prop_with(fn(p) { SchemaProperty(..p, required: ["a"]) })
  let m2 = prop_with(fn(p) { SchemaProperty(..p, required: ["b"]) })
  let node =
    prop_with(fn(p) {
      SchemaProperty(..p, required: ["a", "c"], all_of: Some([m1, m2]))
    })

  let assert Ok(flat) = composer.flatten_property(node)
  flat.required |> should.equal(["a", "b", "c"])
}

pub fn flatten_bounds_stricter_wins_test() {
  let loose =
    prop_with(fn(p) {
      SchemaProperty(
        ..p,
        number_constraints: Some(NumberConstraints(
          minimum: Some(0.0),
          maximum: Some(100.0),
          exclusive_minimum: None,
          exclusive_maximum: None,
          multiple_of: None,
        )),
      )
    })
  let strict =
    prop_with(fn(p) {
      SchemaProperty(
        ..p,
        number_constraints: Some(NumberConstraints(
          minimum: Some(18.0),
          maximum: Some(65.0),
          exclusive_minimum: None,
          exclusive_maximum: None,
          multiple_of: None,
        )),
      )
    })
  let node =
    prop_with(fn(p) {
      SchemaProperty(
        ..p,
        field_type: Some(IntegerType),
        all_of: Some([strict, loose]),
      )
    })

  let assert Ok(flat) = composer.flatten_property(node)
  let assert Some(nc) = flat.number_constraints
  nc.minimum |> should.equal(Some(18.0))
  nc.maximum |> should.equal(Some(65.0))
}

pub fn flatten_disjoint_string_constraints_combine_test() {
  let min =
    prop_with(fn(p) {
      SchemaProperty(
        ..p,
        string_constraints: Some(StringConstraints(
          min_length: Some(2),
          max_length: None,
          pattern: None,
          format: None,
        )),
      )
    })
  let max =
    prop_with(fn(p) {
      SchemaProperty(
        ..p,
        string_constraints: Some(StringConstraints(
          min_length: None,
          max_length: Some(10),
          pattern: None,
          format: None,
        )),
      )
    })
  let node =
    prop_with(fn(p) {
      SchemaProperty(
        ..p,
        field_type: Some(StringType),
        all_of: Some([min, max]),
      )
    })

  let assert Ok(flat) = composer.flatten_property(node)
  let assert Some(sc) = flat.string_constraints
  sc.min_length |> should.equal(Some(2))
  sc.max_length |> should.equal(Some(10))
}

pub fn flatten_crossed_array_bounds_is_error_test() {
  // minItems 5 ∧ maxItems 3 validates nothing — reject at parse instead of
  // renormalizing into a form the backend's real allOf validation refuses.
  let m1 =
    prop_with(fn(p) {
      SchemaProperty(
        ..p,
        array_constraints: Some(ArrayConstraints(
          min_items: Some(5),
          max_items: None,
        )),
      )
    })
  let m2 =
    prop_with(fn(p) {
      SchemaProperty(
        ..p,
        array_constraints: Some(ArrayConstraints(
          min_items: None,
          max_items: Some(3),
        )),
      )
    })
  let node = prop_with(fn(p) { SchemaProperty(..p, all_of: Some([m1, m2])) })
  composer.flatten_property(node) |> should.be_error
}

pub fn parse_crossed_array_bounds_is_error_test() {
  // The spec scenario at parse level: cross-member minItems/maxItems.
  // (Single-member-authored crossings never reach the composer for arrays —
  // the decoder normalizes them first, grandfathered #63 behavior.)
  let json =
    "{ \"type\": \"object\", \"properties\": { \"x\": { \"type\": \"array\", \"items\": { \"type\": \"string\" }, \"allOf\": [ { \"minItems\": 5 }, { \"maxItems\": 3 } ] } } }"
  parser.parse_schema(json) |> should.be_error
}

pub fn parse_crossed_string_bounds_is_error_test() {
  let json =
    "{ \"type\": \"object\", \"properties\": { \"x\": { \"type\": \"string\", \"allOf\": [ { \"minLength\": 5 }, { \"maxLength\": 3 } ] } } }"
  parser.parse_schema(json) |> should.be_error
}

pub fn parse_crossed_number_bounds_is_error_test() {
  let json =
    "{ \"type\": \"object\", \"properties\": { \"x\": { \"type\": \"number\", \"allOf\": [ { \"minimum\": 10 }, { \"maximum\": 5 } ] } } }"
  parser.parse_schema(json) |> should.be_error
}

pub fn parse_crossed_exclusive_bounds_is_error_test() {
  // exclusiveMinimum 5 ∧ exclusiveMaximum 5 admits no value.
  let json =
    "{ \"type\": \"object\", \"properties\": { \"x\": { \"type\": \"number\", \"allOf\": [ { \"exclusiveMinimum\": 5 }, { \"exclusiveMaximum\": 5 } ] } } }"
  parser.parse_schema(json) |> should.be_error
}

pub fn parse_empty_allof_skips_satisfiability_test() {
  // No effective members → pure no-op: authored crossed bounds keep
  // lenient single-schema semantics (grandfathered; runtime validation
  // still reports them).
  let json =
    "{ \"type\": \"object\", \"properties\": { \"x\": { \"type\": \"string\", \"minLength\": 5, \"maxLength\": 3, \"allOf\": [] } } }"
  let assert Ok(schema) = parser.parse_schema(json)
  let assert Some(x) = properties.get(schema.properties, "x")
  let assert Some(sc) = x.string_constraints
  sc.min_length |> should.equal(Some(5))
  sc.max_length |> should.equal(Some(3))
}

pub fn parse_true_only_allof_skips_satisfiability_test() {
  let json =
    "{ \"type\": \"object\", \"properties\": { \"x\": { \"type\": \"string\", \"minLength\": 5, \"maxLength\": 3, \"allOf\": [ true ] } } }"
  parser.parse_schema(json) |> should.be_ok
}

pub fn flatten_lifts_member_conditionals_test() {
  let rule =
    types.ConditionalRule(
      if_schema: types.empty_property(),
      then_schema: None,
      else_schema: None,
    )
  let member = prop_with(fn(p) { SchemaProperty(..p, conditionals: [rule]) })
  let direct_rule =
    types.ConditionalRule(
      if_schema: prop_with(fn(p) { SchemaProperty(..p, title: Some("direct")) }),
      then_schema: None,
      else_schema: None,
    )
  let node =
    prop_with(fn(p) {
      SchemaProperty(..p, conditionals: [direct_rule], all_of: Some([member]))
    })

  // Member rules first, the node's own rules last.
  let assert Ok(flat) = composer.flatten_property(node)
  flat.conditionals |> should.equal([rule, direct_rule])
}

pub fn flatten_nested_member_allof_collapses_test() {
  let inner =
    prop_with(fn(p) {
      SchemaProperty(..p, properties: Some([#("deep", types.empty_property())]))
    })
  let member = prop_with(fn(p) { SchemaProperty(..p, all_of: Some([inner])) })
  let node = prop_with(fn(p) { SchemaProperty(..p, all_of: Some([member])) })

  let assert Ok(flat) = composer.flatten_property(node)
  flat.all_of |> should.equal(None)
  let assert Some(props) = flat.properties
  properties.keys(props) |> should.equal(["deep"])
}

pub fn parse_lifts_members_to_root_test() {
  let json =
    "{ \"type\": \"object\", \"required\": [\"local\"], \"properties\": { \"local\": { \"type\": \"string\" } }, \"allOf\": [ { \"properties\": { \"from_member\": { \"type\": \"string\" } }, \"required\": [\"from_member\"] } ] }"
  let assert Ok(schema) = parser.parse_schema(json)
  properties.keys(schema.properties)
  |> should.equal(["from_member", "local"])
  schema.required |> should.equal(["from_member", "local"])
}

pub fn flatten_items_vs_items_collision_merges_test() {
  let m1 =
    prop_with(fn(p) {
      SchemaProperty(
        ..p,
        items: Some(
          prop_with(fn(i) {
            SchemaProperty(
              ..i,
              field_type: Some(ObjectType),
              properties: Some([#("a", types.empty_property())]),
            )
          }),
        ),
      )
    })
  let m2 =
    prop_with(fn(p) {
      SchemaProperty(
        ..p,
        items: Some(
          prop_with(fn(i) {
            SchemaProperty(
              ..i,
              title: Some("Row"),
              properties: Some([#("b", types.empty_property())]),
            )
          }),
        ),
      )
    })
  let node = prop_with(fn(p) { SchemaProperty(..p, all_of: Some([m1, m2])) })

  let assert Ok(flat) = composer.flatten_property(node)
  let assert Some(items) = flat.items
  items.title |> should.equal(Some("Row"))
  items.field_type |> should.equal(Some(ObjectType))
  let assert Some(props) = items.properties
  properties.keys(props) |> should.equal(["a", "b"])
}

pub fn flatten_collision_keeps_own_childs_allof_test() {
  let member =
    prop_with(fn(p) {
      SchemaProperty(
        ..p,
        properties: Some([
          #(
            "child",
            SchemaProperty(
              ..types.empty_property(),
              properties: Some([#("x", types.empty_property())]),
            ),
          ),
        ]),
      )
    })
  let own_child_mixin =
    prop_with(fn(p) {
      SchemaProperty(..p, properties: Some([#("y", types.empty_property())]))
    })
  let node =
    prop_with(fn(p) {
      SchemaProperty(
        ..p,
        properties: Some([
          #(
            "child",
            SchemaProperty(
              ..types.empty_property(),
              all_of: Some([own_child_mixin]),
            ),
          ),
        ]),
        all_of: Some([member]),
      )
    })

  let assert Ok(flat) = composer.flatten_property(node)
  let assert Some(props) = flat.properties
  let assert Some(child) = properties.get(props, "child")
  child.all_of |> should.equal(None)
  let assert Some(child_props) = child.properties
  properties.keys(child_props) |> should.equal(["x", "y"])
}

pub fn resolver_expands_ref_inside_all_of_test() {
  let base_def =
    prop_with(fn(p) {
      SchemaProperty(
        ..p,
        field_type: Some(ObjectType),
        properties: Some([#("from_base", types.empty_property())]),
      )
    })
  let schema =
    types.JsonSchema(
      title: None,
      description: None,
      field_type: ObjectType,
      properties: [],
      required: [],
      defs: Some(dict.from_list([#("base", base_def)])),
      conditionals: [],
      all_of: Some([
        prop_with(fn(p) { SchemaProperty(..p, ref: Some("#/$defs/base")) }),
      ]),
      string_constraints: None,
      number_constraints: None,
    )

  let assert Ok(resolved) = resolver.resolve_refs(schema)
  let assert Some([member]) = resolved.all_of
  member.ref |> should.equal(None)
  let assert Some(props) = member.properties
  properties.keys(props) |> should.equal(["from_base"])
}

pub fn resolver_circular_ref_inside_all_of_errors_test() {
  let looping =
    prop_with(fn(p) {
      SchemaProperty(
        ..p,
        all_of: Some([
          prop_with(fn(q) { SchemaProperty(..q, ref: Some("#/$defs/loop")) }),
        ]),
      )
    })
  let schema =
    types.JsonSchema(
      title: None,
      description: None,
      field_type: ObjectType,
      properties: [
        #(
          "field",
          prop_with(fn(p) { SchemaProperty(..p, ref: Some("#/$defs/loop")) }),
        ),
      ],
      required: [],
      defs: Some(dict.from_list([#("loop", looping)])),
      conditionals: [],
      all_of: None,
      string_constraints: None,
      number_constraints: None,
    )

  resolver.resolve_refs(schema) |> should.be_error
}

// --- Integration: parser.parse_schema (specs/schema-composition) ---

pub fn parse_allof_plain_members_issue54_repro_test() {
  let json =
    "{ \"type\": \"object\", \"allOf\": [ { \"properties\": { \"a\": { \"type\": \"string\" } } }, { \"properties\": { \"b\": { \"type\": \"string\" } } } ] }"
  let assert Ok(schema) = parser.parse_schema(json)
  properties.keys(schema.properties) |> should.equal(["a", "b"])
  schema.all_of |> should.equal(None)
}

pub fn parse_allof_ref_base_plus_extras_test() {
  let json =
    "{ \"type\": \"object\", \"$defs\": { \"base\": { \"type\": \"object\", \"properties\": { \"id\": { \"type\": \"integer\" } }, \"required\": [\"id\"] } }, \"allOf\": [ { \"$ref\": \"#/$defs/base\" }, { \"properties\": { \"extra\": { \"type\": \"string\" } } } ] }"
  let assert Ok(schema) = parser.parse_schema(json)
  properties.keys(schema.properties) |> should.equal(["id", "extra"])
  schema.required |> should.equal(["id"])
}

pub fn parse_allof_two_ref_mixins_test() {
  let json =
    "{ \"type\": \"object\", \"$defs\": { \"a\": { \"properties\": { \"a1\": { \"type\": \"string\" } }, \"required\": [\"a1\"] }, \"b\": { \"properties\": { \"b1\": { \"type\": \"string\" } }, \"required\": [\"b1\"] } }, \"allOf\": [ { \"$ref\": \"#/$defs/a\" }, { \"$ref\": \"#/$defs/b\" } ] }"
  let assert Ok(schema) = parser.parse_schema(json)
  properties.keys(schema.properties) |> should.equal(["a1", "b1"])
  schema.required |> should.equal(["a1", "b1"])
}

pub fn parse_allof_title_override_keeps_base_type_test() {
  let json =
    "{ \"type\": \"object\", \"$defs\": { \"base\": { \"properties\": { \"name\": { \"type\": \"string\", \"minLength\": 2 } } } }, \"allOf\": [ { \"$ref\": \"#/$defs/base\" } ], \"properties\": { \"name\": { \"title\": \"Custom\" } } }"
  let assert Ok(schema) = parser.parse_schema(json)
  let assert Some(name) = properties.get(schema.properties, "name")
  name.title |> should.equal(Some("Custom"))
  name.field_type |> should.equal(Some(StringType))
  let assert Some(sc) = name.string_constraints
  sc.min_length |> should.equal(Some(2))
}

pub fn parse_allof_conditional_member_lifted_and_plain_merged_test() {
  // Mixed member: if/then AND plain properties both contribute.
  let json =
    "{ \"type\": \"object\", \"properties\": { \"kind\": { \"type\": \"string\" } }, \"allOf\": [ { \"if\": { \"properties\": { \"kind\": { \"const\": \"x\" } } }, \"then\": { \"properties\": { \"extra\": { \"type\": \"string\" } } }, \"properties\": { \"always\": { \"type\": \"string\" } } } ] }"
  let assert Ok(schema) = parser.parse_schema(json)
  properties.has_key(schema.properties, "always") |> should.be_true
  schema.conditionals |> list.length |> should.equal(1)
}

pub fn parse_direct_if_beside_allof_kept_test() {
  let json =
    "{ \"type\": \"object\", \"properties\": { \"kind\": { \"type\": \"string\" } }, \"if\": { \"properties\": { \"kind\": { \"const\": \"a\" } } }, \"then\": { \"properties\": { \"direct\": { \"type\": \"string\" } } }, \"allOf\": [ { \"if\": { \"properties\": { \"kind\": { \"const\": \"b\" } } }, \"then\": { \"properties\": { \"member\": { \"type\": \"string\" } } } } ] }"
  let assert Ok(schema) = parser.parse_schema(json)
  // Member rule first (lifted), direct rule last.
  let assert [member_rule, direct_rule] = schema.conditionals
  let assert Some(member_then) = member_rule.then_schema
  let assert Some(member_props) = member_then.properties
  properties.has_key(member_props, "member") |> should.be_true
  let assert Some(direct_then) = direct_rule.then_schema
  let assert Some(direct_props) = direct_then.properties
  properties.has_key(direct_props, "direct") |> should.be_true
}

pub fn parse_allof_inside_then_branch_flattened_test() {
  let json =
    "{ \"type\": \"object\", \"properties\": { \"kind\": { \"type\": \"string\" } }, \"if\": { \"properties\": { \"kind\": { \"const\": \"x\" } } }, \"then\": { \"allOf\": [ { \"properties\": { \"revealed\": { \"type\": \"string\" } } } ] } }"
  let assert Ok(schema) = parser.parse_schema(json)
  let assert [rule] = schema.conditionals
  let assert Some(then_schema) = rule.then_schema
  let assert Some(props) = then_schema.properties
  properties.keys(props) |> should.equal(["revealed"])
}

pub fn parse_property_level_allof_test() {
  let json =
    "{ \"type\": \"object\", \"properties\": { \"nested\": { \"type\": \"object\", \"allOf\": [ { \"properties\": { \"x\": { \"type\": \"string\" } } }, { \"properties\": { \"y\": { \"type\": \"string\" } } } ] } } }"
  let assert Ok(schema) = parser.parse_schema(json)
  let assert Some(nested) = properties.get(schema.properties, "nested")
  // Spec: no residual composition state at ANY depth post-parse.
  nested.all_of |> should.equal(None)
  let assert Some(props) = nested.properties
  properties.keys(props) |> should.equal(["x", "y"])
}

pub fn parse_array_items_allof_test() {
  let json =
    "{ \"type\": \"object\", \"properties\": { \"rows\": { \"type\": \"array\", \"items\": { \"type\": \"object\", \"allOf\": [ { \"properties\": { \"cell\": { \"type\": \"string\" } } } ] } } } }"
  let assert Ok(schema) = parser.parse_schema(json)
  let assert Some(rows) = properties.get(schema.properties, "rows")
  let assert Some(items) = rows.items
  let assert Some(props) = items.properties
  properties.keys(props) |> should.equal(["cell"])
}

pub fn parse_circular_ref_through_allof_errors_test() {
  let json =
    "{ \"type\": \"object\", \"$defs\": { \"node\": { \"allOf\": [ { \"$ref\": \"#/$defs/node\" } ] } }, \"properties\": { \"root\": { \"$ref\": \"#/$defs/node\" } } }"
  parser.parse_schema(json) |> should.be_error
}

pub fn parse_empty_allof_noop_test() {
  let json =
    "{ \"type\": \"object\", \"allOf\": [], \"properties\": { \"a\": { \"type\": \"string\" } } }"
  let assert Ok(schema) = parser.parse_schema(json)
  properties.keys(schema.properties) |> should.equal(["a"])
}

pub fn parse_required_union_across_members_test() {
  let json =
    "{ \"type\": \"object\", \"required\": [\"a\", \"c\"], \"allOf\": [ { \"properties\": { \"a\": { \"type\": \"string\" }, \"b\": { \"type\": \"string\" }, \"c\": { \"type\": \"string\" } }, \"required\": [\"a\", \"b\"] } ] }"
  let assert Ok(schema) = parser.parse_schema(json)
  schema.required |> should.equal(["a", "b", "c"])
}

pub fn parse_allof_true_member_is_noop_test() {
  // `true` is the JSON Schema no-op member (design.md D8): it is skipped
  // and the remaining members still compose.
  let json =
    "{ \"type\": \"object\", \"allOf\": [ true, { \"properties\": { \"a\": { \"type\": \"string\" } } } ], \"properties\": { \"local\": { \"type\": \"string\" } } }"
  let assert Ok(schema) = parser.parse_schema(json)
  properties.keys(schema.properties) |> should.equal(["a", "local"])
}

pub fn parse_allof_false_member_is_parse_error_test() {
  // `false` makes the composition unsatisfiable — reject loudly instead of
  // rendering a form the backend's real allOf validation would refuse.
  let json =
    "{ \"type\": \"object\", \"allOf\": [ false, { \"properties\": { \"a\": { \"type\": \"string\" } } } ] }"
  parser.parse_schema(json) |> should.be_error
}

pub fn parse_allof_malformed_member_is_parse_error_test() {
  // A member that is no schema at all fails the parse (design.md D8) —
  // silently dropping it would silently drop its validation constraints.
  let json = "{ \"type\": \"object\", \"allOf\": [ 42 ] }"
  parser.parse_schema(json) |> should.be_error
}

pub fn parse_property_level_allof_false_member_is_parse_error_test() {
  // Same strictness through the property-decoder call site.
  let json =
    "{ \"type\": \"object\", \"properties\": { \"x\": { \"type\": \"object\", \"allOf\": [ false ] } } }"
  parser.parse_schema(json) |> should.be_error
}

pub fn parse_ref_to_def_carrying_allof_test() {
  let json =
    "{ \"type\": \"object\", \"$defs\": { \"d\": { \"type\": \"object\", \"allOf\": [ { \"properties\": { \"inner\": { \"type\": \"string\" } } } ] } }, \"properties\": { \"x\": { \"$ref\": \"#/$defs/d\" } } }"
  let assert Ok(schema) = parser.parse_schema(json)
  let assert Some(x) = properties.get(schema.properties, "x")
  x.all_of |> should.equal(None)
  let assert Some(props) = x.properties
  properties.keys(props) |> should.equal(["inner"])
}

pub fn parse_collision_local_property_with_allof_test() {
  // Root-level collision: a member declares addr.street; the parent's own
  // addr carries a nested allOf mixin adding city. Both must survive.
  let json =
    "{ \"type\": \"object\", \"allOf\": [ { \"properties\": { \"addr\": { \"type\": \"object\", \"properties\": { \"street\": { \"type\": \"string\" } } } } } ], \"properties\": { \"addr\": { \"allOf\": [ { \"properties\": { \"city\": { \"type\": \"string\" } } } ] } } }"
  let assert Ok(schema) = parser.parse_schema(json)
  let assert Some(addr) = properties.get(schema.properties, "addr")
  addr.all_of |> should.equal(None)
  let assert Some(props) = addr.properties
  properties.keys(props) |> should.equal(["street", "city"])
}

pub fn parse_ref_and_local_allof_local_member_wins_test() {
  // Both the $ref-bearing node and its referenced definition carry allOf:
  // referenced members merge first, so local members override — the same
  // local-over-referenced precedence as plain $ref keyword merging.
  let json =
    "{ \"type\": \"object\", \"$defs\": { \"a\": { \"type\": \"string\", \"allOf\": [ { \"title\": \"def-mixin\" } ] } }, \"properties\": { \"x\": { \"$ref\": \"#/$defs/a\", \"allOf\": [ { \"title\": \"local-mixin\" } ] } } }"
  let assert Ok(schema) = parser.parse_schema(json)
  let assert Some(x) = properties.get(schema.properties, "x")
  x.title |> should.equal(Some("local-mixin"))
}

pub fn parse_ref_with_local_allof_ref_member_resolves_test() {
  // A $ref-bearing node's own allOf members pass through nested-$ref
  // resolution before merging — otherwise the unresolved ref reaches the
  // composer and resurrects a `ref` on the flattened node.
  let json =
    "{ \"type\": \"object\", \"$defs\": { \"a\": { \"type\": \"string\" }, \"b\": { \"title\": \"from-b\" } }, \"properties\": { \"x\": { \"$ref\": \"#/$defs/a\", \"allOf\": [ { \"$ref\": \"#/$defs/b\" } ] } } }"
  let assert Ok(schema) = parser.parse_schema(json)
  let assert Some(x) = properties.get(schema.properties, "x")
  x.title |> should.equal(Some("from-b"))
  x.ref |> should.equal(None)
}

// --- Root-as-SchemaProperty (issue #70) ---

pub fn parse_allof_scalar_member_types_root_test() {
  // Issue #70: the ObjectType default must land AFTER composition. The
  // serializer is the root type's only consumer — assert the round-trip.
  let json = "{ \"allOf\": [ { \"type\": \"string\", \"minLength\": 3 } ] }"
  let assert Ok(schema) = parser.parse_schema(json)
  schema.field_type |> should.equal(StringType)
  let assert Some(sc) = schema.string_constraints
  sc.min_length |> should.equal(Some(3))
  serializer.schema_to_json(schema)
  |> json.to_string
  |> string.contains("\"type\":\"string\"")
  |> should.be_true
}

pub fn parse_typeless_composition_defaults_object_test() {
  let json =
    "{ \"allOf\": [ { \"properties\": { \"a\": { \"type\": \"string\" } } } ] }"
  let assert Ok(schema) = parser.parse_schema(json)
  schema.field_type |> should.equal(ObjectType)
  properties.has_key(schema.properties, "a") |> should.be_true
}

pub fn parse_authored_root_type_kept_test() {
  let json =
    "{ \"type\": \"object\", \"allOf\": [ { \"properties\": { \"a\": { \"type\": \"string\" } } } ] }"
  let assert Ok(schema) = parser.parse_schema(json)
  schema.field_type |> should.equal(ObjectType)
}

pub fn parse_root_ref_resolves_test() {
  let json =
    "{ \"$ref\": \"#/$defs/base\", \"$defs\": { \"base\": { \"type\": \"object\", \"properties\": { \"a\": { \"type\": \"string\" } } } } }"
  let assert Ok(schema) = parser.parse_schema(json)
  properties.has_key(schema.properties, "a") |> should.be_true
}

pub fn parse_root_ref_circular_is_error_test() {
  let json =
    "{ \"$ref\": \"#/$defs/a\", \"$defs\": { \"a\": { \"$ref\": \"#/$defs/a\" } } }"
  parser.parse_schema(json) |> should.be_error
}

// --- Strict type intersection (issue #68 follow-on) ---

pub fn parse_root_type_conflict_is_error_test() {
  // Disjoint intersection validates nothing — same class as a false member.
  let json = "{ \"type\": \"object\", \"allOf\": [ { \"type\": \"string\" } ] }"
  parser.parse_schema(json) |> should.be_error
}

pub fn parse_property_type_conflict_is_error_test() {
  let json =
    "{ \"type\": \"object\", \"properties\": { \"x\": { \"type\": \"string\", \"allOf\": [ { \"type\": \"boolean\" } ] } } }"
  parser.parse_schema(json) |> should.be_error
}

pub fn parse_property_type_conflict_names_path_test() {
  // The spec requires the unsatisfiable-schema error to name the offending
  // property's path; pin the variant and the #/x breadcrumb so an unrelated
  // future parse failure can't keep this green.
  let json =
    "{ \"type\": \"object\", \"properties\": { \"x\": { \"type\": \"string\", \"allOf\": [ { \"type\": \"boolean\" } ] } } }"
  let assert Error(UnsatisfiableSchema(msg)) = parser.parse_schema(json)
  msg |> string.contains("#/x") |> should.be_true
  msg |> string.contains("string") |> should.be_true
  msg |> string.contains("boolean") |> should.be_true
}

pub fn parse_number_member_refines_root_to_integer_test() {
  let json =
    "{ \"type\": \"number\", \"allOf\": [ { \"type\": \"integer\" } ] }"
  let assert Ok(schema) = parser.parse_schema(json)
  schema.field_type |> should.equal(IntegerType)
}

pub fn parse_integer_refinement_at_property_level_test() {
  // Both orders must narrow, not conflict and not stay number.
  let json =
    "{ \"type\": \"object\", \"properties\": { \"n\": { \"type\": \"integer\", \"allOf\": [ { \"type\": \"number\" } ] } } }"
  let assert Ok(schema) = parser.parse_schema(json)
  let assert Some(n) = properties.get(schema.properties, "n")
  n.field_type |> should.equal(Some(IntegerType))
}

// --- Mixed plain/exclusive bound crossings (post-PR review follow-on) ---

pub fn parse_crossed_min_exclusive_max_is_error_test() {
  // minimum 10 ∧ exclusiveMaximum 5 admits no value (x >= 10 and x < 5).
  let json =
    "{ \"type\": \"object\", \"properties\": { \"x\": { \"type\": \"number\", \"allOf\": [ { \"minimum\": 10 }, { \"exclusiveMaximum\": 5 } ] } } }"
  parser.parse_schema(json) |> should.be_error
}

pub fn parse_crossed_exclusive_min_max_is_error_test() {
  // exclusiveMinimum 5 ∧ maximum 5 admits no value (x > 5 and x <= 5).
  let json =
    "{ \"type\": \"object\", \"properties\": { \"x\": { \"type\": \"number\", \"allOf\": [ { \"exclusiveMinimum\": 5 }, { \"maximum\": 5 } ] } } }"
  parser.parse_schema(json) |> should.be_error
}

pub fn parse_authored_crossed_bounds_with_member_is_error_test() {
  // Any effective member (even one touching nothing) opts the node into
  // strict satisfiability of its MERGED constraints — including bounds the
  // node authored itself. Only an empty/true-only allOf stays lenient.
  let json =
    "{ \"type\": \"object\", \"properties\": { \"x\": { \"type\": \"string\", \"minLength\": 5, \"maxLength\": 3, \"allOf\": [ { \"title\": \"t\" } ] } } }"
  parser.parse_schema(json) |> should.be_error
}
