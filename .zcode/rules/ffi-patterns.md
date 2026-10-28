---
paths:
  - "src/formosh/ffi/**"
  - "demo/src/**"
---

# FFI patterns

Project target is `javascript` (set in gleam.toml). All FFI is JS-only.

## File placement

- Gleam declarations: `<name>.gleam`
- JS implementation: `<name>_ffi.mjs` — the `_ffi` suffix is mandatory, not cosmetic
- `@external` uses relative path: `@external(javascript, "./<name>_ffi.mjs", "functionName")`

The Gleam compiler rejects `foo.gleam` next to `foo.mjs` (same base name) — that's why the `_ffi` suffix exists. Drop the suffix and the build fails with a duplicate-module error.

## Where to put FFI pairs

- Library FFI: `src/formosh/ffi/`
- Demo FFI: `demo/src/`

`.gitignore` ignores all `*.mjs` except whitelisted FFI paths: `!src/formosh/ffi/*_ffi.mjs` and `!demo/src/*_ffi.mjs`. New FFI elsewhere needs an explicit whitelist line, otherwise the `.mjs` is silently skipped by `git add`.

## Conventions

- Functions are `pub fn` with fully typed Gleam signatures
- JS exports match the camelCase name in `@external` third argument
