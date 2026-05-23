import formosh/form/model.{type FormModel, FormModel}
import formosh/form/path.{ArraySegment, PropertySegment}
import formosh/form/update
import formosh/schema/types.{
  type JsonSchema, IntegerType, IntegerValue, JsonSchema, ObjectType,
  ObjectValue, SchemaProperty, empty_property,
}
import formosh/validation/cross_validator
import formosh/validation/error.{type ValidationError, ValidationError}
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

// Schema with two integer fields: `total_limit` and `categories[].limit`.
// Cross-field rule: sum of category limits must not exceed total_limit.
fn limits_schema() -> JsonSchema {
  let integer_prop =
    SchemaProperty(..empty_property(), field_type: Some(IntegerType))
  let category_item =
    SchemaProperty(
      ..empty_property(),
      field_type: Some(ObjectType),
      properties: Some([#("limit", integer_prop)]),
      required: ["limit"],
    )
  let categories_prop =
    SchemaProperty(
      ..empty_property(),
      field_type: Some(types.ArrayType),
      items: Some(category_item),
    )
  JsonSchema(
    title: None,
    description: None,
    field_type: ObjectType,
    properties: [
      #("total_limit", integer_prop),
      #("categories", categories_prop),
    ],
    required: ["total_limit"],
    defs: None,
    conditionals: [],
    string_constraints: None,
    number_constraints: None,
  )
}

fn sum_categories(m: FormModel) -> Int {
  case path.get_at_path(m.values, [PropertySegment("categories")]) {
    Some(types.ArrayValue(items)) ->
      list.fold(items, 0, fn(acc, item) {
        case path.get_at_path(item, [PropertySegment("limit")]) {
          Some(IntegerValue(n)) -> acc + n
          _ -> acc
        }
      })
    _ -> 0
  }
}

fn total_limit(m: FormModel) -> Int {
  case path.get_at_path(m.values, [PropertySegment("total_limit")]) {
    Some(IntegerValue(n)) -> n
    _ -> 0
  }
}

fn check_sum(m: FormModel) -> List(ValidationError) {
  case sum_categories(m) > total_limit(m) {
    True -> [
      ValidationError(
        field: [PropertySegment("total_limit")],
        message: "Sum of categories exceeds total",
        rule: "custom",
      ),
    ]
    False -> []
  }
}

pub fn cross_validator_adds_error_when_sum_exceeds_test() {
  let schema = limits_schema()
  let m =
    FormModel(
      ..model.init(schema),
      values: ObjectValue([
        #("total_limit", IntegerValue(100)),
        #(
          "categories",
          types.ArrayValue([
            ObjectValue([#("limit", IntegerValue(70))]),
            ObjectValue([#("limit", IntegerValue(50))]),
          ]),
        ),
      ]),
      validator: Some(cross_validator.pure(check_sum)),
    )

  let validated = update.validate_all_fields(m)

  validated
  |> model.has_errors_at_path([PropertySegment("total_limit")])
  |> should.be_true()
  validated.is_valid
  |> should.be_false()
}

pub fn cross_validator_no_errors_when_sum_within_limit_test() {
  let schema = limits_schema()
  let m =
    FormModel(
      ..model.init(schema),
      values: ObjectValue([
        #("total_limit", IntegerValue(100)),
        #(
          "categories",
          types.ArrayValue([
            ObjectValue([#("limit", IntegerValue(40))]),
            ObjectValue([#("limit", IntegerValue(30))]),
          ]),
        ),
      ]),
      validator: Some(cross_validator.pure(check_sum)),
    )

  let validated = update.validate_all_fields(m)

  validated
  |> model.get_errors_at_path([PropertySegment("total_limit")])
  |> should.equal([])
}

pub fn cross_validator_absence_does_not_alter_behaviour_test() {
  let schema = limits_schema()
  let m =
    FormModel(
      ..model.init(schema),
      values: ObjectValue([
        #("total_limit", IntegerValue(100)),
        #(
          "categories",
          types.ArrayValue([ObjectValue([#("limit", IntegerValue(200))])]),
        ),
      ]),
      validator: None,
    )

  let validated = update.validate_all_fields(m)

  // Without a custom validator, schema-only validation finds no error on
  // total_limit (schema has no arithmetic constraint between fields).
  validated
  |> model.get_errors_at_path([PropertySegment("total_limit")])
  |> should.equal([])
}

pub fn cross_validator_can_target_nested_array_item_test() {
  let schema = limits_schema()
  let flag_overspent = fn(m: FormModel) {
    case path.get_at_path(m.values, [PropertySegment("categories")]) {
      Some(types.ArrayValue(items)) ->
        list.index_map(items, fn(item, i) { #(i, item) })
        |> list.filter_map(fn(pair) {
          let #(i, item) = pair
          case path.get_at_path(item, [PropertySegment("limit")]) {
            Some(IntegerValue(n)) if n > 100 ->
              Ok(ValidationError(
                field: [
                  PropertySegment("categories"),
                  ArraySegment(i),
                  PropertySegment("limit"),
                ],
                message: "Per-category limit too high",
                rule: "custom",
              ))
            _ -> Error(Nil)
          }
        })
      _ -> []
    }
  }

  let m =
    FormModel(
      ..model.init(schema),
      values: ObjectValue([
        #("total_limit", IntegerValue(1000)),
        #(
          "categories",
          types.ArrayValue([
            ObjectValue([#("limit", IntegerValue(50))]),
            ObjectValue([#("limit", IntegerValue(150))]),
          ]),
        ),
      ]),
      validator: Some(cross_validator.pure(flag_overspent)),
    )

  let validated = update.validate_all_fields(m)

  validated
  |> model.has_errors_at_path([
    PropertySegment("categories"),
    ArraySegment(1),
    PropertySegment("limit"),
  ])
  |> should.be_true()
  validated
  |> model.has_errors_at_path([
    PropertySegment("categories"),
    ArraySegment(0),
    PropertySegment("limit"),
  ])
  |> should.be_false()
}
