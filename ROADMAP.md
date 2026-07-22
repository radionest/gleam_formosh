# Formosh — Roadmap

Stages are ordered so that each delivers complete value on its own, minimizes
breaking changes for the previous ones, and lays the foundation for the next.
No version pinning — what matters is priority and dependency order, not
release numbers. Sizes are rough estimates for solo development:
S < 1 week, M ≈ 1–2 weeks, L ≈ 2–4 weeks, XL > 1 month.

Checkboxes reflect the state as of July 2026 (v0.8.4).

---

## API debts (docs audit, July 2026)

Found while auditing `docs/` against `src/`; removed from the documentation
as non-existent — they wait here for implementation (or a deliberate "won't
do"):

- [ ] **Emit `formosh-validate`.** `component.on_validate` subscribes to an
  event nothing sends (`component.gleam` emits only `formosh-ready` /
  `formosh-change` / `formosh-submitting` / `formosh-submit`). Either emit
  it on validity changes or delete the helper.
- [ ] **HTTP headers from the web component.** `with_http_submit` accepts
  headers, but there is no attribute for them. Add `submit-headers` taking a
  JSON object.
- [ ] **Wire `ui:widget: "toggle"`.** `boolean_field.render_as_toggle` (and
  the `toggle`, `toggle-wrapper`, `toggle-slider`, `toggle-text` parts plus
  `data-state`) exist, but the dispatcher always renders radios. Hook it up
  in the dispatcher; systematically solved by the Widget Registry.
- [ ] **No re-exports from the root module.** `formosh.StringValue` /
  `formosh.FormModel` do not compile — Gleam cannot re-export constructors.
  Consider wrapper functions (`formosh.string_value(...)`) for ergonomics.
- [ ] **Configurable CSS class prefix** — claimed in the README but never
  implemented (claim removed). Decide: implement or drop for good (partially
  covered by the Theming pack).
- [ ] **`format: "date" / "time" / "datetime"` render as plain text.**
  `format_decoder` (`parser.gleam`) wires only `email` / `url`+`uri` /
  `uuid` to typed variants; `DateFormat` / `TimeFormat` / `DateTimeFormat`
  and their `get_input_type` mappings exist but are unreachable from parsed
  schemas. Extend `format_decoder` to get native pickers.
- [ ] **`with_show_errors_on_change` is a no-op.** The flag is stored on
  `FormConfig`, but `create_form_with_config` never forwards it to
  `model.init_with_full_config` and nothing under `src/` reads it — errors
  always follow the touch gate. Wire it into the model (or drop the
  builder).

---

## UI Schema (foundation) — shipped

**Goal.** Separate "data" from "presentation". Without this, every further
feature would drag `x-widget`-style dirt into the JSON Schema.

**Scope:** L. **Breaking:** minor (`x-widget` still read, but deprecated).

- [x] Parallel `UiSchema` structure with the same path addressing as
  `FieldPath` (tree isomorphic to the JSON Schema)
- [x] `ui:widget`, `ui:options`, `ui:order`, `ui:placeholder`, `ui:help`,
  `ui:autofocus`, `ui:disabled`, `ui:readonly`, `ui:title`,
  `ui:description` (plus `ui:addable`, `ui:removable`, `ui:orderable`,
  `ui:accept`, `ui:maxFileSize`)
- [x] Separate parser `formosh/schema/ui_parser.gleam` — `schema/parser.gleam`
  stays clean
- [x] Config builders: `with_ui_schema` / `with_ui_schema_json`
- [x] Web component: `ui-schema='{...}'` attribute
- [x] Migration: `x-widget: "hidden"` → `ui:widget: "hidden"`; `x-*` read as
  deprecated fallback for two more versions
- [ ] Remove the `x-*` fallback (scheduled after the deprecation window)

---

## Widget Registry

**Goal.** Let users register their own widget without forking the library.
The "second layer of the foundation" together with UI Schema.

**Scope:** L. **Breaking:** no (API addition). **Depends on:** UI Schema.

- [ ] `Widget(msg)` type — record
  `{ name: String, render: fn(WidgetContext) -> Element(msg), parse_value: fn(String) -> Value }`
- [ ] `WidgetContext` — record with `path`, `schema_node`, `ui_options`,
  `current_value`, `errors`, `dispatch: fn(Msg) -> Nil`. This is the public
  contract.
- [ ] Builders: `formosh.with_widget(name, widget)`, `formosh.with_widgets(list)`
- [ ] Runtime: `field_dispatcher` checks the user registry first, then the
  default registry. Built-in widgets are expressed through the same contract
  — eat the dog food.
- [ ] Optional widget lifecycle hooks: `on_mount`, `on_value_change`, `on_blur`
- [ ] Example `examples/custom_widget` — a simple color picker via FFI to
  `<input type="color">`

**Files:** `src/formosh/widgets/registry.gleam` (new),
`src/formosh/widgets/context.gleam` (new); rewrite all `fields/*_field.gleam`
as `Widget` implementations (rendering unchanged) — after that
`field_dispatcher.gleam` shrinks to a dispatch table.

**Acceptance:** a user-registered widget renders via `ui:widget: "my-widget"`;
all built-in fields go through the same registry (no second rendering path);
a custom widget receives `dispatch` and can update the `FormModel`.

---

## JSON Schema gap-closing

**Goal.** Close the basic standard keywords without which Formosh can't be
called a "JSON Schema form generator" without disclaimers.

**Scope:** M. **Breaking:** no.

- [x] `pattern` — enforced via `gleam_regexp` (no FFI needed; partial-match
  per draft 2020-12 §6.3.3)
- [x] `minItems` / `maxItems` — length validation plus add/remove button
  gating
- [x] `multipleOf` — tolerant comparison (1e-8), also drives the `step`
  attribute
- [x] `enum` value validation
- [x] `anyOf` with schemas (not just const) — null members collapse into a
  `nullable` flag, a single surviving member merges into the node
  (`Optional[X]`), 2+ surviving members render a branch chooser; the
  selection is stored in `FormModel.selected_branches`, a
  `List(#(FieldPath, Int))` association list (not a `Dict` — `FieldPath` is
  a `List`, so `list.key_find`/`key_set` do the lookup). `oneOf` schema
  variants remain unimplemented — see [Schema Keywords](docs/reference/schema-keywords.md#composition).
- [ ] `dependencies` / `dependentRequired` / `dependentSchemas` — recompute
  required/subschema on key change; same logic as `if/then/else`, reuse
  `conditional_resolver.gleam`
- [ ] `additionalProperties: false` — drop keys not described in `properties`
  from `get_values`; `additionalProperties: { type: ... }` — render a
  key/value editor (dict-like)
- [ ] `not` — validation only (not rendering); negate any check
- [ ] RFC-grade email/url validation via the patterns from the JSON Schema
  spec (current checks are lax substring tests)

**Acceptance:** these keywords pass the official JSON Schema Test Suite
(at minimum the happy path for draft 2020-12); the README "What's NOT
Implemented" section shrinks by ~60%.

---

## Layouts

**Goal.** Enable forms more complex than "everything top-to-bottom".

**Scope:** M. **Breaking:** no. **Depends on:** UI Schema.

- [ ] Layout nodes in UI Schema (as in JSONForms):
  `{ "type": "VerticalLayout" | "HorizontalLayout" | "Group" | "Categorization", "elements": [...], "label"?: ... }`;
  leaves are `{ "type": "Control", "scope": "#/properties/foo" }`
- [ ] No `ui_schema` → fall back to the current linear render (back-compat)
- [ ] `Group` — `<fieldset>` with a legend
- [ ] `HorizontalLayout` — CSS grid, equal columns
- [ ] `Categorization` — tabs (no wizard yet)

**Files:** `src/formosh/schema/ui_schema.gleam` (layout union type),
`src/formosh/fields/layout.gleam` (new), `src/formosh/form/view.gleam`
(branch point: root layout present → render it, otherwise the old flow).

**Acceptance:** demo with a 2-column layout, a nested `Group`, and tabs over
3 sections; everything works as before without a `ui_schema`.

---

## Wizard / multi-step

**Goal.** Long forms (surveys, checkout) — step-by-step UI with per-step
validation.

**Scope:** M. **Breaking:** no. **Depends on:** Layouts (`Categorization`
already provides half of it).

- [ ] `Wizard` layout — a special case of `Categorization` with Prev/Next
  navigation and Submit on the last step
- [ ] Step validation: the user cannot leave step N while its visible fields
  have errors
- [ ] Progress bar as dedicated parts (`progress`, `progress-step`)
- [ ] UI Schema options: `linear: bool` (can the user jump ahead),
  `allow_back: bool`
- [ ] Model state: `current_step: Int`, `visited_steps: Set(Int)`

**Files:** `src/formosh/fields/wizard.gleam` (new), wizard state in
`form/model.gleam`, `NextStep` / `PrevStep` / `GoToStep(Int)` in
`form/update.gleam`.

**Acceptance:** 3-step demo; errors on step 1 block the transition; Submit
fires only from the last step.

---

## Async / server-side validation

**Goal.** "Email already taken", "tax ID not found in the registry". Without
this you can't build registrations or any form backed by reference data.

**Scope:** M. **Breaking:** no.

- [ ] API: `formosh.with_async_validator(field_path, validator)` where
  `validator: fn(Value) -> Effect(Result(Nil, String))`
- [ ] Debounce: 500 ms default, tunable via `ui:options.debounce_ms`
- [ ] Model: `pending_validations: Set(FieldPath)`; spinner on the field in
  the view
- [ ] Submit waits for all pending validations to finish
- [ ] Backend errors in a separate `model.async_errors` channel, merged with
  `model.errors` at display time
- [ ] Web component: `async-validate-url` attribute sending
  `{ field, value }` and accepting `{ valid: bool, message?: string }`

**Files:** `src/formosh/validation/async.gleam` (new); debounce logic and
response handling in `form/update.gleam`.

**Acceptance:** demo where typing an email fires a request after 500 ms,
spinner shows, then either ✓ or an error message; submit waits while a field
is still being checked.

---

## Expressions / calculated fields / cross-field rules

**Goal.** Form business logic: "total = price × quantity", "end date not
before start date", "if option A is selected, field B is required".

**Scope:** XL. **Breaking:** no. **Depends on:** UI Schema (carries the
expressions).

- [ ] Expression mini-DSL (own parser, no eval). Grammar: number / string /
  bool / null literals; identifiers `$.foo.bar` (from the root) and
  `@.sibling` (relative); operators `+ - * / %`, `== != < <= > >=`,
  `&& ||`, `!`; functions `iif(cond, a, b)`, `today()`,
  `sum($.items[*].price)`, `length($.items)`, `contains(str, sub)`
- [ ] Application points in UI Schema:
  `ui:value_expression: "@.price * @.qty"` (computed field, input disabled),
  `ui:visible_if: "$.type == 'company'"` (simpler alternative to
  `if/then/else`), `ui:enabled_if`, `ui:required_if`
- [ ] Reactivity: on any path change, collect dependent expressions and
  recompute them; the dependency graph is built once while parsing the
  UI Schema
- [ ] Dependency cycles detected at parse time → `ParseError`

**Files:** `src/formosh/expr/{parser,ast,eval,dependencies}.gleam` (all new);
recompute hook in `form/update.gleam`; dedicated `test/expr_test.gleam` with
an operator/precedence matrix.

**Acceptance:** order-form demo — qty, price, computed total updating live;
cross-field validation `end_date >= start_date` via `required_if` or an
explicit validator.

---

## Generic file upload + async enum

**Goal.** Unify file uploads (currently only image-upload, hardcoded,
top-level only). Provide typeahead for reference data.

**Scope:** M. **Breaking:** yes — `x-widget: "image-upload"` migrates to
`ui:widget: "file"` with `ui:options.accept = "image/*"`. **Depends on:**
Widget Registry.

- [ ] `file` widget via the registry. Options: `accept`, `multiple`,
  `max_size`, `upload_url`, `headers`. Progress via
  `XMLHttpRequest.upload.onprogress`. Support `format: "data-url"` (base64
  inline) and `format: "binary"` (multipart upload)
- [ ] Image-upload reimplemented as a `file` preset + preview; old code
  removed, its behaviour covered by ui-options (also fixes today's
  "top-level properties only" limitation)
- [ ] `autocomplete` typeahead widget: `data_source_url`, `query_param`
  (default `q`), `value_field`, `label_field`, `min_chars`, `debounce_ms`
  (debounce shared with async validation)
- [ ] No JSON Schema changes — `enum` stays empty, options are fetched at
  runtime

**Files:** `src/formosh/widgets/file.gleam`,
`src/formosh/widgets/autocomplete.gleam`, `src/formosh/ffi/upload_ffi.mjs`
(XHR with progress); delete `src/formosh/fields/image_field.gleam` and
migrate the example.

**Acceptance:** file upload works at any depth (inside array/object);
typeahead demo searching a city out of a 10k-record list via
`/api/cities?q=...`.

---

## Theming pack (Tailwind)

**Goal.** "Looks good out of the box" without writing CSS from scratch.

**Scope:** M. **Breaking:** no.

- [ ] Separate hex package `formosh_theme_tailwind` (keep CSS out of core)
- [ ] Ready-made CSS (or a Tailwind preset) covering every `::part()` name
- [ ] Docs: "connect a theme in 3 lines"
- [ ] Later: Bootstrap / DaisyUI packs (community-driven)

**Acceptance:** one `import` + one `<link>` — the form looks
production-ready with no manual CSS.

---

## i18n

**Goal.** Translated labels and error messages.

**Scope:** S. **Breaking:** no.

- [ ] `formosh.with_locale("ru")` — switches the built-in error dictionary
- [ ] `formosh.with_messages(dict)` — custom overrides
- [ ] `errorMessage` keyword (Ajv extension): put
  `{ "errorMessage": { "minLength": "Too short" } }` right in the schema
- [ ] Locales in the repo: en (default), ru; others via community PRs

**Files:** `src/formosh/i18n/locales.gleam` (new); route
`validation/error.gleam` messages through the dictionary.

**Acceptance:** all built-in errors translate with one line of config;
`errorMessage` from the schema overrides the default.

---

## Cross-cutting tasks (not separate releases)

- [ ] **JSON Schema Test Suite** — wire the official suite in as a
  submodule, run the "structural validation" part in CI. Instantly shows
  which keywords are really supported.
- [ ] **Accessibility audit** — run axe-core over every widget, add ARIA.
  Best done together with the registry rewrite (widgets are being touched
  anyway).
- [ ] **Performance benchmarks** — a `bench/` folder measuring render time
  on 100/500/1000-field forms. Needed before Expressions land (they add
  recomputation — a baseline is required).
- [ ] **CHANGELOG.md and SemVer** — overdue. Every breaking change gets a
  major bump.
- [ ] **Publish to Hex** — installation currently requires a path/git
  dependency; publish once the API stabilizes enough for outside users.

---

## Non-goals (and why)

- **Visual form builder** à la SurveyJS Creator — a separate product an
  order of magnitude bigger than the core. If ever, as a separate
  `formosh-builder` project.
- **OpenAPI integration** — users convert OpenAPI → JSON Schema with
  external tools; not a priority for us.
- **Markdown rich-text widget, signature pad, geo-picker** — left to the
  community via the widget registry (that's what it's for).
- **Server-side rendering** — Lustre supports it; if demand appears, a
  separate iteration, not part of this roadmap.

---

## Critical path

**UI Schema (done) → Widget Registry** is the mandatory pair — everything
else leans on it. Doing one without the other means Expressions would later
have no way to pass UI Schema values into custom widgets, forcing a second
API break.

After that, two independent tracks that can run in parallel:

- **"Standards" track:** JSON Schema gap-closing → i18n.
- **"UX" track:** Layouts → Wizard → Expressions.

Async validation and file upload are self-contained — slot them in whenever
convenient.
