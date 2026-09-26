// The library stylesheet (spec: style-layer): rendered once, as the
// container's first child, in edit and review mode, with every rule inside
// `@layer formosh`.

import formosh/form/model
import formosh/form/view
import formosh/schema/parser
import gleam/list
import gleam/string
import gleeunit/should
import lustre/element

const schema_json = "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}}}"

fn render(read_only: Bool) -> String {
  let assert Ok(schema) = parser.parse_schema(schema_json)
  model.FormModel(..model.init(schema), read_only: read_only)
  |> view.view
  |> element.to_string
}

fn occurrences(html: String, needle: String) -> Int {
  list.length(string.split(html, needle)) - 1
}

fn stylesheet_text(html: String) -> String {
  let assert Ok(#(_, after_open)) = string.split_once(html, "<style>")
  let assert Ok(#(css, _)) = string.split_once(after_open, "</style>")
  css
}

/// Grapheme index where the brace depth first returns to zero — where the
/// first top-level block closes.
fn first_top_level_close(css: String) -> Result(Int, Nil) {
  let #(_, closed_at) =
    css
    |> string.to_graphemes
    |> list.index_fold(#(0, Error(Nil)), fn(acc, grapheme, index) {
      case acc, grapheme {
        #(_, Ok(_)), _ -> acc
        #(depth, found), "{" -> #(depth + 1, found)
        #(1, _), "}" -> #(0, Ok(index))
        #(depth, found), "}" -> #(depth - 1, found)
        _, _ -> acc
      }
    })
  closed_at
}

fn assert_first_child_is_the_stylesheet(html: String) -> Nil {
  let assert Ok(#(_, inside_container)) =
    string.split_once(html, "part=\"container\">")
  inside_container |> string.starts_with("<style>") |> should.be_true
  html |> occurrences("<style>") |> should.equal(1)
}

pub fn stylesheet_is_the_containers_first_child_in_edit_mode_test() {
  render(False) |> assert_first_child_is_the_stylesheet
}

pub fn stylesheet_is_the_containers_first_child_in_review_mode_test() {
  render(True) |> assert_first_child_is_the_stylesheet
}

pub fn every_rule_sits_inside_the_formosh_layer_test() {
  let css = stylesheet_text(render(False))
  css |> string.starts_with("@layer formosh {") |> should.be_true
  // The layer's block is the only top-level block: it closes on the last
  // character, so no rule can follow it unlayered.
  first_top_level_close(css) |> should.equal(Ok(string.length(css) - 1))
}
