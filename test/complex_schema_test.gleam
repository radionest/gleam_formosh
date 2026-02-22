import formosh/schema/parser
import formosh/schema/types
import gleam/dict
import gleam/option.{None, Some}
import gleeunit/should

pub fn complex_lesion_schema_test() {
  // Test with the actual example schema from formosh.gleam
  let json =
    "{
    \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",
    \"$id\": \"https://example.com/lesion-measurement.schema.json\",
    \"title\": \"Измерение образований\",
    \"description\": \"Укажите наибольший размер каждого обнаруженного образования в миллиметрах\",
    \"type\": \"object\",
    \"properties\": {
      \"diagnosis\": {
        \"description\": \"Диагноз\",
        \"type\": \"string\",
        \"maxLength\": 200
      },
      \"lesions\": {
        \"description\": \"Список измерений образований\",
        \"type\": \"array\",
        \"items\": {
          \"type\": \"object\",
          \"properties\": {
            \"side\": {
              \"description\": \"Сторона (L - левая, R - правая)\",
              \"type\": \"string\",
              \"enum\": [\"L\", \"R\"]
            },
            \"max_size_mm\": {
              \"description\": \"Наибольший размер в миллиметрах\",
              \"type\": \"number\",
              \"minimum\": 0,
              \"maximum\": 200
            }
          },
          \"required\": [\"side\", \"max_size_mm\"]
        },
        \"minItems\": 1
      }
    },
    \"required\": [\"lesions\"]
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  case result {
    Ok(schema) -> {
      // Check main schema properties
      should.equal(schema.title, Some("Измерение образований"))
      should.equal(schema.field_type, types.ObjectType)
      should.equal(schema.required, ["lesions"])

      // Check that we have the expected properties
      let property_count = dict.size(schema.properties)
      should.equal(property_count, 2)

      // Check diagnosis property constraints
      case dict.get(schema.properties, "diagnosis") {
        Ok(diagnosis_prop) -> {
          should.equal(diagnosis_prop.field_type, Some(types.StringType))
          should.equal(diagnosis_prop.description, Some("Диагноз"))

          case diagnosis_prop.string_constraints {
            Some(constraints) -> {
              should.equal(constraints.max_length, Some(200))
            }
            None -> panic as "Expected string constraints for diagnosis"
          }
        }
        Error(_) -> panic as "Expected diagnosis property"
      }

      // Check lesions property
      case dict.get(schema.properties, "lesions") {
        Ok(lesions_prop) -> {
          should.equal(lesions_prop.field_type, Some(types.ArrayType))
          should.equal(
            lesions_prop.description,
            Some("Список измерений образований"),
          )

          // Check that items are defined
          case lesions_prop.items {
            Some(item_schema) -> {
              should.equal(item_schema.field_type, Some(types.ObjectType))
              should.equal(item_schema.required, ["side", "max_size_mm"])
            }
            None -> panic as "Expected items schema for lesions array"
          }
        }
        Error(_) -> panic as "Expected lesions property"
      }
    }
    Error(_) -> panic as "Parser should succeed"
  }
}

pub fn enum_values_test() {
  let json =
    "{
    \"title\": \"Color Choice\",
    \"type\": \"string\",
    \"enum\": [\"red\", \"green\", \"blue\"]
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  case result {
    Ok(schema) -> {
      should.equal(schema.title, Some("Color Choice"))
      should.equal(schema.field_type, types.StringType)
    }
    Error(_) -> panic as "Parser should succeed"
  }
}
