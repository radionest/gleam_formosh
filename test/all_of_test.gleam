/// Tests for allOf composition merging (issue #54).
/// Unit level: composer.flatten_property / flatten_schema on constructed
/// records. Integration level (Task 5): parser.parse_schema on JSON.
import formosh/schema/composer
import formosh/schema/properties
import formosh/schema/resolver
import formosh/schema/types.{
  ArrayConstraints, IntegerType, NumberConstraints, ObjectType, SchemaProperty,
  StringConstraints, StringType,
}
import gleam/dict
import gleam/option.{None, Some}
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

  let flat = composer.flatten_property(node)

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

  let flat = composer.flatten_property(node)
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

  composer.flatten_property(node).required |> should.equal(["a", "b", "c"])
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

  let assert Some(nc) = composer.flatten_property(node).number_constraints
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

  let assert Some(sc) = composer.flatten_property(node).string_constraints
  sc.min_length |> should.equal(Some(2))
  sc.max_length |> should.equal(Some(10))
}

pub fn flatten_crossed_array_bounds_renormalize_test() {
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

  // minItems wins on unsatisfiable bounds — same normalization as the
  // parser's extract_array_constraints, or ensure_min_items wedges the form.
  composer.flatten_property(node).array_constraints
  |> should.equal(
    Some(ArrayConstraints(min_items: Some(5), max_items: Some(5))),
  )
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
  let flat = composer.flatten_property(node)
  flat.conditionals |> should.equal([rule, direct_rule])
}

pub fn flatten_nested_member_allof_collapses_test() {
  let inner =
    prop_with(fn(p) {
      SchemaProperty(..p, properties: Some([#("deep", types.empty_property())]))
    })
  let member = prop_with(fn(p) { SchemaProperty(..p, all_of: Some([inner])) })
  let node = prop_with(fn(p) { SchemaProperty(..p, all_of: Some([member])) })

  let flat = composer.flatten_property(node)
  flat.all_of |> should.equal(None)
  let assert Some(props) = flat.properties
  properties.keys(props) |> should.equal(["deep"])
}

pub fn flatten_schema_lifts_members_to_root_test() {
  let member =
    prop_with(fn(p) {
      SchemaProperty(
        ..p,
        properties: Some([#("from_member", types.empty_property())]),
        required: ["from_member"],
      )
    })
  let schema =
    types.JsonSchema(
      title: None,
      description: None,
      field_type: ObjectType,
      properties: [#("local", types.empty_property())],
      required: ["local"],
      defs: None,
      conditionals: [],
      all_of: Some([member]),
      string_constraints: None,
      number_constraints: None,
    )

  let flat = composer.flatten_schema(schema)
  flat.all_of |> should.equal(None)
  properties.keys(flat.properties) |> should.equal(["from_member", "local"])
  flat.required |> should.equal(["from_member", "local"])
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
