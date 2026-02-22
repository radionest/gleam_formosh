import formosh/form/path
import formosh/schema/types
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// Test basic path creation
pub fn from_field_name_test() {
  let path = path.from_field_name("lesions")
  path
  |> should.equal([path.PropertySegment("lesions")])
}

// Test array item field path creation  
pub fn to_array_item_field_test() {
  let path = path.to_array_item_field("lesions", 0, "description")
  path
  |> should.equal([
    path.PropertySegment("lesions"),
    path.ArraySegment(0),
    path.PropertySegment("description"),
  ])
}

// Test path to string conversion
pub fn to_string_test() {
  let path = [
    path.PropertySegment("lesions"),
    path.ArraySegment(0),
    path.PropertySegment("measurements"),
    path.ArraySegment(1),
    path.PropertySegment("value"),
  ]
  path
  |> path.to_string
  |> should.equal("lesions.[0].measurements.[1].value")
}

// Test getting value at path
pub fn get_at_path_simple_test() {
  let data =
    types.ObjectValue([
      #("name", types.StringValue("Test")),
      #("age", types.NumberValue(25.0)),
    ])

  let path = [path.PropertySegment("name")]
  let result = path.get_at_path(data, path)

  result
  |> should.equal(option.Some(types.StringValue("Test")))
}

// Test getting value from nested array
pub fn get_at_path_nested_array_test() {
  let data =
    types.ObjectValue([
      #(
        "lesions",
        types.ArrayValue([
          types.ObjectValue([
            #("description", types.StringValue("Lesion 1")),
            #(
              "measurements",
              types.ArrayValue([
                types.ObjectValue([
                  #("value", types.NumberValue(10.0)),
                  #("unit", types.StringValue("mm")),
                ]),
              ]),
            ),
          ]),
        ]),
      ),
    ])

  let path = [
    path.PropertySegment("lesions"),
    path.ArraySegment(0),
    path.PropertySegment("measurements"),
    path.ArraySegment(0),
    path.PropertySegment("value"),
  ]

  let result = path.get_at_path(data, path)
  result
  |> should.equal(option.Some(types.NumberValue(10.0)))
}

// Test setting value at path
pub fn set_at_path_simple_test() {
  let data =
    types.ObjectValue([
      #("name", types.StringValue("Old")),
    ])

  let path = [path.PropertySegment("name")]
  let new_data = path.set_at_path(data, path, types.StringValue("New"))

  new_data
  |> should.equal(
    types.ObjectValue([
      #("name", types.StringValue("New")),
    ]),
  )
}

// Test setting value in nested array - this tests the main fix!
pub fn set_at_path_nested_array_test() {
  let data =
    types.ObjectValue([
      #(
        "lesions",
        types.ArrayValue([
          types.ObjectValue([
            #("description", types.StringValue("Lesion 1")),
            #(
              "measurements",
              types.ArrayValue([
                types.ObjectValue([
                  #("value", types.NumberValue(10.0)),
                  #("unit", types.StringValue("mm")),
                ]),
              ]),
            ),
          ]),
        ]),
      ),
    ])

  let path = [
    path.PropertySegment("lesions"),
    path.ArraySegment(0),
    path.PropertySegment("measurements"),
    path.ArraySegment(0),
    path.PropertySegment("value"),
  ]

  let new_data = path.set_at_path(data, path, types.NumberValue(20.0))

  // Verify the value was updated correctly
  let result = path.get_at_path(new_data, path)
  result
  |> should.equal(option.Some(types.NumberValue(20.0)))
}

// Test adding item to nested array
pub fn add_array_item_nested_test() {
  let data =
    types.ObjectValue([
      #(
        "lesions",
        types.ArrayValue([
          types.ObjectValue([
            #("measurements", types.ArrayValue([])),
          ]),
        ]),
      ),
    ])

  let path = [
    path.PropertySegment("lesions"),
    path.ArraySegment(0),
    path.PropertySegment("measurements"),
  ]

  let new_item =
    types.ObjectValue([
      #("value", types.NumberValue(15.0)),
      #("unit", types.StringValue("cm")),
    ])

  let new_data = path.add_array_item_at_path(data, path, new_item)

  // Verify the item was added
  let check_path = [
    path.PropertySegment("lesions"),
    path.ArraySegment(0),
    path.PropertySegment("measurements"),
    path.ArraySegment(0),
    path.PropertySegment("value"),
  ]

  let result = path.get_at_path(new_data, check_path)
  result
  |> should.equal(option.Some(types.NumberValue(15.0)))
}

import gleam/option
