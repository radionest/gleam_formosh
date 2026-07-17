import gleam/list
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub type Token {
  Key(String)
  StringValue(String)
  Number(String)
  Literal(String)
  Punctuation(String)
  Whitespace(String)
  Other(String)
}

pub fn to_spans(json: String) -> List(Element(a)) {
  json
  |> tokenize
  |> list.map(render_token)
}

pub fn tokenize(json: String) -> List(Token) {
  json
  |> string.to_graphemes
  |> scan([])
  |> list.reverse
}

fn scan(graphemes: List(String), acc: List(Token)) -> List(Token) {
  case graphemes {
    [] -> acc
    ["\"", ..rest] -> {
      let #(lexeme, remaining) = take_string(rest, [])
      let token = case next_is_colon(remaining) {
        True -> Key(lexeme)
        False -> StringValue(lexeme)
      }
      scan(remaining, [token, ..acc])
    }
    [g, ..rest] ->
      case g {
        "{" | "}" | "[" | "]" | ":" | "," -> scan(rest, [Punctuation(g), ..acc])
        " " | "\n" | "\t" | "\r" -> {
          let #(run, remaining) = take_while(graphemes, is_whitespace, [])
          scan(remaining, [Whitespace(run), ..acc])
        }
        "-" -> {
          let #(run, remaining) = take_while(graphemes, is_number_char, [])
          scan(remaining, [Number(run), ..acc])
        }
        _ ->
          case is_digit(g) {
            True -> {
              let #(run, remaining) = take_while(graphemes, is_number_char, [])
              scan(remaining, [Number(run), ..acc])
            }
            False ->
              case is_letter(g) {
                True -> {
                  let #(run, remaining) = take_while(graphemes, is_letter, [])
                  scan(remaining, [Literal(run), ..acc])
                }
                False -> scan(rest, [Other(g), ..acc])
              }
          }
      }
  }
}

fn take_string(
  graphemes: List(String),
  acc: List(String),
) -> #(String, List(String)) {
  case graphemes {
    [] -> #(quote(acc), [])
    ["\\", next, ..rest] -> take_string(rest, [next, "\\", ..acc])
    ["\"", ..rest] -> #(quote(acc), rest)
    [g, ..rest] -> take_string(rest, [g, ..acc])
  }
}

fn quote(reversed: List(String)) -> String {
  "\"" <> string.concat(list.reverse(reversed)) <> "\""
}

fn take_while(
  graphemes: List(String),
  pred: fn(String) -> Bool,
  acc: List(String),
) -> #(String, List(String)) {
  case graphemes {
    [g, ..rest] ->
      case pred(g) {
        True -> take_while(rest, pred, [g, ..acc])
        False -> #(string.concat(list.reverse(acc)), graphemes)
      }
    [] -> #(string.concat(list.reverse(acc)), graphemes)
  }
}

fn next_is_colon(graphemes: List(String)) -> Bool {
  case graphemes {
    [] -> False
    [g, ..rest] ->
      case is_whitespace(g) {
        True -> next_is_colon(rest)
        False -> g == ":"
      }
  }
}

fn is_whitespace(g: String) -> Bool {
  case g {
    " " | "\n" | "\t" | "\r" -> True
    _ -> False
  }
}

fn is_digit(g: String) -> Bool {
  case g {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

fn is_number_char(g: String) -> Bool {
  case is_digit(g) {
    True -> True
    False ->
      case g {
        "-" | "+" | "." | "e" | "E" -> True
        _ -> False
      }
  }
}

// Only the letters that appear in JSON bare literals: true / false / null.
fn is_letter(g: String) -> Bool {
  case g {
    "t" | "r" | "u" | "e" | "f" | "a" | "l" | "s" | "n" -> True
    _ -> False
  }
}

fn render_token(token: Token) -> Element(a) {
  case token {
    Key(text) -> span("jk", text)
    StringValue(text) -> span("js", text)
    Number(text) -> span("jn", text)
    Literal(text) -> span("jl", text)
    Punctuation(text) -> span("jp", text)
    Whitespace(text) -> html.text(text)
    Other(text) -> html.text(text)
  }
}

fn span(class: String, text: String) -> Element(a) {
  html.span([attribute.class(class)], [html.text(text)])
}
