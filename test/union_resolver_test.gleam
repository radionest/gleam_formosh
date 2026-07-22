/// Unit tests for `formosh/form/union_resolver`: branch inference and
/// materialization (design D4/D8,
/// openspec/changes/add-anyof-union-support/design.md).
import formosh/form/path
import formosh/form/union_resolver
import formosh/schema/properties
import formosh/schema/types.{
  type JsonSchema, type SchemaProperty, ArrayType, ArrayValue, ConditionalRule,
  IntegerType, IntegerValue, JsonSchema, NumberConstraints, NumberType,
  NumberValue, ObjectType, ObjectValue, RenderHints, SchemaProperty, StringType,
  StringValue, empty_hints, empty_number_constraints, empty_property,
}
import gleam/option.{None, Some}
import gleeunit/should

fn int_member() -> SchemaProperty {
  SchemaProperty(..empty_property(), field_type: Some(IntegerType))
}

fn str_member() -> SchemaProperty {
  SchemaProperty(..empty_property(), field_type: Some(StringType))
}

fn int_str_union() -> SchemaProperty {
  SchemaProperty(..empty_property(), any_of: Some([int_member(), str_member()]))
}

fn test_schema(props: List(#(String, SchemaProperty))) -> JsonSchema {
  JsonSchema(
    title: None,
    description: None,
    field_type: ObjectType,
    properties: props,
    required: [],
    defs: None,
    conditionals: [],
    all_of: None,
    string_constraints: None,
    number_constraints: None,
  )
}

// --- active_branch_index ---

pub fn active_branch_index_stored_selection_wins_test() {
  let field_path = path.from_field_name("value")
  let selected = [#(field_path, 1)]
  // Value alone would infer branch 0 (integer) — the stored selection must
  // win over inference regardless.
  union_resolver.active_branch_index(
    int_str_union(),
    Some(IntegerValue(42)),
    field_path,
    selected,
  )
  |> should.equal(1)
}

pub fn active_branch_index_infers_string_branch_test() {
  let field_path = path.from_field_name("value")
  union_resolver.active_branch_index(
    int_str_union(),
    Some(StringValue("hi")),
    field_path,
    [],
  )
  |> should.equal(1)
}

pub fn active_branch_index_infers_object_by_key_overlap_test() {
  let member_a =
    SchemaProperty(
      ..empty_property(),
      field_type: Some(ObjectType),
      properties: Some([#("foo", empty_property())]),
    )
  let member_b =
    SchemaProperty(
      ..empty_property(),
      field_type: Some(ObjectType),
      properties: Some([#("bar", empty_property())]),
    )
  let prop =
    SchemaProperty(..empty_property(), any_of: Some([member_a, member_b]))
  let field_path = path.from_field_name("value")
  let value = Some(ObjectValue([#("bar", StringValue("x"))]))
  union_resolver.active_branch_index(prop, value, field_path, [])
  |> should.equal(1)
}

pub fn active_branch_index_defaults_to_zero_test() {
  let field_path = path.from_field_name("value")
  union_resolver.active_branch_index(int_str_union(), None, field_path, [])
  |> should.equal(0)
}

pub fn active_branch_index_integer_value_matches_number_type_test() {
  // IntegerValue matches IntegerType *or* NumberType — here only the
  // second member declares NumberType, so it must be picked.
  let number_member =
    SchemaProperty(..empty_property(), field_type: Some(NumberType))
  let prop =
    SchemaProperty(
      ..empty_property(),
      any_of: Some([str_member(), number_member]),
    )
  let field_path = path.from_field_name("value")
  union_resolver.active_branch_index(
    prop,
    Some(IntegerValue(3)),
    field_path,
    [],
  )
  |> should.equal(1)
}

pub fn active_branch_index_float_value_matches_number_type_only_test() {
  // NumberValue (float) must NOT match IntegerType — only NumberType.
  let number_member =
    SchemaProperty(..empty_property(), field_type: Some(NumberType))
  let prop =
    SchemaProperty(
      ..empty_property(),
      any_of: Some([int_member(), number_member]),
    )
  let field_path = path.from_field_name("value")
  union_resolver.active_branch_index(
    prop,
    Some(NumberValue(3.5)),
    field_path,
    [],
  )
  |> should.equal(1)
}

// --- materialize_branch ---

pub fn materialize_branch_adopts_member_content_test() {
  let constrained_int =
    SchemaProperty(
      ..int_member(),
      number_constraints: Some(
        NumberConstraints(..empty_number_constraints(), minimum: Some(1.0)),
      ),
    )
  let hints = RenderHints(..empty_hints(), placeholder: Some("ph"))
  let prop =
    SchemaProperty(
      ..empty_property(),
      any_of: Some([constrained_int, str_member()]),
      title: Some("Value"),
      description: Some("desc"),
      nullable: True,
      render_hints: hints,
    )

  let result = union_resolver.materialize_branch(prop, 0)

  result.field_type |> should.equal(Some(IntegerType))
  result.number_constraints
  |> should.equal(constrained_int.number_constraints)
  // Node-level metadata stays the parent's, not the member's.
  result.title |> should.equal(Some("Value"))
  result.description |> should.equal(Some("desc"))
  result.render_hints |> should.equal(hints)
  result.nullable |> should.be_true()
}

pub fn materialize_branch_adopts_member_properties_test() {
  let object_member =
    SchemaProperty(
      ..empty_property(),
      field_type: Some(ObjectType),
      properties: Some([#("city", empty_property())]),
    )
  let prop =
    SchemaProperty(
      ..empty_property(),
      any_of: Some([object_member, int_member()]),
    )

  let result = union_resolver.materialize_branch(prop, 0)

  result.properties |> should.equal(object_member.properties)
}

pub fn materialize_branch_strips_member_any_of_test() {
  // member_a itself carries a (bogus) any_of — the materialized result must
  // carry the outer node's member list, not the chosen member's own.
  let member_a = SchemaProperty(..int_member(), any_of: Some([str_member()]))
  let prop =
    SchemaProperty(..empty_property(), any_of: Some([member_a, str_member()]))

  let result = union_resolver.materialize_branch(prop, 0)

  result.any_of |> should.equal(prop.any_of)
}

pub fn materialize_branch_out_of_range_falls_back_to_first_test() {
  let result = union_resolver.materialize_branch(int_str_union(), 5)
  result.field_type |> should.equal(Some(IntegerType))
}

// --- resolve_form_schema ---

pub fn resolve_form_schema_materializes_top_level_union_test() {
  let schema = test_schema([#("value", int_str_union())])
  let values = ObjectValue([#("value", StringValue("hi"))])

  let resolved = union_resolver.resolve_form_schema(schema, values, [])

  let assert Some(value_prop) = properties.get(resolved.properties, "value")
  value_prop.field_type |> should.equal(Some(StringType))
  // The chooser needs the member list — materialization must keep it.
  value_prop.any_of |> should.equal(Some([int_member(), str_member()]))
}

pub fn resolve_form_schema_does_not_descend_array_items_test() {
  let array_prop =
    SchemaProperty(
      ..empty_property(),
      field_type: Some(ArrayType),
      items: Some(int_str_union()),
    )
  let schema = test_schema([#("list", array_prop)])
  let values = ObjectValue([#("list", ArrayValue([StringValue("hi")]))])

  let resolved = union_resolver.resolve_form_schema(schema, values, [])

  let assert Some(list_prop) = properties.get(resolved.properties, "list")
  // items must stay exactly as authored — untouched by the top-level walk.
  list_prop.items |> should.equal(Some(int_str_union()))
}

// --- resolve_effective_property ---

pub fn resolve_effective_property_unions_then_conditionals_test() {
  let value_field =
    SchemaProperty(
      ..empty_property(),
      any_of: Some([int_member(), str_member()]),
    )
  let if_schema =
    SchemaProperty(
      ..empty_property(),
      properties: Some([
        #(
          "kind",
          SchemaProperty(
            ..empty_property(),
            enum_values: Some([StringValue("special")]),
          ),
        ),
      ]),
    )
  let then_schema =
    SchemaProperty(
      ..empty_property(),
      properties: Some([#("bonus", empty_property())]),
    )
  let rule =
    ConditionalRule(
      if_schema: if_schema,
      then_schema: Some(then_schema),
      else_schema: None,
    )
  let row_prop =
    SchemaProperty(
      ..empty_property(),
      field_type: Some(ObjectType),
      properties: Some([
        #(
          "kind",
          SchemaProperty(..empty_property(), field_type: Some(StringType)),
        ),
        #("value", value_field),
      ]),
      conditionals: [rule],
    )
  let row_value =
    ObjectValue([
      #("kind", StringValue("special")),
      #("value", StringValue("hello")),
    ])
  let row_path = [path.PropertySegment("items"), path.ArraySegment(0)]

  let resolved =
    union_resolver.resolve_effective_property(row_prop, row_value, row_path, [])

  // Union resolved first: "value" materializes to the string branch.
  let assert Some(props) = resolved.properties
  let assert Some(value_prop) = properties.get(props, "value")
  value_prop.field_type |> should.equal(Some(StringType))

  // Conditionals still fire afterwards, against the same row value.
  properties.has_key(props, "bonus") |> should.be_true()
}

// --- branch_label ---

pub fn branch_label_prefers_title_test() {
  let member = SchemaProperty(..empty_property(), title: Some("Address"))
  union_resolver.branch_label(member, 0) |> should.equal("Address")
}

pub fn branch_label_falls_back_to_type_name_test() {
  union_resolver.branch_label(int_member(), 0) |> should.equal("Integer")
}

pub fn branch_label_falls_back_to_option_n_test() {
  union_resolver.branch_label(empty_property(), 2)
  |> should.equal("Option 3")
}
