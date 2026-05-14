---
paths:
  - "src/formosh/form/**/*.gleam"
  - "src/formosh/fields/**/*.gleam"
  - "src/formosh/validation/**/*.gleam"
---

# Error rendering pipeline

```
validator (src/formosh/validation/**)
   │   produces List(ValidationError) per field
   ▼
model.errors : Dict(String, List(ValidationError))
   │   key = path.to_string(field_path)  (canonical, see path_format.gleam)
   │   mutated only via model.{add_error, clear_errors_at_path}
   ▼
model.touched_fields : List(FieldPath)
   │   gate: errors stay hidden until the field is touched.
   │   set by model.mark_field_touched/2 — called from update.gleam on
   │   field change/blur, and bulk-set on submit.
   ▼
view → each *_field.gleam → render_field_errors(model, field_path)
       must consult both is_field_touched AND get_errors_at_path
```

## Rules

- Key into `model.errors` only via `path.to_string(field_path)` — never
  hand-build the dot-notation string. Canonical format lives in
  `formosh/path_format.gleam`.
- Never display errors without first checking
  `model.is_field_touched(field_path)`. Use `field_common.render_field_errors`
  which already handles the gate.
- Add/clear errors via `model.{add_error, clear_errors_at_path}`,
  not by rebuilding the Dict manually — `is_valid` is derived from dict size.
- `mark_field_touched` lives in `update.gleam`, not in field renderers —
  views are pure and must not mutate touched state.
