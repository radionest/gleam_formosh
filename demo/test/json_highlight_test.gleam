import gleam/string
import gleeunit/should
import json_highlight.{
  Key, Literal, Number, Punctuation, StringValue, Whitespace,
}
import lustre/element
import lustre/element/html

pub fn key_vs_value_test() {
  json_highlight.tokenize("{\"type\": \"object\"}")
  |> should.equal([
    Punctuation("{"),
    Key("\"type\""),
    Punctuation(":"),
    Whitespace(" "),
    StringValue("\"object\""),
    Punctuation("}"),
  ])
}

pub fn number_test() {
  json_highlight.tokenize("{\"n\": 42}")
  |> should.equal([
    Punctuation("{"),
    Key("\"n\""),
    Punctuation(":"),
    Whitespace(" "),
    Number("42"),
    Punctuation("}"),
  ])
}

pub fn literal_test() {
  json_highlight.tokenize("[true, null]")
  |> should.equal([
    Punctuation("["),
    Literal("true"),
    Punctuation(","),
    Whitespace(" "),
    Literal("null"),
    Punctuation("]"),
  ])
}

pub fn preserves_indentation_test() {
  json_highlight.tokenize("{\n  \"a\": 1\n}")
  |> should.equal([
    Punctuation("{"),
    Whitespace("\n  "),
    Key("\"a\""),
    Punctuation(":"),
    Whitespace(" "),
    Number("1"),
    Whitespace("\n"),
    Punctuation("}"),
  ])
}

pub fn escaped_quote_in_string_test() {
  json_highlight.tokenize("\"a\\\"b\"")
  |> should.equal([StringValue("\"a\\\"b\"")])
}

pub fn to_spans_emits_classes_test() {
  let rendered =
    html.pre([], json_highlight.to_spans("{\"a\": 1}"))
    |> element.to_string
  should.be_true(string.contains(rendered, "class=\"jk\""))
  should.be_true(string.contains(rendered, "class=\"jn\""))
}
