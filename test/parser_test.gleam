import formosh/schema/parser
import formosh/schema/types
import gleam/dict
import gleam/option.{None, Some}
import gleeunit/should

pub fn simple_string_schema_test() {
  let json =
    "{
    \"title\": \"Simple String Field\",
    \"type\": \"string\",
    \"maxLength\": 100
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  case result {
    Ok(schema) -> {
      should.equal(schema.title, "Simple String Field")
      should.equal(schema.field_type, types.StringType)

      case schema.string_constraints {
        Some(constraints) -> {
          should.equal(constraints.max_length, Some(100))
        }
        None -> panic as "Expected string constraints"
      }
    }
    Error(_) -> panic as "Parser should succeed"
  }
}

pub fn object_with_properties_test() {
  let json =
    "{
    \"title\": \"User Registration\",
    \"type\": \"object\",
    \"properties\": {
      \"name\": {
        \"type\": \"string\",
        \"minLength\": 2
      },
      \"age\": {
        \"type\": \"integer\",
        \"minimum\": 0,
        \"maximum\": 120
      }
    },
    \"required\": [\"name\"]
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  case result {
    Ok(schema) -> {
      should.equal(schema.title, "User Registration")
      should.equal(schema.field_type, types.ObjectType)
      should.equal(schema.required, ["name"])

      // Check that properties were parsed
      let property_count = dict.size(schema.properties)
      should.equal(property_count, 2)
    }
    Error(_) -> panic as "Parser should succeed"
  }
}

pub fn array_with_items_test() {
  let json =
    "{
    \"title\": \"Number List\",
    \"type\": \"array\",
    \"items\": {
      \"type\": \"number\",
      \"minimum\": 0
    }
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  case result {
    Ok(schema) -> {
      should.equal(schema.title, "Number List")
      should.equal(schema.field_type, types.ArrayType)
    }
    Error(_) -> panic as "Parser should succeed"
  }
}

pub fn invalid_json_test() {
  let json = "{ invalid json"

  let result = parser.parse_schema(json)
  should.be_error(result)
}
