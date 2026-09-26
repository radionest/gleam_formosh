// The library stylesheet (spec: style-layer): rendered once, as the
// container's first child, in edit and review mode, with every rule inside
// `@layer formosh`.

import formosh/form/model
import formosh/form/view
import formosh/schema/parser
import formosh/schema/types
import formosh/schema/ui_parser
import gleam/dict
import gleam/list
import gleam/option.{None}
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

pub fn every_selector_is_scoped_to_the_form_test() {
  // A plain-Lustre `<style>` is a page stylesheet: an unscoped selector would
  // style foreign elements that use the same part names.
  let css = stylesheet_text(render(False))
  { occurrences(css, ":where(") > 0 } |> should.be_true
  css
  |> occurrences(":where(.formosh-container ")
  |> should.equal(occurrences(css, ":where("))
}

const layout_schema_json = "{\"type\":\"object\",\"properties\":{\"a\":{\"type\":\"string\"},\"b\":{\"type\":\"string\"},\"zones\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"required\":[\"state\"],\"properties\":{\"state\":{\"type\":\"string\"}}}}}}"

const layout_ui_json = "{\"ui:layout\":[{\"type\":\"Row\",\"elements\":[\"a\",\"b\"]}],\"zones\":{\"ui:options\":{\"collapseCompleted\":true}}}"

pub fn layout_and_collapse_render_no_inline_style_test() {
  let assert Ok(schema) = parser.parse_schema(layout_schema_json)
  let assert Ok(ui) = ui_parser.parse(layout_ui_json)
  let m = model.init_with_full_config(schema, None, False, dict.new(), ui)
  // Row 0 complete (folds), row 1 missing its required `state` (open).
  let values =
    types.ObjectValue([
      #(
        "zones",
        types.ArrayValue([
          types.ObjectValue([#("state", types.StringValue("done"))]),
          types.ObjectValue([]),
        ]),
      ),
    ])
  let html =
    model.FormModel(..m, values: values) |> view.view |> element.to_string
  // Presence guards: the Row and both fold states really rendered, so the
  // absence check below is not vacuous.
  html |> string.contains("part=\"row\"") |> should.be_true
  html |> string.contains("data-collapsed=\"true\"") |> should.be_true
  html |> occurrences("part=\"array-item-body\"") |> should.equal(2)
  html |> string.contains(" style=\"") |> should.be_false
}
