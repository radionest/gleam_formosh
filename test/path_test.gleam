import formosh/form/path
import formosh/schema/types
import gleam/list
import gleam/option
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

// Document and pin down `set_at_path` auto-vivification: when the path
// crosses a non-container value (scalar, NullValue) the segment is
// silently rebuilt as the matching container. This is intentional — form
// renderers rely on it so writing `user.name` works even when `user`
// hasn't been initialised — but it also means the call cannot detect a
// caller bug like reusing a leaf path as a container path. The test pins
// the behaviour so any future tightening (e.g. to a Result return) stays
// a deliberate change.
pub fn set_at_path_through_scalar_auto_vivifies_test() {
  // `name` starts as a string, but we set `name.first = "Ada"`.
  let data =
    types.ObjectValue([
      #("name", types.StringValue("legacy")),
    ])

  let updated =
    path.set_at_path(
      data,
      [path.PropertySegment("name"), path.PropertySegment("first")],
      types.StringValue("Ada"),
    )

  // The scalar at `name` was replaced by an ObjectValue holding `first`.
  updated
  |> should.equal(
    types.ObjectValue([
      #("name", types.ObjectValue([#("first", types.StringValue("Ada"))])),
    ]),
  )
}

// Update one root key — verify all sibling top-level keys survive intact.
pub fn set_at_path_preserves_siblings_at_root_test() {
  let data =
    types.ObjectValue([
      #("a", types.StringValue("alpha")),
      #("b", types.NumberValue(1.0)),
      #("c", types.BooleanValue(True)),
      #("d", types.ArrayValue([types.StringValue("keep")])),
    ])

  let updated =
    path.set_at_path(data, [path.PropertySegment("b")], types.NumberValue(99.0))

  updated
  |> should.equal(
    types.ObjectValue([
      #("a", types.StringValue("alpha")),
      #("b", types.NumberValue(99.0)),
      #("c", types.BooleanValue(True)),
      #("d", types.ArrayValue([types.StringValue("keep")])),
    ]),
  )
}

// Three-level nested set must touch only the leaf and rebuild the
// containing objects without losing the sibling branches at any level.
pub fn set_at_path_three_level_nested_test() {
  let data =
    types.ObjectValue([
      #(
        "outer",
        types.ObjectValue([
          #("keep_outer_sibling", types.StringValue("o")),
          #(
            "middle",
            types.ObjectValue([
              #("keep_middle_sibling", types.StringValue("m")),
              #(
                "inner",
                types.ObjectValue([
                  #("keep_inner_sibling", types.StringValue("i")),
                  #("leaf", types.StringValue("old")),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    ])

  let leaf_path = [
    path.PropertySegment("outer"),
    path.PropertySegment("middle"),
    path.PropertySegment("inner"),
    path.PropertySegment("leaf"),
  ]
  let updated = path.set_at_path(data, leaf_path, types.StringValue("new"))

  // Leaf updated.
  path.get_at_path(updated, leaf_path)
  |> should.equal(option.Some(types.StringValue("new")))

  // All sibling branches at every level still intact.
  path.get_at_path(updated, [
    path.PropertySegment("outer"),
    path.PropertySegment("keep_outer_sibling"),
  ])
  |> should.equal(option.Some(types.StringValue("o")))

  path.get_at_path(updated, [
    path.PropertySegment("outer"),
    path.PropertySegment("middle"),
    path.PropertySegment("keep_middle_sibling"),
  ])
  |> should.equal(option.Some(types.StringValue("m")))

  path.get_at_path(updated, [
    path.PropertySegment("outer"),
    path.PropertySegment("middle"),
    path.PropertySegment("inner"),
    path.PropertySegment("keep_inner_sibling"),
  ])
  |> should.equal(option.Some(types.StringValue("i")))
}

pub fn from_string_empty_test() {
  path.from_string("")
  |> should.equal([])
}

pub fn from_string_single_property_test() {
  path.from_string("email")
  |> should.equal([path.PropertySegment("email")])
}

pub fn from_string_nested_property_test() {
  path.from_string("address.street")
  |> should.equal([
    path.PropertySegment("address"),
    path.PropertySegment("street"),
  ])
}

pub fn from_string_array_item_field_test() {
  path.from_string("lesions.[0].visible")
  |> should.equal([
    path.PropertySegment("lesions"),
    path.ArraySegment(0),
    path.PropertySegment("visible"),
  ])
}

pub fn from_string_empty_brackets_test() {
  path.from_string("[]")
  |> should.equal([path.PropertySegment("[]")])
}

pub fn from_string_round_trip_test() {
  let originals = [
    "email",
    "address.street",
    "lesions.[0].visible",
    "outer.[2].inner.[10].leaf",
  ]
  originals
  |> list.each(fn(s) {
    path.from_string(s)
    |> path.to_string
    |> should.equal(s)
  })
}

// ---- move_array_item_at_path ----

pub fn move_array_item_adjacent_test() {
  let data =
    types.ObjectValue([
      #(
        "tags",
        types.ArrayValue([
          types.StringValue("a"),
          types.StringValue("b"),
          types.StringValue("c"),
        ]),
      ),
    ])
  path.move_array_item_at_path(data, [path.PropertySegment("tags")], 0, 1)
  |> should.equal(
    types.ObjectValue([
      #(
        "tags",
        types.ArrayValue([
          types.StringValue("b"),
          types.StringValue("a"),
          types.StringValue("c"),
        ]),
      ),
    ]),
  )
}

pub fn move_array_item_far_forward_test() {
  // [a,b,c,d], move 1 -> 3  ==>  [a,c,d,b]
  let data =
    types.ObjectValue([
      #(
        "tags",
        types.ArrayValue([
          types.StringValue("a"),
          types.StringValue("b"),
          types.StringValue("c"),
          types.StringValue("d"),
        ]),
      ),
    ])
  path.move_array_item_at_path(data, [path.PropertySegment("tags")], 1, 3)
  |> should.equal(
    types.ObjectValue([
      #(
        "tags",
        types.ArrayValue([
          types.StringValue("a"),
          types.StringValue("c"),
          types.StringValue("d"),
          types.StringValue("b"),
        ]),
      ),
    ]),
  )
}

pub fn move_array_item_far_backward_test() {
  // [a,b,c,d], move 3 -> 1  ==>  [a,d,b,c]
  let data =
    types.ObjectValue([
      #(
        "tags",
        types.ArrayValue([
          types.StringValue("a"),
          types.StringValue("b"),
          types.StringValue("c"),
          types.StringValue("d"),
        ]),
      ),
    ])
  path.move_array_item_at_path(data, [path.PropertySegment("tags")], 3, 1)
  |> should.equal(
    types.ObjectValue([
      #(
        "tags",
        types.ArrayValue([
          types.StringValue("a"),
          types.StringValue("d"),
          types.StringValue("b"),
          types.StringValue("c"),
        ]),
      ),
    ]),
  )
}

pub fn move_array_item_noop_same_index_test() {
  let data =
    types.ObjectValue([
      #(
        "tags",
        types.ArrayValue([types.StringValue("a"), types.StringValue("b")]),
      ),
    ])
  path.move_array_item_at_path(data, [path.PropertySegment("tags")], 1, 1)
  |> should.equal(data)
}

pub fn move_array_item_noop_out_of_range_test() {
  let data =
    types.ObjectValue([
      #(
        "tags",
        types.ArrayValue([types.StringValue("a"), types.StringValue("b")]),
      ),
    ])
  path.move_array_item_at_path(data, [path.PropertySegment("tags")], 0, 5)
  |> should.equal(data)
}

// ---- reindex_after_array_move ----

pub fn reindex_after_move_maps_moved_row_test() {
  // move 1 -> 3 : the moved row's touched path follows to index 3.
  path.reindex_after_array_move(
    [path.PropertySegment("tags"), path.ArraySegment(1)],
    [path.PropertySegment("tags")],
    1,
    3,
  )
  |> should.equal([path.PropertySegment("tags"), path.ArraySegment(3)])
}

pub fn reindex_after_move_forward_shifts_between_rows_test() {
  // move 1 -> 3 : row 2 shifts down to 1.
  path.reindex_after_array_move(
    [path.PropertySegment("tags"), path.ArraySegment(2)],
    [path.PropertySegment("tags")],
    1,
    3,
  )
  |> should.equal([path.PropertySegment("tags"), path.ArraySegment(1)])
}

pub fn reindex_after_move_backward_shifts_test() {
  // move 3 -> 1 : row 1 shifts up to 2.
  path.reindex_after_array_move(
    [path.PropertySegment("tags"), path.ArraySegment(1)],
    [path.PropertySegment("tags")],
    3,
    1,
  )
  |> should.equal([path.PropertySegment("tags"), path.ArraySegment(2)])
}

pub fn reindex_after_move_preserves_nested_rest_test() {
  path.reindex_after_array_move(
    [
      path.PropertySegment("tags"),
      path.ArraySegment(1),
      path.PropertySegment("name"),
    ],
    [path.PropertySegment("tags")],
    1,
    3,
  )
  |> should.equal([
    path.PropertySegment("tags"),
    path.ArraySegment(3),
    path.PropertySegment("name"),
  ])
}

pub fn reindex_after_move_outside_array_unchanged_test() {
  let other = [path.PropertySegment("other"), path.ArraySegment(0)]
  path.reindex_after_array_move(other, [path.PropertySegment("tags")], 1, 3)
  |> should.equal(other)
}

// ---- relative_to / is_prefix_of ----

pub fn relative_to_exact_match_test() {
  path.relative_to([path.PropertySegment("zones")], [
    path.PropertySegment("zones"),
  ])
  |> should.equal(option.Some([]))
}

pub fn relative_to_returns_remainder_test() {
  path.relative_to(
    [
      path.PropertySegment("zones"),
      path.ArraySegment(3),
      path.PropertySegment("state"),
    ],
    [path.PropertySegment("zones")],
  )
  |> should.equal(
    option.Some([path.ArraySegment(3), path.PropertySegment("state")]),
  )
}

pub fn relative_to_unrelated_path_test() {
  path.relative_to([path.PropertySegment("other")], [
    path.PropertySegment("zones"),
  ])
  |> should.equal(option.None)
}

pub fn is_prefix_of_exact_match_test() {
  path.is_prefix_of([path.PropertySegment("zones")], [
    path.PropertySegment("zones"),
  ])
  |> should.be_true
}

pub fn is_prefix_of_deep_descendant_test() {
  path.is_prefix_of([path.PropertySegment("zones"), path.ArraySegment(3)], [
    path.PropertySegment("zones"),
    path.ArraySegment(3),
    path.PropertySegment("lesions"),
    path.ArraySegment(0),
    path.PropertySegment("form"),
  ])
  |> should.be_true
}

// Segments compare structurally, so the string-prefix hazard that would make
// "zones.[3]" match "zones.[30]" cannot occur.
pub fn is_prefix_of_sibling_index_test() {
  path.is_prefix_of([path.PropertySegment("zones"), path.ArraySegment(3)], [
    path.PropertySegment("zones"),
    path.ArraySegment(30),
  ])
  |> should.be_false
}

pub fn is_prefix_of_unrelated_test() {
  path.is_prefix_of([path.PropertySegment("zones")], [
    path.PropertySegment("other"),
    path.ArraySegment(0),
  ])
  |> should.be_false
}
