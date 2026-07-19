// Render guard for number inputs whose schema combines a lower bound with
// multipleOf. HTML computes stepping from the `min` attribute, while JSON
// Schema anchors multipleOf at 0 — the rendered `min` must therefore be the
// smallest multiple satisfying the bound, or the native stepper would emit
// values the validator (correctly) rejects: minimum 1 + multipleOf 2 must
// step 2, 4, 6…, not 1, 3, 5…

import formosh/form/model
import formosh/form/view
import formosh/schema/parser
import gleam/string
import gleeunit/should
import lustre/element

fn render_number_schema(prop_json: String) -> String {
  let json =
    "{\"type\": \"object\", \"properties\": {\"n\": " <> prop_json <> "}}"
  let assert Ok(schema) = parser.parse_schema(json)
  model.init(schema)
  |> view.view
  |> element.to_string
}

pub fn min_aligned_up_to_first_multiple_test() {
  let html =
    render_number_schema(
      "{\"type\": \"number\", \"minimum\": 1, \"multipleOf\": 2}",
    )
  html |> string.contains("min=\"2.0\"") |> should.be_true
  html |> string.contains("min=\"1.0\"") |> should.be_false
  html |> string.contains("step=\"2.0\"") |> should.be_true
}

pub fn min_kept_when_already_a_multiple_test() {
  let html =
    render_number_schema(
      "{\"type\": \"number\", \"minimum\": 4, \"multipleOf\": 2}",
    )
  html |> string.contains("min=\"4.0\"") |> should.be_true
}

pub fn min_unchanged_without_multiple_of_test() {
  let html = render_number_schema("{\"type\": \"number\", \"minimum\": 1}")
  html |> string.contains("min=\"1.0\"") |> should.be_true
}

pub fn exclusive_min_aligned_to_next_multiple_test() {
  let html =
    render_number_schema(
      "{\"type\": \"number\", \"exclusiveMinimum\": 2, \"multipleOf\": 2}",
    )
  html |> string.contains("min=\"4.0\"") |> should.be_true
}

pub fn fractional_multiple_min_aligned_test() {
  let html =
    render_number_schema(
      "{\"type\": \"number\", \"minimum\": 0.15, \"multipleOf\": 0.1}",
    )
  html |> string.contains("min=\"0.2\"") |> should.be_true
}

pub fn negative_min_aligned_test() {
  let html =
    render_number_schema(
      "{\"type\": \"number\", \"minimum\": -3, \"multipleOf\": 2}",
    )
  html |> string.contains("min=\"-2.0\"") |> should.be_true
}
