import formosh/schema/serializer
import formosh/schema/types.{
  ArrayType, BooleanType, DateFormat, EmailFormat, IntegerType, IntegerValue,
  JsonSchema, NumberConstraints, NumberType, ObjectType, SchemaProperty,
  StringConstraints, StringType, StringValue,
}
import gleam/dict
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

pub fn serialize_basic_string_schema_test() {
  let schema =
    JsonSchema(
      title: Some("Basic String"),
      description: Some("A simple string field"),
      field_type: ObjectType,
      properties: dict.from_list([
        #(
          "name",
          SchemaProperty(
            field_type: Some(StringType),
            title: Some("Name"),
            description: Some("Your name"),
            default: None,
            enum_values: None,
            ref: None,
            string_constraints: None,
            number_constraints: None,
            items: None,
            properties: None,
            required: [],
            read_only: False,
          ),
        ),
      ]),
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
      properties: dict.from_list([
        #(
          "email",
          SchemaProperty(
            field_type: Some(StringType),
            title: Some("Email"),
            description: None,
            default: None,
            enum_values: None,
            ref: None,
            string_constraints: Some(StringConstraints(
              min_length: Some(5),
              max_length: Some(100),
              pattern: Some("^[\\w._%+-]+@[\\w.-]+\\.[A-Za-z]{2,}$"),
              format: Some(EmailFormat),
            )),
            number_constraints: None,
            items: None,
            properties: None,
            required: [],
            read_only: False,
          ),
        ),
      ]),
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
      properties: dict.from_list([
        #(
          "age",
          SchemaProperty(
            field_type: Some(IntegerType),
            title: Some("Age"),
            description: None,
            default: Some(IntegerValue(18)),
            enum_values: None,
            ref: None,
            string_constraints: None,
            number_constraints: Some(NumberConstraints(
              minimum: Some(0.0),
              maximum: Some(120.0),
              exclusive_minimum: None,
              exclusive_maximum: None,
              multiple_of: Some(1.0),
            )),
            items: None,
            properties: None,
            required: [],
            read_only: False,
          ),
        ),
      ]),
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
      properties: dict.from_list([
        #(
          "color",
          SchemaProperty(
            field_type: Some(StringType),
            title: Some("Favorite Color"),
            description: None,
            default: Some(StringValue("blue")),
            enum_values: Some([
              StringValue("red"),
              StringValue("green"),
              StringValue("blue"),
            ]),
            ref: None,
            string_constraints: None,
            number_constraints: None,
            items: None,
            properties: None,
            required: [],
            read_only: False,
          ),
        ),
      ]),
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
      properties: dict.from_list([
        #(
          "tags",
          SchemaProperty(
            field_type: Some(ArrayType),
            title: Some("Tags"),
            description: Some("List of tags"),
            default: None,
            enum_values: None,
            ref: None,
            string_constraints: None,
            number_constraints: None,
            items: Some(SchemaProperty(
              field_type: Some(StringType),
              title: None,
              description: None,
              default: None,
              enum_values: None,
              ref: None,
              string_constraints: Some(StringConstraints(
                min_length: Some(1),
                max_length: Some(20),
                pattern: None,
                format: None,
              )),
              number_constraints: None,
              items: None,
              properties: None,
              required: [],
              read_only: False,
            )),
            properties: None,
            required: [],
            read_only: False,
          ),
        ),
      ]),
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
      properties: dict.from_list([
        #(
          "address",
          SchemaProperty(
            field_type: Some(ObjectType),
            title: Some("Address"),
            description: None,
            default: None,
            enum_values: None,
            ref: None,
            string_constraints: None,
            number_constraints: None,
            items: None,
            properties: Some(
              dict.from_list([
                #(
                  "street",
                  SchemaProperty(
                    field_type: Some(StringType),
                    title: Some("Street"),
                    description: None,
                    default: None,
                    enum_values: None,
                    ref: None,
                    string_constraints: None,
                    number_constraints: None,
                    items: None,
                    properties: None,
                    required: [],
                    read_only: False,
                  ),
                ),
                #(
                  "city",
                  SchemaProperty(
                    field_type: Some(StringType),
                    title: Some("City"),
                    description: None,
                    default: None,
                    enum_values: None,
                    ref: None,
                    string_constraints: None,
                    number_constraints: None,
                    items: None,
                    properties: None,
                    required: [],
                    read_only: False,
                  ),
                ),
              ]),
            ),
            required: ["street", "city"],
            read_only: False,
          ),
        ),
      ]),
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
      properties: dict.from_list([
        #(
          "shipping",
          SchemaProperty(
            field_type: None,
            title: Some("Shipping Address"),
            description: None,
            default: None,
            enum_values: None,
            ref: Some("#/$defs/address"),
            string_constraints: None,
            number_constraints: None,
            items: None,
            properties: None,
            required: [],
            read_only: False,
          ),
        ),
      ]),
      required: [],
      defs: Some(
        dict.from_list([
          #(
            "address",
            SchemaProperty(
              field_type: Some(ObjectType),
              title: Some("Address"),
              description: None,
              default: None,
              enum_values: None,
              ref: None,
              string_constraints: None,
              number_constraints: None,
              items: None,
              properties: Some(
                dict.from_list([
                  #(
                    "street",
                    SchemaProperty(
                      field_type: Some(StringType),
                      title: None,
                      description: None,
                      default: None,
                      enum_values: None,
                      ref: None,
                      string_constraints: None,
                      number_constraints: None,
                      items: None,
                      properties: None,
                      required: [],
                      read_only: False,
                    ),
                  ),
                ]),
              ),
              required: [],
              read_only: False,
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
      properties: dict.from_list([
        #(
          "hasAccount",
          SchemaProperty(
            field_type: Some(BooleanType),
            title: Some("Has Account"),
            description: None,
            default: None,
            enum_values: None,
            ref: None,
            string_constraints: None,
            number_constraints: None,
            items: None,
            properties: None,
            required: [],
            read_only: False,
          ),
        ),
      ]),
      required: [],
      defs: None,
      conditionals: [
        types.ConditionalRule(
          if_schema: SchemaProperty(
            field_type: None,
            title: None,
            description: None,
            default: None,
            enum_values: None,
            ref: None,
            string_constraints: None,
            number_constraints: None,
            items: None,
            properties: Some(
              dict.from_list([
                #(
                  "hasAccount",
                  SchemaProperty(
                    field_type: None,
                    title: None,
                    description: None,
                    default: None,
                    enum_values: Some([types.BooleanValue(True)]),
                    ref: None,
                    string_constraints: None,
                    number_constraints: None,
                    items: None,
                    properties: None,
                    required: [],
                    read_only: False,
                  ),
                ),
              ]),
            ),
            required: [],
            read_only: False,
          ),
          then_schema: Some(SchemaProperty(
            field_type: None,
            title: None,
            description: None,
            default: None,
            enum_values: None,
            ref: None,
            string_constraints: None,
            number_constraints: None,
            items: None,
            properties: Some(
              dict.from_list([
                #(
                  "accountId",
                  SchemaProperty(
                    field_type: Some(StringType),
                    title: Some("Account ID"),
                    description: None,
                    default: None,
                    enum_values: None,
                    ref: None,
                    string_constraints: None,
                    number_constraints: None,
                    items: None,
                    properties: None,
                    required: [],
                    read_only: False,
                  ),
                ),
              ]),
            ),
            required: ["accountId"],
            read_only: False,
          )),
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
      properties: dict.from_list([
        #(
          "active",
          SchemaProperty(
            field_type: Some(BooleanType),
            title: Some("Is Active"),
            description: Some("Whether the user is active"),
            default: Some(types.BooleanValue(True)),
            enum_values: None,
            ref: None,
            string_constraints: None,
            number_constraints: None,
            items: None,
            properties: None,
            required: [],
            read_only: False,
          ),
        ),
      ]),
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
      properties: dict.from_list([
        #(
          "birthdate",
          SchemaProperty(
            field_type: Some(StringType),
            title: Some("Birth Date"),
            description: None,
            default: None,
            enum_values: None,
            ref: None,
            string_constraints: Some(StringConstraints(
              min_length: None,
              max_length: None,
              pattern: None,
              format: Some(DateFormat),
            )),
            number_constraints: None,
            items: None,
            properties: None,
            required: [],
            read_only: False,
          ),
        ),
      ]),
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
      properties: dict.from_list([
        #(
          "percentage",
          SchemaProperty(
            field_type: Some(NumberType),
            title: Some("Percentage"),
            description: None,
            default: None,
            enum_values: None,
            ref: None,
            string_constraints: None,
            number_constraints: Some(NumberConstraints(
              minimum: None,
              maximum: None,
              exclusive_minimum: Some(0.0),
              exclusive_maximum: Some(100.0),
              multiple_of: None,
            )),
            items: None,
            properties: None,
            required: [],
            read_only: False,
          ),
        ),
      ]),
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
      properties: dict.from_list([
        #(
          "type",
          SchemaProperty(
            field_type: Some(StringType),
            title: Some("Type"),
            description: None,
            default: None,
            enum_values: Some([
              StringValue("personal"),
              StringValue("business"),
            ]),
            ref: None,
            string_constraints: None,
            number_constraints: None,
            items: None,
            properties: None,
            required: [],
            read_only: False,
          ),
        ),
      ]),
      required: [],
      defs: None,
      conditionals: [
        types.ConditionalRule(
          if_schema: SchemaProperty(
            field_type: None,
            title: None,
            description: None,
            default: None,
            enum_values: None,
            ref: None,
            string_constraints: None,
            number_constraints: None,
            items: None,
            properties: Some(
              dict.from_list([
                #(
                  "type",
                  SchemaProperty(
                    field_type: None,
                    title: None,
                    description: None,
                    default: None,
                    enum_values: Some([StringValue("personal")]),
                    ref: None,
                    string_constraints: None,
                    number_constraints: None,
                    items: None,
                    properties: None,
                    required: [],
                    read_only: False,
                  ),
                ),
              ]),
            ),
            required: [],
            read_only: False,
          ),
          then_schema: Some(SchemaProperty(
            field_type: None,
            title: None,
            description: None,
            default: None,
            enum_values: None,
            ref: None,
            string_constraints: None,
            number_constraints: None,
            items: None,
            properties: Some(
              dict.from_list([
                #(
                  "firstName",
                  SchemaProperty(
                    field_type: Some(StringType),
                    title: Some("First Name"),
                    description: None,
                    default: None,
                    enum_values: None,
                    ref: None,
                    string_constraints: None,
                    number_constraints: None,
                    items: None,
                    properties: None,
                    required: [],
                    read_only: False,
                  ),
                ),
              ]),
            ),
            required: [],
            read_only: False,
          )),
          else_schema: None,
        ),
        types.ConditionalRule(
          if_schema: SchemaProperty(
            field_type: None,
            title: None,
            description: None,
            default: None,
            enum_values: None,
            ref: None,
            string_constraints: None,
            number_constraints: None,
            items: None,
            properties: Some(
              dict.from_list([
                #(
                  "type",
                  SchemaProperty(
                    field_type: None,
                    title: None,
                    description: None,
                    default: None,
                    enum_values: Some([StringValue("business")]),
                    ref: None,
                    string_constraints: None,
                    number_constraints: None,
                    items: None,
                    properties: None,
                    required: [],
                    read_only: False,
                  ),
                ),
              ]),
            ),
            required: [],
            read_only: False,
          ),
          then_schema: Some(SchemaProperty(
            field_type: None,
            title: None,
            description: None,
            default: None,
            enum_values: None,
            ref: None,
            string_constraints: None,
            number_constraints: None,
            items: None,
            properties: Some(
              dict.from_list([
                #(
                  "companyName",
                  SchemaProperty(
                    field_type: Some(StringType),
                    title: Some("Company Name"),
                    description: None,
                    default: None,
                    enum_values: None,
                    ref: None,
                    string_constraints: None,
                    number_constraints: None,
                    items: None,
                    properties: None,
                    required: [],
                    read_only: False,
                  ),
                ),
              ]),
            ),
            required: [],
            read_only: False,
          )),
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
