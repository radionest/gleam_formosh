import formosh/schema/parser
import formosh/schema/serializer
import formosh/schema/types.{
  ArrayType, BooleanType, DateFormat, EmailFormat, IntegerType, IntegerValue,
  JsonSchema, NumberConstraints, NumberType, ObjectType, SchemaProperty,
  StringConstraints, StringType, StringValue, UploadConfig, empty_property,
}
import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

pub fn serialize_basic_string_schema_test() {
  let schema =
    JsonSchema(
      title: Some("Basic String"),
      description: Some("A simple string field"),
      field_type: ObjectType,
      properties: [
        #(
          "name",
          SchemaProperty(
            ..empty_property(),
            field_type: Some(StringType),
            title: Some("Name"),
            description: Some("Your name"),
          ),
        ),
      ],
      required: ["name"],
      defs: None,
      conditionals: [],
      string_constraints: None,
      number_constraints: None,
    )

  let result = serializer.schema_to_json(schema)
  let json_string = json.to_string(result)

  // Verify the JSON contains expected fields
  json_string
  |> string.contains(
    "\"$schema\":\"https://json-schema.org/draft/2020-12/schema\"",
  )
  |> should.be_true()

  json_string
  |> string.contains("\"title\":\"Basic String\"")
  |> should.be_true()

  json_string
  |> string.contains("\"type\":\"object\"")
  |> should.be_true()

  json_string
  |> string.contains("\"required\":[\"name\"]")
  |> should.be_true()

  json_string
  |> string.contains("\"description\":\"A simple string field\"")
  |> should.be_true()
}

pub fn serialize_string_with_constraints_test() {
  let schema =
    JsonSchema(
      title: Some("Constrained String"),
      description: None,
      field_type: ObjectType,
      properties: [
        #(
          "email",
          SchemaProperty(
            ..empty_property(),
            field_type: Some(StringType),
            title: Some("Email"),
            string_constraints: Some(StringConstraints(
              min_length: Some(5),
              max_length: Some(100),
              pattern: Some("^[\\w._%+-]+@[\\w.-]+\\.[A-Za-z]{2,}$"),
              format: Some(EmailFormat),
            )),
          ),
        ),
      ],
      required: [],
      defs: None,
      conditionals: [],
      string_constraints: None,
      number_constraints: None,
    )

  let result = serializer.schema_to_json(schema)
  let json_string = json.to_string(result)

  json_string
  |> string.contains("\"minLength\":5")
  |> should.be_true()

  json_string
  |> string.contains("\"maxLength\":100")
  |> should.be_true()

  json_string
  |> string.contains("\"format\":\"email\"")
  |> should.be_true()

  json_string
  |> string.contains("\"pattern\":")
  |> should.be_true()
}

pub fn serialize_number_with_constraints_test() {
  let schema =
    JsonSchema(
      title: Some("Number Field"),
      description: None,
      field_type: ObjectType,
      properties: [
        #(
          "age",
          SchemaProperty(
            ..empty_property(),
            field_type: Some(IntegerType),
            title: Some("Age"),
            default: Some(IntegerValue(18)),
            number_constraints: Some(NumberConstraints(
              minimum: Some(0.0),
              maximum: Some(120.0),
              exclusive_minimum: None,
              exclusive_maximum: None,
              multiple_of: Some(1.0),
            )),
          ),
        ),
      ],
      required: [],
      defs: None,
      conditionals: [],
      string_constraints: None,
      number_constraints: None,
    )

  let result = serializer.schema_to_json(schema)
  let json_string = json.to_string(result)

  json_string
  |> string.contains("\"type\":\"integer\"")
  |> should.be_true()

  json_string
  |> string.contains("\"minimum\":0")
  |> should.be_true()

  json_string
  |> string.contains("\"maximum\":120")
  |> should.be_true()

  json_string
  |> string.contains("\"default\":18")
  |> should.be_true()

  json_string
  |> string.contains("\"multipleOf\":1")
  |> should.be_true()
}

pub fn serialize_enum_field_test() {
  let schema =
    JsonSchema(
      title: Some("Enum Field"),
      description: None,
      field_type: ObjectType,
      properties: [
        #(
          "color",
          SchemaProperty(
            ..empty_property(),
            field_type: Some(StringType),
            title: Some("Favorite Color"),
            default: Some(StringValue("blue")),
            enum_values: Some([
              StringValue("red"),
              StringValue("green"),
              StringValue("blue"),
            ]),
          ),
        ),
      ],
      required: [],
      defs: None,
      conditionals: [],
      string_constraints: None,
      number_constraints: None,
    )

  let result = serializer.schema_to_json(schema)
  let json_string = json.to_string(result)

  json_string
  |> string.contains("\"enum\":[\"red\",\"green\",\"blue\"]")
  |> should.be_true()

  json_string
  |> string.contains("\"default\":\"blue\"")
  |> should.be_true()
}

pub fn serialize_array_field_test() {
  let schema =
    JsonSchema(
      title: Some("Array Field"),
      description: None,
      field_type: ObjectType,
      properties: [
        #(
          "tags",
          SchemaProperty(
            ..empty_property(),
            field_type: Some(ArrayType),
            title: Some("Tags"),
            description: Some("List of tags"),
            items: Some(
              SchemaProperty(
                ..empty_property(),
                field_type: Some(StringType),
                string_constraints: Some(StringConstraints(
                  min_length: Some(1),
                  max_length: Some(20),
                  pattern: None,
                  format: None,
                )),
              ),
            ),
          ),
        ),
      ],
      required: [],
      defs: None,
      conditionals: [],
      string_constraints: None,
      number_constraints: None,
    )

  let result = serializer.schema_to_json(schema)
  let json_string = json.to_string(result)

  json_string
  |> string.contains("\"type\":\"array\"")
  |> should.be_true()

  json_string
  |> string.contains("\"items\":{")
  |> should.be_true()

  json_string
  |> string.contains("\"minLength\":1")
  |> should.be_true()

  json_string
  |> string.contains("\"maxLength\":20")
  |> should.be_true()
}

pub fn serialize_nested_object_test() {
  let schema =
    JsonSchema(
      title: Some("Nested Object"),
      description: None,
      field_type: ObjectType,
      properties: [
        #(
          "address",
          SchemaProperty(
            ..empty_property(),
            field_type: Some(ObjectType),
            title: Some("Address"),
            properties: Some([
              #(
                "street",
                SchemaProperty(
                  ..empty_property(),
                  field_type: Some(StringType),
                  title: Some("Street"),
                ),
              ),
              #(
                "city",
                SchemaProperty(
                  ..empty_property(),
                  field_type: Some(StringType),
                  title: Some("City"),
                ),
              ),
            ]),
            required: ["street", "city"],
          ),
        ),
      ],
      required: ["address"],
      defs: None,
      conditionals: [],
      string_constraints: None,
      number_constraints: None,
    )

  let result = serializer.schema_to_json(schema)
  let json_string = json.to_string(result)

  json_string
  |> string.contains("\"required\":[\"address\"]")
  |> should.be_true()

  json_string
  |> string.contains("\"street\":{\"type\"")
  |> should.be_true()

  json_string
  |> string.contains("\"city\":{\"type\":\"string\"")
  |> should.be_true()

  // Nested required
  json_string
  |> string.contains("\"required\":[\"street\",\"city\"]")
  |> should.be_true()
}

pub fn serialize_ref_field_test() {
  let schema =
    JsonSchema(
      title: Some("Schema with $ref"),
      description: None,
      field_type: ObjectType,
      properties: [
        #(
          "shipping",
          SchemaProperty(
            ..empty_property(),
            title: Some("Shipping Address"),
            ref: Some("#/$defs/address"),
          ),
        ),
      ],
      required: [],
      defs: Some(
        dict.from_list([
          #(
            "address",
            SchemaProperty(
              ..empty_property(),
              field_type: Some(ObjectType),
              title: Some("Address"),
              properties: Some([
                #(
                  "street",
                  SchemaProperty(
                    ..empty_property(),
                    field_type: Some(StringType),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
      conditionals: [],
      string_constraints: None,
      number_constraints: None,
    )

  let result = serializer.schema_to_json(schema)
  let json_string = json.to_string(result)

  json_string
  |> string.contains("\"$ref\":\"#/$defs/address\"")
  |> should.be_true()

  json_string
  |> string.contains("\"$defs\":{")
  |> should.be_true()

  json_string
  |> string.contains("\"address\":{\"type\":\"object\"")
  |> should.be_true()
}

pub fn serialize_conditional_schema_test() {
  let schema =
    JsonSchema(
      title: Some("Conditional Schema"),
      description: None,
      field_type: ObjectType,
      properties: [
        #(
          "hasAccount",
          SchemaProperty(
            ..empty_property(),
            field_type: Some(BooleanType),
            title: Some("Has Account"),
          ),
        ),
      ],
      required: [],
      defs: None,
      conditionals: [
        types.ConditionalRule(
          if_schema: SchemaProperty(
            ..empty_property(),
            properties: Some([
              #(
                "hasAccount",
                SchemaProperty(
                  ..empty_property(),
                  enum_values: Some([types.BooleanValue(True)]),
                ),
              ),
            ]),
          ),
          then_schema: Some(
            SchemaProperty(
              ..empty_property(),
              properties: Some([
                #(
                  "accountId",
                  SchemaProperty(
                    ..empty_property(),
                    field_type: Some(StringType),
                    title: Some("Account ID"),
                  ),
                ),
              ]),
              required: ["accountId"],
            ),
          ),
          else_schema: None,
        ),
      ],
      string_constraints: None,
      number_constraints: None,
    )

  let result = serializer.schema_to_json(schema)
  let json_string = json.to_string(result)

  json_string
  |> string.contains("\"if\":{")
  |> should.be_true()

  json_string
  |> string.contains("\"then\":{")
  |> should.be_true()

  json_string
  |> string.contains("\"accountId\":{\"type\":\"string\"")
  |> should.be_true()
}

pub fn serialize_boolean_field_test() {
  let schema =
    JsonSchema(
      title: Some("Boolean Field"),
      description: None,
      field_type: ObjectType,
      properties: [
        #(
          "active",
          SchemaProperty(
            ..empty_property(),
            field_type: Some(BooleanType),
            title: Some("Is Active"),
            description: Some("Whether the user is active"),
            default: Some(types.BooleanValue(True)),
          ),
        ),
      ],
      required: [],
      defs: None,
      conditionals: [],
      string_constraints: None,
      number_constraints: None,
    )

  let result = serializer.schema_to_json(schema)
  let json_string = json.to_string(result)

  json_string
  |> string.contains("\"type\":\"boolean\"")
  |> should.be_true()

  json_string
  |> string.contains("\"default\":true")
  |> should.be_true()

  json_string
  |> string.contains("\"title\":\"Is Active\"")
  |> should.be_true()
}

pub fn serialize_date_format_test() {
  let schema =
    JsonSchema(
      title: Some("Date Field"),
      description: None,
      field_type: ObjectType,
      properties: [
        #(
          "birthdate",
          SchemaProperty(
            ..empty_property(),
            field_type: Some(StringType),
            title: Some("Birth Date"),
            string_constraints: Some(StringConstraints(
              min_length: None,
              max_length: None,
              pattern: None,
              format: Some(DateFormat),
            )),
          ),
        ),
      ],
      required: [],
      defs: None,
      conditionals: [],
      string_constraints: None,
      number_constraints: None,
    )

  let result = serializer.schema_to_json(schema)
  let json_string = json.to_string(result)

  json_string
  |> string.contains("\"format\":\"date\"")
  |> should.be_true()

  json_string
  |> string.contains("\"type\":\"string\"")
  |> should.be_true()
}

pub fn serialize_exclusive_constraints_test() {
  let schema =
    JsonSchema(
      title: Some("Exclusive Constraints"),
      description: None,
      field_type: ObjectType,
      properties: [
        #(
          "percentage",
          SchemaProperty(
            ..empty_property(),
            field_type: Some(NumberType),
            title: Some("Percentage"),
            number_constraints: Some(NumberConstraints(
              minimum: None,
              maximum: None,
              exclusive_minimum: Some(0.0),
              exclusive_maximum: Some(100.0),
              multiple_of: None,
            )),
          ),
        ),
      ],
      required: [],
      defs: None,
      conditionals: [],
      string_constraints: None,
      number_constraints: None,
    )

  let result = serializer.schema_to_json(schema)
  let json_string = json.to_string(result)

  json_string
  |> string.contains("\"exclusiveMinimum\":0")
  |> should.be_true()

  json_string
  |> string.contains("\"exclusiveMaximum\":100")
  |> should.be_true()
}

pub fn serialize_multiple_conditionals_test() {
  let schema =
    JsonSchema(
      title: Some("Multiple Conditionals"),
      description: None,
      field_type: ObjectType,
      properties: [
        #(
          "type",
          SchemaProperty(
            ..empty_property(),
            field_type: Some(StringType),
            title: Some("Type"),
            enum_values: Some([
              StringValue("personal"),
              StringValue("business"),
            ]),
          ),
        ),
      ],
      required: [],
      defs: None,
      conditionals: [
        types.ConditionalRule(
          if_schema: SchemaProperty(
            ..empty_property(),
            properties: Some([
              #(
                "type",
                SchemaProperty(
                  ..empty_property(),
                  enum_values: Some([StringValue("personal")]),
                ),
              ),
            ]),
          ),
          then_schema: Some(
            SchemaProperty(
              ..empty_property(),
              properties: Some([
                #(
                  "firstName",
                  SchemaProperty(
                    ..empty_property(),
                    field_type: Some(StringType),
                    title: Some("First Name"),
                  ),
                ),
              ]),
            ),
          ),
          else_schema: None,
        ),
        types.ConditionalRule(
          if_schema: SchemaProperty(
            ..empty_property(),
            properties: Some([
              #(
                "type",
                SchemaProperty(
                  ..empty_property(),
                  enum_values: Some([StringValue("business")]),
                ),
              ),
            ]),
          ),
          then_schema: Some(
            SchemaProperty(
              ..empty_property(),
              properties: Some([
                #(
                  "companyName",
                  SchemaProperty(
                    ..empty_property(),
                    field_type: Some(StringType),
                    title: Some("Company Name"),
                  ),
                ),
              ]),
            ),
          ),
          else_schema: None,
        ),
      ],
      string_constraints: None,
      number_constraints: None,
    )

  let result = serializer.schema_to_json(schema)
  let json_string = json.to_string(result)

  // Multiple conditionals should be wrapped in allOf
  json_string
  |> string.contains("\"allOf\":[")
  |> should.be_true()
}

pub fn serialize_one_of_test() {
  let schema =
    JsonSchema(
      title: Some("OneOf Field"),
      description: None,
      field_type: ObjectType,
      properties: [
        #(
          "best_series",
          SchemaProperty(
            ..empty_property(),
            field_type: Some(StringType),
            title: Some("Best Series"),
            one_of: Some([
              SchemaProperty(
                ..empty_property(),
                title: Some("S1: T1 Axial (120 images)"),
                enum_values: Some([StringValue("1.2.3.4.5")]),
              ),
              SchemaProperty(
                ..empty_property(),
                title: Some("S2: T2 Coronal (80 images)"),
                enum_values: Some([StringValue("1.2.3.4.6")]),
              ),
            ]),
          ),
        ),
      ],
      required: [],
      defs: None,
      conditionals: [],
      string_constraints: None,
      number_constraints: None,
    )

  let result = serializer.schema_to_json(schema)
  let json_string = json.to_string(result)

  // Should contain oneOf array
  json_string
  |> string.contains("\"oneOf\":[")
  |> should.be_true()

  // Should contain the const values
  json_string
  |> string.contains("\"enum\":[\"1.2.3.4.5\"]")
  |> should.be_true()

  json_string
  |> string.contains("\"enum\":[\"1.2.3.4.6\"]")
  |> should.be_true()

  // Should contain the titles
  json_string
  |> string.contains("\"title\":\"S1: T1 Axial (120 images)\"")
  |> should.be_true()

  json_string
  |> string.contains("\"title\":\"S2: T2 Coronal (80 images)\"")
  |> should.be_true()
}

pub fn image_upload_serialization_test() {
  let schema =
    JsonSchema(
      title: Some("Image Form"),
      description: None,
      field_type: ObjectType,
      properties: [
        #(
          "photos",
          SchemaProperty(
            ..empty_property(),
            field_type: Some(ArrayType),
            title: Some("Photos"),
            items: Some(
              SchemaProperty(..empty_property(), field_type: Some(StringType)),
            ),
            render_hints: types.RenderHints(
              widget: Some(types.ImageUploadWidget),
              upload_config: Some(UploadConfig(
                accept: "image/*",
                max_file_size: Some(10_485_760),
              )),
            ),
          ),
        ),
      ],
      required: [],
      defs: None,
      conditionals: [],
      string_constraints: None,
      number_constraints: None,
    )

  let result = serializer.schema_to_json(schema)
  let json_string = json.to_string(result)

  json_string
  |> string.contains("\"x-widget\":\"image-upload\"")
  |> should.be_true()

  json_string
  |> string.contains("\"x-accept\":\"image/*\"")
  |> should.be_true()

  json_string
  |> string.contains("\"x-max-file-size\":10485760")
  |> should.be_true()
}

pub fn image_upload_roundtrip_test() {
  let json =
    "{
    \"type\": \"object\",
    \"properties\": {
      \"photos\": {
        \"type\": \"array\",
        \"title\": \"Photos\",
        \"items\": {\"type\": \"string\"},
        \"x-widget\": \"image-upload\",
        \"x-accept\": \"image/jpeg\",
        \"x-max-file-size\": 5242880
      }
    }
  }"

  // Parse
  let assert Ok(schema) = parser.parse_schema(json)
  let assert Ok(prop) = list.key_find(schema.properties, "photos")

  should.equal(prop.render_hints.widget, Some(types.ImageUploadWidget))
  case prop.render_hints.upload_config {
    Some(config) -> {
      should.equal(config.accept, "image/jpeg")
      should.equal(config.max_file_size, Some(5_242_880))
    }
    None -> panic as "Expected upload_config"
  }

  // Serialize back
  let serialized = serializer.schema_to_json(schema)
  let serialized_string = json.to_string(serialized)

  serialized_string
  |> string.contains("\"x-widget\":\"image-upload\"")
  |> should.be_true()

  serialized_string
  |> string.contains("\"x-accept\":\"image/jpeg\"")
  |> should.be_true()

  serialized_string
  |> string.contains("\"x-max-file-size\":5242880")
  |> should.be_true()

  // Re-parse serialized output
  let assert Ok(reparsed) = parser.parse_schema(serialized_string)
  let assert Ok(reparsed_prop) = list.key_find(reparsed.properties, "photos")

  should.equal(reparsed_prop.render_hints.widget, Some(types.ImageUploadWidget))
  case reparsed_prop.render_hints.upload_config {
    Some(config) -> {
      should.equal(config.accept, "image/jpeg")
      should.equal(config.max_file_size, Some(5_242_880))
    }
    None -> panic as "Expected upload_config after roundtrip"
  }
}

pub fn no_widget_no_x_fields_serialized_test() {
  let schema =
    JsonSchema(
      title: None,
      description: None,
      field_type: ObjectType,
      properties: [
        #(
          "name",
          SchemaProperty(..empty_property(), field_type: Some(StringType)),
        ),
      ],
      required: [],
      defs: None,
      conditionals: [],
      string_constraints: None,
      number_constraints: None,
    )

  let result = serializer.schema_to_json(schema)
  let json_string = json.to_string(result)

  // Should not contain any x- fields
  json_string
  |> string.contains("x-widget")
  |> should.be_false()

  json_string
  |> string.contains("x-accept")
  |> should.be_false()

  json_string
  |> string.contains("x-max-file-size")
  |> should.be_false()
}
