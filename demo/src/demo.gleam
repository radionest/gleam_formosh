import formosh
import formosh/component
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lustre
import lustre/attribute
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/keyed
import lustre/event
import rsvp
import validators

const submit_url = "http://localhost:8888"

const form_element_id = "demo-formosh-form"

/// Map a schema filename to a cross-field validator kind, if any.
///
/// The kind string must match a key in the `VALIDATORS` table in
/// `validators_ffi.mjs`. Schemas not in this list render with no
/// cross-field validation.
fn validator_kind_for(filename: String) -> Option(String) {
  case filename {
    "budget_split.json" -> Some("budget_split")
    "date_range.json" -> Some("date_range")
    "password_confirm.json" -> Some("password_confirm")
    _ -> None
  }
}

pub type Model {
  Model(
    selected_schema: Option(String),
    // Editor text, updated on every keystroke.
    schema_draft: Option(String),
    ui_schema_draft: String,
    // The last draft that parsed — what the form renders.
    schema_content: Option(String),
    ui_schema_content: Option(String),
    schema_error: Option(String),
    ui_schema_error: Option(String),
    css: String,
    // Bumped to recreate <formosh-form>: Lustre copies page stylesheets
    // into its shadow root only once, when the element is created.
    form_key: Int,
    available_schemas: List(String),
    error: Option(String),
    submission_result: Option(String),
  )
}

pub type Msg {
  LoadSchema(String)
  SchemaFetched(Result(String, String))
  UiSchemaFetched(Option(String))
  CssFetched(Result(String, rsvp.Error))
  SchemaEdited(String)
  UiSchemaEdited(String)
  CssEdited(String)
  CssCommitted
  FormSubmitted(dict.Dict(String, String))
  ClearSubmissionResult
}

pub fn main() {
  let _ = component.register()

  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

pub fn init(_) -> #(Model, effect.Effect(Msg)) {
  // Browsers can't list directories — keep the catalogue here. Pair a
  // schema with a `<basename>.ui.json` to show UiSchema-driven rendering.
  let schemas = [
    "numeric_options.json",
    "carcinomatosis_review.json",
    "carcinomatosis_radiology.json",
    "widgets_demo.json",
    "contact_form.json",
    "survey_form.json",
    "user_registration.json",
    "pattern_validation.json",
    "layout_showcase.json",
    "basic_leak_signs.json",
    "array_editable_test.json",
    "array_readonly_test.json",
    "array_readonly_test_full.json",
    "hidden_fields_test.json",
    "composition_test.json",
    "root_ref_composition.json",
    "budget_split.json",
    "date_range.json",
    "password_confirm.json",
    "union_branches.json",
  ]

  #(
    Model(
      selected_schema: None,
      schema_draft: None,
      ui_schema_draft: "",
      schema_content: None,
      ui_schema_content: None,
      schema_error: None,
      ui_schema_error: None,
      css: "",
      form_key: 0,
      available_schemas: schemas,
      error: None,
      submission_result: None,
    ),
    fetch_css(),
  )
}

pub fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    LoadSchema(filename) -> {
      #(
        Model(
          ..model,
          selected_schema: Some(filename),
          schema_draft: None,
          ui_schema_draft: "",
          schema_content: None,
          ui_schema_content: None,
          schema_error: None,
          ui_schema_error: None,
          error: None,
        ),
        effect.batch([fetch_schema(filename), fetch_ui_schema(filename)]),
      )
    }

    SchemaFetched(result) -> {
      case result {
        Ok(content) -> #(
          set_schema(Model(..model, error: None), content),
          attach_validator_effect(model.selected_schema),
        )
        Error(error) -> #(
          Model(
            ..model,
            schema_content: None,
            error: Some("Failed to load schema: " <> error),
          ),
          effect.none(),
        )
      }
    }

    UiSchemaFetched(content) -> {
      #(set_ui_schema(model, option.unwrap(content, "")), effect.none())
    }

    CssFetched(Ok(css)) -> #(
      Model(..model, css: css, form_key: model.form_key + 1),
      attach_validator_effect(model.selected_schema),
    )
    // Shown in the CSS editor itself: `model.error` is cleared by the
    // next schema pick.
    CssFetched(Error(_)) -> #(
      Model(..model, css: "/* Failed to load form-theme.css */"),
      effect.none(),
    )

    SchemaEdited(text) -> #(set_schema(model, text), effect.none())
    UiSchemaEdited(text) -> #(set_ui_schema(model, text), effect.none())
    CssEdited(css) -> #(Model(..model, css: css), effect.none())
    CssCommitted -> #(
      Model(..model, form_key: model.form_key + 1),
      attach_validator_effect(model.selected_schema),
    )

    FormSubmitted(values) -> {
      let result_message = case dict.get(values, "error") {
        Ok(error) -> "Error: " <> error
        Error(_) ->
          case dict.get(values, "response") {
            Ok(response) -> "Success! Server response: " <> response
            Error(_) -> "Form submitted to " <> submit_url
          }
      }

      #(Model(..model, submission_result: Some(result_message)), effect.none())
    }

    ClearSubmissionResult -> {
      #(Model(..model, submission_result: None), effect.none())
    }
  }
}

// A draft that fails to parse keeps the form on the last one that did.
fn set_schema(model: Model, text: String) -> Model {
  case formosh.from_json_string(text) {
    Ok(_) ->
      Model(
        ..model,
        schema_draft: Some(text),
        schema_content: Some(text),
        schema_error: None,
      )
    Error(err) ->
      Model(
        ..model,
        schema_draft: Some(text),
        schema_error: Some(string.inspect(err)),
      )
  }
}

fn set_ui_schema(model: Model, text: String) -> Model {
  case string.trim(text), formosh.parse_ui_schema(text) {
    "", _ ->
      Model(
        ..model,
        ui_schema_draft: text,
        ui_schema_content: None,
        ui_schema_error: None,
      )
    _, Ok(_) ->
      Model(
        ..model,
        ui_schema_draft: text,
        ui_schema_content: Some(text),
        ui_schema_error: None,
      )
    _, Error(err) ->
      Model(
        ..model,
        ui_schema_draft: text,
        ui_schema_error: Some(string.inspect(err)),
      )
  }
}

fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("page")], [
    // A page stylesheet, so <formosh-form> adopts it like any other.
    html.style([], model.css),
    masthead(),
    html.section([], [
      section_head("Schema catalogue", schema_count(model.available_schemas)),
      html.div(
        [attribute.class("schema-list")],
        list.map(model.available_schemas, fn(filename) {
          schema_chip(filename, is_selected(model, filename))
        }),
      ),
    ]),
    case model.error {
      Some(error) ->
        html.div([attribute.class("error-message")], [
          html.span([attribute.class("error-mark")], [html.text("!")]),
          html.span([], [html.text(error)]),
        ])
      None -> element.none()
    },
    case model.submission_result {
      Some(result) -> submission_banner(result)
      None -> element.none()
    },
    form_section(model),
  ])
}

fn masthead() -> Element(Msg) {
  html.header([attribute.class("masthead")], [
    html.p([attribute.class("eyebrow")], [
      html.span([attribute.class("diamond")], [html.text("◆")]),
      html.text("Gleam · Lustre · JSON Schema"),
    ]),
    html.h1([attribute.class("wordmark")], [
      html.text("Formosh"),
      html.span([attribute.class("wordmark-dot")], [html.text(".")]),
    ]),
    html.div([attribute.class("field-shell")], [
      html.span([attribute.class("field-shell-label")], [
        html.text("what is this"),
      ]),
      html.p([attribute.class("field-value")], [
        html.text("A JSON Schema, rendered to a live, typed form."),
        html.span([attribute.class("caret")], []),
      ]),
    ]),
  ])
}

fn section_head(label: String, note: String) -> Element(Msg) {
  html.div([attribute.class("section-head")], [
    html.span([attribute.class("section-label")], [
      html.span([attribute.class("section-mark")], []),
      html.text(label),
    ]),
    html.span([attribute.class("section-note")], [html.text(note)]),
  ])
}

fn schema_count(schemas: List(String)) -> String {
  int.to_string(list.length(schemas)) <> " schemas"
}

fn is_selected(model: Model, filename: String) -> Bool {
  case model.selected_schema {
    Some(selected) -> selected == filename
    None -> False
  }
}

fn schema_chip(filename: String, selected: Bool) -> Element(Msg) {
  html.button(
    [
      event.on_click(LoadSchema(filename)),
      attribute.class(case selected {
        True -> "schema-button selected"
        False -> "schema-button"
      }),
    ],
    [
      html.div([attribute.class("schema-file-row")], [
        html.code([attribute.class("schema-file")], [html.text(filename)]),
        html.span([attribute.class("schema-go")], [
          html.text(case selected {
            True -> "● selected"
            False -> "→"
          }),
        ]),
      ]),
      html.span([attribute.class("schema-name")], [
        html.text(get_display_name(filename)),
      ]),
    ],
  )
}

fn submission_banner(result: String) -> Element(Msg) {
  let is_error = string.contains(result, "Error")
  html.div(
    [
      attribute.class(case is_error {
        True -> "form-status error"
        False -> "form-status success"
      }),
    ],
    [
      html.span([], [html.text(result)]),
      html.button(
        [
          event.on_click(ClearSubmissionResult),
          attribute.class("clear-button"),
        ],
        [html.text("×")],
      ),
    ],
  )
}

fn form_section(model: Model) -> Element(Msg) {
  case model.schema_draft {
    Some(schema_draft) ->
      html.div([attribute.class("workbench two-pane")], [
        transform_bar(option.unwrap(model.selected_schema, "schema.json")),
        html.div([attribute.class("workbench-body")], [
          info_chips(model),
          html.div([attribute.class("split")], [
            form_pane(model),
            editor_pane(model, schema_draft),
          ]),
        ]),
      ])
    None ->
      case model.selected_schema {
        None ->
          placeholder("Pick a schema above to render it as a live, typed form.")
        Some(_) -> placeholder("Loading schema…")
      }
  }
}

fn transform_bar(filename: String) -> Element(Msg) {
  html.div([attribute.class("transform-bar")], [
    html.code([attribute.class("tb-file")], [html.text(filename)]),
    html.span([attribute.class("tb-arrow")], [html.text("→")]),
    html.span([attribute.class("tb-out")], [html.text("live form")]),
  ])
}

fn info_chips(model: Model) -> Element(Msg) {
  let ui_chip = case model.ui_schema_content {
    Some(_) -> [chip("ui-schema", "applied")]
    None -> []
  }
  let validator_chip = case
    model.selected_schema
    |> option.then(validator_kind_for)
  {
    Some(kind) -> [chip("validator", kind)]
    None -> []
  }
  html.div(
    [attribute.class("info-chips")],
    list.flatten([[chip("json-schema", "2020-12")], ui_chip, validator_chip]),
  )
}

fn chip(key: String, value: String) -> Element(Msg) {
  html.span([attribute.class("chip")], [
    html.span([attribute.class("chip-key")], [html.text(key)]),
    html.text(value),
  ])
}

pub fn form_pane(model: Model) -> Element(Msg) {
  case model.schema_content {
    Some(schema_json) ->
      keyed.div([attribute.id("form-mount-point")], [
        #(
          int.to_string(model.form_key),
          element.element(
            "formosh-form",
            form_attributes(schema_json, model.ui_schema_content),
            [],
          ),
        ),
      ])
    None -> placeholder("Fix the schema to render the form.")
  }
}

fn editor_pane(model: Model, schema_draft: String) -> Element(Msg) {
  html.div([attribute.class("schema-pane")], [
    editor(
      "schema",
      schema_draft,
      [event.on_input(SchemaEdited)],
      error_note(model.schema_error),
    ),
    editor(
      "ui-schema",
      model.ui_schema_draft,
      [event.on_input(UiSchemaEdited)],
      error_note(model.ui_schema_error),
    ),
    editor(
      "css",
      model.css,
      [event.on_input(CssEdited)],
      // An explicit button, not blur: recreating the form on blur would
      // swallow the click that moved focus into it.
      html.div([attribute.class("code-note")], [
        html.span([], [
          html.text(
            "::part() rules and --formosh-* tokens apply as you type. "
            <> "Other selectors need Apply, which recreates the form to "
            <> "re-adopt the stylesheet and clears its values.",
          ),
        ]),
        html.button(
          [attribute.class("apply-button"), event.on_click(CssCommitted)],
          [html.text("Apply")],
        ),
      ]),
    ),
  ])
}

fn editor(
  label: String,
  content: String,
  handlers: List(attribute.Attribute(Msg)),
  note: Element(Msg),
) -> Element(Msg) {
  html.div([attribute.class("code-block")], [
    html.span([attribute.class("code-label")], [html.text(label)]),
    html.textarea(
      [
        attribute.class("code-editor"),
        attribute.attribute("aria-label", label),
        attribute.attribute("spellcheck", "false"),
        ..handlers
      ],
      content,
    ),
    note,
  ])
}

fn error_note(error: Option(String)) -> Element(Msg) {
  case error {
    Some(message) ->
      html.div([attribute.class("code-note error")], [html.text(message)])
    None -> element.none()
  }
}

fn placeholder(message: String) -> Element(Msg) {
  html.div([attribute.class("placeholder")], [
    html.span([attribute.class("placeholder-mark")], [html.text("{ }")]),
    html.p([], [html.text(message)]),
  ])
}

fn form_attributes(
  schema_json: String,
  ui_schema: Option(String),
) -> List(attribute.Attribute(Msg)) {
  let base = [
    attribute.id(form_element_id),
    attribute.attribute("schema", schema_json),
    attribute.attribute("submit-url", submit_url),
    attribute.attribute("submit-method", "POST"),
    event.on("formosh-submit", decode_form_submit()),
  ]
  case ui_schema {
    Some(json) -> [attribute.attribute("ui-schema", json), ..base]
    None -> base
  }
}

/// Build an effect that attaches the right cross-field validator (or
/// detaches any previous one) once Lustre has rendered the form. Must run
/// after paint: a synchronous effect would reach the element before the
/// render creates (or, after a `form_key` bump, replaces) it.
fn attach_validator_effect(filename: Option(String)) -> effect.Effect(Msg) {
  effect.after_paint(fn(_dispatch, _root) {
    case filename {
      None -> validators.detach_validator(form_element_id)
      Some(name) ->
        case validator_kind_for(name) {
          Some(kind) -> validators.attach_validator(form_element_id, kind)
          None -> validators.detach_validator(form_element_id)
        }
    }
  })
}

fn get_display_name(filename: String) -> String {
  filename
  |> string.replace(".json", "")
  |> string.replace("_", " ")
  |> string.replace("-", " ")
  |> string.capitalise()
}

fn fetch_css() -> effect.Effect(Msg) {
  rsvp.get("./form-theme.css", rsvp.expect_text(CssFetched))
}

fn fetch_schema(filename: String) -> effect.Effect(Msg) {
  let url = "./schemas/" <> filename
  let handler =
    rsvp.expect_any_response(fn(fetch_result) {
      case fetch_result {
        Ok(json_string) -> SchemaFetched(Ok(json_string.body))
        Error(error) ->
          case error {
            rsvp.HttpError(resp) -> SchemaFetched(Error(resp.body))
            rsvp.NetworkError -> SchemaFetched(Error("Network error"))
            rsvp.BadUrl(u) -> SchemaFetched(Error("BAD url " <> u))
            rsvp.BadBody -> SchemaFetched(Error("Bad body"))
            _ -> SchemaFetched(Error("Can't fetch schema at " <> url))
          }
      }
    })
  rsvp.get(url, handler)
}

// UiSchema is optional. A missing `.ui.json` yields a non-JSON response
// (a 404 error page), so we sniff for a leading `{` to tell a real JSON
// object from an error page before treating it as a UiSchema.
fn fetch_ui_schema(filename: String) -> effect.Effect(Msg) {
  let basename = string.replace(filename, ".json", "")
  let url = "./schemas/" <> basename <> ".ui.json"
  let handler =
    rsvp.expect_any_response(fn(fetch_result) {
      case fetch_result {
        Ok(resp) ->
          case string.starts_with(string.trim(resp.body), "{") {
            True -> UiSchemaFetched(Some(resp.body))
            False -> UiSchemaFetched(None)
          }
        Error(_) -> UiSchemaFetched(None)
      }
    })
  rsvp.get(url, handler)
}

fn decode_form_submit() -> decode.Decoder(Msg) {
  use event_data <- decode.then(decode.at(["detail"], decode.dynamic))

  let status =
    decode.run(event_data, decode.at(["status"], decode.string))
    |> result.unwrap("unknown")

  let values = case status {
    "success" ->
      decode.run(event_data, decode.at(["data"], decode.string))
      |> result.map(fn(data) { dict.from_list([#("response", data)]) })
      |> result.unwrap(dict.new())
    "error" ->
      decode.run(event_data, decode.at(["error"], decode.string))
      |> result.map(fn(error) { dict.from_list([#("error", error)]) })
      |> result.unwrap(dict.new())
    _ -> dict.new()
  }

  decode.success(FormSubmitted(values))
}
