import formosh/schema/parser
import formosh/schema/types
import gleam/dict
import gleam/list
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
      should.equal(schema.title, Some("Simple String Field"))
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
      should.equal(schema.title, Some("User Registration"))
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
      should.equal(schema.title, Some("Number List"))
      should.equal(schema.field_type, types.ArrayType)
    }
    Error(_) -> panic as "Parser should succeed"
  }
}

pub fn schema_without_title_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"name\": {
        \"type\": \"string\"
      }
    }
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  case result {
    Ok(schema) -> {
      should.equal(schema.title, None)
      should.equal(schema.field_type, types.ObjectType)

      let property_count = dict.size(schema.properties)
      should.equal(property_count, 1)
    }
    Error(_) -> panic as "Parser should succeed for schema without title"
  }
}

pub fn one_of_with_const_title_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"best_series\": {
        \"type\": \"string\",
        \"oneOf\": [
          {\"const\": \"1.2.3.4.5\", \"title\": \"S1: T1 Axial (120 images)\"},
          {\"const\": \"1.2.3.4.6\", \"title\": \"S2: T2 Coronal (80 images)\"}
        ]
      }
    }
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  let assert Ok(schema) = result
  let assert Ok(prop) = dict.get(schema.properties, "best_series")

  // field_type should be string
  should.equal(prop.field_type, Some(types.StringType))

  // one_of should contain 2 sub-schemas
  case prop.one_of {
    Some(schemas) -> {
      should.equal(list.length(schemas), 2)

      // First sub-schema
      let assert [first, second] = schemas
      should.equal(first.enum_values, Some([types.StringValue("1.2.3.4.5")]))
      should.equal(first.title, Some("S1: T1 Axial (120 images)"))

      // Second sub-schema
      should.equal(second.enum_values, Some([types.StringValue("1.2.3.4.6")]))
      should.equal(second.title, Some("S2: T2 Coronal (80 images)"))
    }
    None -> panic as "Expected one_of to be Some"
  }
}

pub fn one_of_without_title_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"value\": {
        \"type\": \"string\",
        \"oneOf\": [
          {\"const\": \"a\"},
          {\"const\": \"b\", \"title\": \"Option B\"}
        ]
      }
    }
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  let assert Ok(schema) = result
  let assert Ok(prop) = dict.get(schema.properties, "value")

  case prop.one_of {
    Some(schemas) -> {
      should.equal(list.length(schemas), 2)

      let assert [first, second] = schemas
      // First has no title
      should.equal(first.title, None)
      should.equal(first.enum_values, Some([types.StringValue("a")]))

      // Second has a title
      should.equal(second.title, Some("Option B"))
      should.equal(second.enum_values, Some([types.StringValue("b")]))
    }
    None -> panic as "Expected one_of to be Some"
  }
}

pub fn invalid_json_test() {
  let json = "{ invalid json"

  let result = parser.parse_schema(json)
  should.be_error(result)
}

pub fn image_upload_widget_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"photos\": {
        \"type\": \"array\",
        \"title\": \"Photos\",
        \"items\": {\"type\": \"string\", \"format\": \"uri\"},
        \"x-widget\": \"image-upload\",
        \"x-accept\": \"image/*\",
        \"x-max-file-size\": 10485760
      }
    }
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  let assert Ok(schema) = result
  let assert Ok(prop) = dict.get(schema.properties, "photos")

  should.equal(prop.field_type, Some(types.ArrayType))
  should.equal(prop.widget, Some("image-upload"))
  should.equal(prop.title, Some("Photos"))

  case prop.upload_config {
    Some(config) -> {
      should.equal(config.accept, "image/*")
      should.equal(config.max_file_size, Some(10_485_760))
    }
    None -> panic as "Expected upload_config to be Some"
  }

  // Items should be string with uri format
  case prop.items {
    Some(items_prop) -> {
      should.equal(items_prop.field_type, Some(types.StringType))
    }
    None -> panic as "Expected items to be Some"
  }
}

pub fn image_upload_defaults_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"photos\": {
        \"type\": \"array\",
        \"x-widget\": \"image-upload\"
      }
    }
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  let assert Ok(schema) = result
  let assert Ok(prop) = dict.get(schema.properties, "photos")

  should.equal(prop.widget, Some("image-upload"))

  // upload_config should have default accept and no max_file_size
  case prop.upload_config {
    Some(config) -> {
      should.equal(config.accept, "image/*")
      should.equal(config.max_file_size, None)
    }
    None -> panic as "Expected upload_config to be Some"
  }
}

pub fn no_widget_property_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"name\": {\"type\": \"string\"}
    }
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  let assert Ok(schema) = result
  let assert Ok(prop) = dict.get(schema.properties, "name")

  should.equal(prop.widget, None)
  should.equal(prop.upload_config, None)
}

pub fn image_upload_custom_accept_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"documents\": {
        \"type\": \"array\",
        \"x-widget\": \"image-upload\",
        \"x-accept\": \"application/pdf\",
        \"x-max-file-size\": 5242880
      }
    }
  }"

  let result = parser.parse_schema(json)
  should.be_ok(result)

  let assert Ok(schema) = result
  let assert Ok(prop) = dict.get(schema.properties, "documents")

  should.equal(prop.widget, Some("image-upload"))
  case prop.upload_config {
    Some(config) -> {
      should.equal(config.accept, "application/pdf")
      should.equal(config.max_file_size, Some(5_242_880))
    }
    None -> panic as "Expected upload_config to be Some"
  }
}
