// Direct unit tests for `formosh/form/model` predicates over `model.errors`
// — the model-level sibling of `path_test.gleam`. Errors are injected
// directly via `model.add_error_at_path`, so these don't need the
// parser/update pipeline.

import formosh/form/model
import formosh/form/path.{type FieldPath, ArraySegment, PropertySegment}
import formosh/schema/types.{type JsonSchema, JsonSchema, ObjectType}
import formosh/validation/error.{ValidationError}
import gleam/option.{None}
import gleeunit/should

fn empty_schema() -> JsonSchema {
  JsonSchema(
    title: None,
    description: None,
    field_type: ObjectType,
    properties: [],
    required: [],
    defs: None,
    conditionals: [],
    all_of: None,
    string_constraints: None,
    number_constraints: None,
  )
}

fn with_error_at(m: model.FormModel, field_path: FieldPath) -> model.FormModel {
  model.add_error_at_path(
    m,
    field_path,
    ValidationError(field: field_path, message: "bad", rule: "custom"),
  )
}

// ---- has_errors_under_path ----

// The case `has_errors_at_path` cannot do: an error recorded on a nested
// field of a row is still found by a scan rooted at the row's own prefix.
pub fn has_errors_under_path_finds_nested_field_error_test() {
  let m =
    model.init(empty_schema())
    |> with_error_at([
      PropertySegment("zones"),
      ArraySegment(0),
      PropertySegment("state"),
    ])

  model.has_errors_under_path(m, [PropertySegment("zones"), ArraySegment(0)])
  |> should.be_true()
}

// Segments compare structurally: an error on row 30 must not be found
// under a different row's prefix (row 3) — the string-prefix hazard
// ("zones.[3]" matching "zones.[30]") cannot occur.
pub fn has_errors_under_path_sibling_index_false_test() {
  let m =
    model.init(empty_schema())
    |> with_error_at([PropertySegment("zones"), ArraySegment(30)])

  model.has_errors_under_path(m, [PropertySegment("zones"), ArraySegment(3)])
  |> should.be_false()
}

// An array-level error (e.g. minItems) recorded on `zones` itself is not
// found under a row's own prefix `zones.[0]`: the prefix is longer than
// the error's own path, so the error lies outside that subtree. A
// row-collapse predicate built on this must not keep every row open just
// because the array as a whole is too short.
pub fn has_errors_under_path_prefix_longer_than_error_path_false_test() {
  let m =
    model.init(empty_schema())
    |> with_error_at([PropertySegment("zones")])

  model.has_errors_under_path(m, [PropertySegment("zones"), ArraySegment(0)])
  |> should.be_false()
}

// Exact match: an error recorded at the prefix itself counts as "under" it.
pub fn has_errors_under_path_exact_match_true_test() {
  let m =
    model.init(empty_schema())
    |> with_error_at([PropertySegment("zones"), ArraySegment(0)])

  model.has_errors_under_path(m, [PropertySegment("zones"), ArraySegment(0)])
  |> should.be_true()
}
