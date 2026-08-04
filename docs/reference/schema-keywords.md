---
type: reference
title: "Schema Keywords"
description: "Which JSON Schema (draft 2020-12) keywords Formosh parses, which it validates, and which it ignores — with source references."
---

# Schema Keywords

Formosh implements a deliberate subset of [JSON Schema draft
2020-12](https://json-schema.org/draft/2020-12/json-schema-core). This page
is the support matrix: every keyword in one of three states — **parsed and
enforced**, **parsed only** (stored on the schema but not acted on), or
**unsupported** (rejected or silently ignored at parse time).

> **Source of truth.** The matrices below are derived from
> `src/formosh/schema/validator.gleam` (what's enforced),
> `src/formosh/schema/parser.gleam` (what's parsed), and
> `src/formosh/schema/types.gleam` (what's stored). If the README and this
> page disagree, this page wins.

## Status legend

| Mark | Meaning |
|------|---------|
| ✅ | Parsed **and** enforced (validation or UI behaviour) |
| 🟡 | Parsed and stored, but **not** enforced |
| ❌ | Not parsed — silently dropped or rejected |

## Type keywords

| Keyword | Status | Notes |
|---------|--------|-------|
| `type` (`string`, `number`, `integer`, `boolean`, `array`, `object`, `null`) | ✅ | Drives widget selection ([Widget Selection](widgets.md)). `null` is accepted but renders nothing useful. |
| `enum` | ✅ | Renders as radio (≤5 options) or select (>5). **Value validated** against the allowed list (`validate_enum` in `validator.gleam`). |
| `const` | ✅ | Converted to a single-value `enum` at parse time. |

## Metadata

| Keyword | Status | Notes |
|---------|--------|-------|
| `title` | ✅ | Used as the field label; overridable via `ui:title`. |
| `description` | ✅ | Used as field help text; overridable via `ui:description` / `ui:help`. |
| `default` | ✅ | Parsed and applied during initial value hydration (`form/defaults.gleam`). |
| `readOnly` | ✅ | Field hidden by default; shown as disabled input with `with_show_readonly_fields(True)`. |

## Object structure

| Keyword | Status | Notes |
|---------|--------|-------|
| `properties` | ✅ | Order-preserving (stored as `List`, never `Dict`). |
| `required` | ✅ | Required-field validation; controls the `*` indicator and submit gating. |
| `$defs` / `definitions` | ✅ | Stored on the root; referenced via `$ref`. |
| `$ref` (`#/$defs/...`, `#/definitions/...`) | ✅ | JSON-Pointer resolved by `schema/resolver.gleam`; **circular refs are detected and rejected**. |
| `additionalProperties` | ❌ | Not parsed. |
| `patternProperties` | ❌ | Not parsed. |
| `minProperties` / `maxProperties` | ❌ | Not parsed. |
| `dependencies` / `dependentRequired` / `dependentSchemas` | ❌ | Not parsed. |
| `discriminator` | ❌ | Not parsed. |

## Array structure

| Keyword | Status | Notes |
|---------|--------|-------|
| `items` | ✅ | Object and array `items` nest to any depth, including arrays inside array items. |
| `minItems` | ✅ | Length validation + auto-creates rows up to `minItems`; hides Remove when shrinking would violate it. |
| `maxItems` | ✅ | Length validation + hides Add once reached. |
| `prefixItems` (tuple validation) | ❌ | Not parsed. |
| `uniqueItems` | ❌ | Not parsed. |
| `contains` / `minContains` / `maxContains` | ❌ | Not parsed. |

**Bounds normalization.** A schema with `minItems > maxItems`
(unsatisfiable) is normalized at parse time so `minItems` wins — the array
renders as fixed-size at `minItems` rows. Array-length violations coming
from externally supplied values are always shown (they bypass the
field-touched gate; see `render_visible` in `fields/field_dispatcher.gleam`).

## String constraints

| Keyword | Status | Notes |
|---------|--------|-------|
| `minLength` | ✅ | Enforced. Skipped for empty optional fields (clearing ≠ too-short). |
| `maxLength` | ✅ | Enforced. `> 100` also flips the widget to a textarea. |
| `format` | see below | Some formats enforced, some parse-only. |
| `pattern` | ✅ | **Enforced** via `gleam_regexp` (`regexp.check`, partial-match per draft §6.3.3). An invalid regex is logged and the check skipped — see the `pattern` branch in `validator.gleam`. |

### `format` support

| Format | Status | Renders as | Validated |
|--------|--------|-----------|-----------|
| `email` | ✅ | `<input type="email">` | checks `@` and `.` present (not RFC-compliant) |
| `url` / `uri` | ✅ | `<input type="url">` | checks `http://` / `https://` prefix |
| `date` | ✅ | `<input type="date">` — native picker | not validated |
| `time` | ✅ | `<input type="time">` — native picker | not validated |
| `password` | ✅ | `<input type="password">` — masked, regardless of `maxLength`: both the `format` and `ui:widget` routes win over the textarea threshold unconditionally (see [UiSchema § Password masking](ui-schema.md#password-masking)), and `••••••••` in review mode | not validated |
| `date-time` | 🟡 | `<input type="text">` — deliberately not wired; RFC 3339 requires an offset that `datetime-local` rejects (see [Widget Selection](widgets.md)) | not validated |
| `uuid` | 🟡 | `<input type="text">` | not validated |
| anything else | 🟡 | `<input type="text">` (`CustomFormat`) | not validated |

## Number constraints

| Keyword | Status | Notes |
|---------|--------|-------|
| `minimum` | ✅ | `value < minimum` fails. |
| `maximum` | ✅ | `value > maximum` fails. |
| `exclusiveMinimum` | ✅ | `value <= exclusiveMinimum` fails. |
| `exclusiveMaximum` | ✅ | `value >= exclusiveMaximum` fails. |
| `multipleOf` | ✅ | **Tolerant** comparison: quotients within `1e-8` of an integer pass, mirroring Ajv's `multipleOfPrecision: 8`. Non-positive `multipleOf` (spec violation) is skipped as a schema bug. Also drives the input `step` attribute. |

## Composition

| Keyword | Status | Notes |
|---------|--------|-------|
| `allOf` | ✅ | Deep-merged into the parent node at parse time by `schema/composer.gleam`: properties, required (union), bounds (stricter-wins), conditionals (appended). Scalar keywords (`title`, `default`, `enum`, `oneOf`, `pattern`, `format`, `multipleOf`) take the **later** member's value wholesale — enum/oneOf are overridden, not intersected. Conflicting types or crossed bounds in the merged result fail parsing with `UnsatisfiableSchema`. |
| `oneOf` (with `const` + `title` options) | ✅ | Renders as a radio group of named constant options. |
| `oneOf` (schema variants) | 🟡 | Parsed and stored, but not processed as polymorphic dispatch. |
| `anyOf` | ✅ | Parsed, `$ref`-resolved inside members, and normalized at parse time (`schema/composer.gleam`): null members collapse into a `nullable` flag — an empty nullable field validates as satisfied and submits `null` (see [Web Component](../guides/web-component.md#nullable-fields)); a single surviving non-null member merges into the node itself (`Optional[X]` renders as a plain `X` field); 2+ surviving members stay in `any_of` and render as a runtime branch chooser (radio ≤5 branches / select >5, `ui:widget` override — see [Widget Selection](widgets.md)). Member extraction is lenient (malformed members dropped); a parent `type` disjoint from every surviving member is a `ParseError`. A **bare** `anyOf` directly as an array's `items` schema (no object wrapper) does not render a chooser. |
| `not` | ❌ | Not parsed. |

**`allOf` round-trip caveat.** `allOf` inside a `$defs` entry does not
survive schema serialization round-trip (`$defs` stay raw source; the
serializer re-emits flattened schemas).

## Conditionals

| Keyword | Status | Notes |
|---------|--------|-------|
| `if` / `then` / `else` | ✅ | Fully dynamic — re-evaluated on every field change by `schema/conditional_resolver.gleam`. Multiple conditionals compose via `allOf`. `$ref` inside branches is resolved, so branches can pull from `$defs`. See [Visibility](../internals/visibility.md). |

## Submission

| Feature | Status |
|---------|--------|
| HTTP `POST` / `PUT` via [rsvp](https://hexdocs.pm/rsvp/) | ✅ |
| Custom submission handler | ✅ |
| No-submission (read values manually) | ✅ (default) |
| HTTP `GET` | ❌ |

## Other

| Feature | Status |
|---------|--------|
| Touch tracking (errors hidden until interaction) | ✅ |
| Conditional field visibility (`if/then/else`) | ✅ |
| Schema serialization back to JSON | ✅ |
| Cross-field validation (`with_validator`) | ✅ |
| UiSchema (`ui:widget`, `ui:order`, …) | ✅ |

## Summary of gaps worth knowing about

If Formosh silently lets something through you expected it to catch, it's
probably one of these:

1. **`email` / `url` validation is lax** — substring checks, not RFC. Always re-validate on the server.
2. **`uuid` and custom formats** are accepted but not checked.
3. **Polymorphic `oneOf`** (schema variants, as opposed to `const`+`title` options) is parsed but not rendered as a choice widget. `anyOf` does render one — see the Composition table above.
4. **No `additionalProperties` / `patternProperties`** — extra object keys are simply ignored at the data layer.
5. **No tuple validation** (`prefixItems`).
6. **`format: "date-time"` stays plain text** — `date`, `time`, and
   `password` get native/typed inputs, but `date-time` is deliberately left
   as `CustomFormat` (see the format table). Separately: `<input
   type="date">` and `<input type="time">` only accept `YYYY-MM-DD` /
   `HH:mm[:ss]` — a value outside that shape renders as an empty input with
   no console error, so normalise non-conforming timestamps before passing
   them as `initial-values`. On a **required** field this also silently
   blocks submission: the empty `<input required>` fails the browser's own
   constraint validation, while formosh's validator still sees the
   original string in `model.values` and reports the field satisfied —
   Submit stays enabled, but clicking it does nothing and formosh renders
   no error. See [Widget Selection § Data
   contract](widgets.md#html-input-type-from-format).
