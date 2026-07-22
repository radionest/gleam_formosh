import formosh/schema/parser
import formosh/schema/types
import gleam/list
import gleam/option
import gleam/string
import gleeunit/should

pub fn anyof_optional_scalar_collapses_test() {
  let schema_json =
    "{\"type\":\"object\",\"properties\":{\"age\":{\"anyOf\":[{\"type\":\"integer\"},{\"type\":\"null\"}]}}}"
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(#(_, age)) = list.first(schema.properties)
  age.field_type |> should.equal(option.Some(types.IntegerType))
  age.nullable |> should.be_true()
  age.any_of |> should.equal(option.None)
}

pub fn type_array_with_null_sets_nullable_test() {
  // #42 nullable-union coverage: test/union_type_render_test.gleam already
  // pins that a ["integer","null"] type array renders without crashing;
  // this asserts the structural side of the same fix — `nullable` must
  // also flip, alongside the pre-existing first-known-type collapse.
  let schema_json =
    "{\"type\":\"object\",\"properties\":{\"age\":{\"type\":[\"integer\",\"null\"]}}}"
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(#(_, age)) = list.first(schema.properties)
  age.field_type |> should.equal(option.Some(types.IntegerType))
  age.nullable |> should.be_true()
}

pub fn anyof_two_members_parses_test() {
  let schema_json =
    "{\"type\":\"object\",\"properties\":{\"value\":{\"anyOf\":[{\"type\":\"integer\"},{\"type\":\"string\"}]}}}"
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(#(_, value)) = list.first(schema.properties)
  let assert option.Some(members) = value.any_of
  list.length(members) |> should.equal(2)
  let assert [first, second] = members
  first.field_type |> should.equal(option.Some(types.IntegerType))
  second.field_type |> should.equal(option.Some(types.StringType))
}

pub fn anyof_lenient_skips_malformed_member_test() {
  // 42 is not a schema (nor the allOf-style boolean no-op) — it fails
  // property_decoder and is dropped at parse time (extract_any_of), leaving
  // the one valid member. With no null sibling here, the composer's
  // normalize_any_of then collapses that single survivor into the node
  // like any other single-member anyOf.
  let schema_json =
    "{\"type\":\"object\",\"properties\":{\"value\":{\"anyOf\":[{\"type\":\"integer\"}, 42]}}}"
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(#(_, value)) = list.first(schema.properties)
  value.field_type |> should.equal(option.Some(types.IntegerType))
  value.nullable |> should.be_false()
  value.any_of |> should.equal(option.None)
}

pub fn anyof_empty_list_is_none_test() {
  let schema_json =
    "{\"type\":\"object\",\"properties\":{\"value\":{\"anyOf\":[]}}}"
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(#(_, value)) = list.first(schema.properties)
  value.any_of |> should.equal(option.None)
}

pub fn anyof_member_ref_resolves_test() {
  // Resolver walks into anyOf members and resolves the $ref (ref cleared,
  // Sub's content merged in) before the composer's normalize_any_of
  // collapses the single surviving non-null member into the node: Sub's
  // properties land directly on `value`, and the null sibling only sets
  // `nullable`.
  let schema_json =
    "{\"type\":\"object\",\"properties\":{\"value\":{\"anyOf\":[{\"$ref\":\"#/$defs/Sub\"},{\"type\":\"null\"}]}},\"$defs\":{\"Sub\":{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}}}}}"
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(#(_, value)) = list.first(schema.properties)

  value.field_type |> should.equal(option.Some(types.ObjectType))
  value.nullable |> should.be_true()
  value.any_of |> should.equal(option.None)
  let assert option.Some(sub_properties) = value.properties
  let assert Ok(name_property) = list.key_find(sub_properties, "name")
  name_property.field_type |> should.equal(option.Some(types.StringType))
}

pub fn anyof_circular_ref_in_defs_errors_test() {
  // A $defs entry whose own anyOf references itself must be caught by the
  // same visited-set cycle protection as oneOf/allOf/properties — a parse
  // error, not a hang.
  let schema_json =
    "{\"type\":\"object\",\"properties\":{\"node\":{\"$ref\":\"#/$defs/Node\"}},\"$defs\":{\"Node\":{\"type\":\"object\",\"anyOf\":[{\"$ref\":\"#/$defs/Node\"}]}}}"
  case parser.parse_schema(schema_json) {
    Error(types.UnexpectedValue(msg)) ->
      should.equal(string.contains(msg, "Circular"), True)
    Error(_) -> panic as "Expected UnexpectedValue circular reference error"
    Ok(_) -> panic as "Expected a circular reference error, got Ok"
  }
}

// --- Task 4: composer normalization (collapse / survive / strict / lenient) ---
// Spec: openspec/changes/add-anyof-union-support/specs/schema-composition/spec.md
// §"A single non-null anyOf member merges into the node"
// §"Multi-member anyOf survives as flattened union state"
// §"anyOf extraction is lenient"

pub fn anyof_constrained_member_keeps_constraints_test() {
  let schema_json =
    "{\"type\":\"object\",\"properties\":{\"value\":{\"anyOf\":[{\"type\":\"integer\",\"minimum\":0},{\"type\":\"null\"}]}}}"
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(#(_, value)) = list.first(schema.properties)
  value.field_type |> should.equal(option.Some(types.IntegerType))
  value.nullable |> should.be_true()
  value.any_of |> should.equal(option.None)
  let assert option.Some(nc) = value.number_constraints
  nc.minimum |> should.equal(option.Some(0.0))
}

pub fn anyof_array_member_keeps_items_test() {
  let schema_json =
    "{\"type\":\"object\",\"properties\":{\"value\":{\"anyOf\":[{\"type\":\"array\",\"items\":{\"type\":\"integer\"}},{\"type\":\"null\"}]}}}"
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(#(_, value)) = list.first(schema.properties)
  value.field_type |> should.equal(option.Some(types.ArrayType))
  value.nullable |> should.be_true()
  value.any_of |> should.equal(option.None)
  let assert option.Some(items) = value.items
  items.field_type |> should.equal(option.Some(types.IntegerType))
}

pub fn anyof_parent_keys_win_over_member_test() {
  // Parent-declared title/default beside anyOf survive the collapse; only
  // the type comes from the surviving member. `default: null` decodes to
  // None (decode.optional treats JSON null as field absence, same as no
  // default declared at all), so this also pins that the merge doesn't
  // invent a default from the member (which has none either).
  let schema_json =
    "{\"type\":\"object\",\"properties\":{\"age\":{\"title\":\"Age\",\"default\":null,\"anyOf\":[{\"type\":\"integer\",\"title\":\"int\"},{\"type\":\"null\"}]}}}"
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(#(_, age)) = list.first(schema.properties)
  age.title |> should.equal(option.Some("Age"))
  age.default |> should.equal(option.None)
  age.field_type |> should.equal(option.Some(types.IntegerType))
  age.nullable |> should.be_true()
  age.any_of |> should.equal(option.None)
}

pub fn anyof_disjoint_parent_type_is_error_test() {
  let schema_json =
    "{\"type\":\"string\",\"anyOf\":[{\"type\":\"integer\"},{\"type\":\"null\"}]}"
  let assert Error(types.UnsatisfiableSchema(msg)) =
    parser.parse_schema(schema_json)
  msg |> string.contains("integer") |> should.be_true()
  msg |> string.contains("string") |> should.be_true()
}

pub fn anyof_multi_member_survives_nullable_false_test() {
  let schema_json =
    "{\"type\":\"object\",\"properties\":{\"value\":{\"anyOf\":[{\"type\":\"integer\"},{\"type\":\"string\"}]}}}"
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(#(_, value)) = list.first(schema.properties)
  value.nullable |> should.be_false()
  let assert option.Some(members) = value.any_of
  list.length(members) |> should.equal(2)
}

pub fn anyof_nullable_union_survives_test() {
  let schema_json =
    "{\"type\":\"object\",\"properties\":{\"value\":{\"anyOf\":[{\"type\":\"integer\"},{\"type\":\"string\"},{\"type\":\"null\"}]}}}"
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(#(_, value)) = list.first(schema.properties)
  value.nullable |> should.be_true()
  let assert option.Some(members) = value.any_of
  list.length(members) |> should.equal(2)
  let assert [first, second] = members
  first.field_type |> should.equal(option.Some(types.IntegerType))
  second.field_type |> should.equal(option.Some(types.StringType))
}

pub fn anyof_nested_member_collapses_before_surviving_test() {
  // The first branch is itself an optional-scalar anyOf; it must collapse
  // to a plain integer (nullable: True, any_of: None) before the outer
  // anyOf decides it survives alongside the string branch — no residual
  // inner composition state on the surviving member.
  let schema_json =
    "{\"type\":\"object\",\"properties\":{\"value\":{\"anyOf\":[{\"anyOf\":[{\"type\":\"integer\",\"minimum\":5},{\"type\":\"null\"}]},{\"type\":\"string\"}]}}}"
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(#(_, value)) = list.first(schema.properties)
  value.nullable |> should.be_false()
  let assert option.Some(members) = value.any_of
  list.length(members) |> should.equal(2)
  let assert [first, second] = members
  first.field_type |> should.equal(option.Some(types.IntegerType))
  first.nullable |> should.be_true()
  first.any_of |> should.equal(option.None)
  let assert option.Some(nc) = first.number_constraints
  nc.minimum |> should.equal(option.Some(5.0))
  second.field_type |> should.equal(option.Some(types.StringType))
}

pub fn anyof_lenient_skips_malformed_member_with_null_test() {
  // Spec-exact lenient scenario: a malformed member alongside a null
  // member still normalizes to a nullable integer.
  let schema_json =
    "{\"type\":\"object\",\"properties\":{\"value\":{\"anyOf\":[{\"type\":\"integer\"}, 42, {\"type\":\"null\"}]}}}"
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(#(_, value)) = list.first(schema.properties)
  value.field_type |> should.equal(option.Some(types.IntegerType))
  value.nullable |> should.be_true()
  value.any_of |> should.equal(option.None)
}

pub fn anyof_all_null_resolves_to_null_type_test() {
  let schema_json =
    "{\"type\":\"object\",\"properties\":{\"value\":{\"anyOf\":[{\"type\":\"null\"}]}}}"
  let assert Ok(schema) = parser.parse_schema(schema_json)
  let assert Ok(#(_, value)) = list.first(schema.properties)
  value.field_type |> should.equal(option.Some(types.NullType))
  value.any_of |> should.equal(option.None)
  value.nullable |> should.be_true()
}
