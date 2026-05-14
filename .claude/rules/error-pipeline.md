---
paths:
  - "src/formosh/form/**/*.gleam"
  - "src/formosh/fields/**/*.gleam"
  - "src/formosh/validation/**/*.gleam"
---

# Error rendering pipeline

```
validator (src/formosh/validation/**)
   │   produces ValidationError values per field
   ▼
model.errors : Dict(String, List(ValidationError))
   │   key = path.to_string(field_path)  (canonical, see path_format.gleam)
   │   mutated only via model.{add_error_at_path, clear_errors_at_path}
   ▼
model.touched_fields : List(FieldPath)
   │   gate: errors stay hidden until the field is touched.
   │   set by model.mark_field_touched/2 — called from update.gleam on
   │   field change/blur, and bulk-set on submit.
   ▼
field_dispatcher.gleam : applies the gate
   │   `case has_errors && is_touched -> render_field_errors(errors)`
   │   (see field_dispatcher.gleam:198)
   ▼
field_common.render_field_errors(errors: List(ValidationError))
   pure formatter — receives a pre-filtered error list, no gating logic
```

## Rules

- Key into `model.errors` only via `path.to_string(field_path)` — never
  hand-build the dot-notation string. Canonical format lives in
  `formosh/path_format.gleam`.
- The touched-gate lives in `field_dispatcher.gleam`, not in
  `field_common.render_field_errors`. The latter is a pure formatter that
  trusts its caller. Never call it without first checking
  `model.is_field_touched(field_path)` and `get_errors_at_path` —
  otherwise errors leak on untouched fields.
- Add/clear errors via `model.{add_error_at_path, clear_errors_at_path}`,
  not by rebuilding the Dict manually — `is_valid` is derived from dict size.
- `mark_field_touched` lives in `update.gleam`, not in field renderers —
  views are pure and must not mutate touched state.
