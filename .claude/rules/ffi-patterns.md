---
globs: ["src/formosh/ffi/**"]
---

# FFI patterns

Project target is `javascript` (set in gleam.toml). All FFI is JS-only.

## File placement

- Gleam declarations: `src/formosh/ffi/<name>.gleam`
- JS implementation: `src/formosh/ffi/<name>_ffi.mjs`
- `@external` uses relative path: `@external(javascript, "./<name>_ffi.mjs", "functionName")`

## Conventions

- FFI `.mjs` files are the only `.mjs` files tracked by git (`.gitignore` has `!src/formosh/ffi/*_ffi.mjs`)
- Functions are `pub fn` with fully typed Gleam signatures
- JS exports match the camelCase name in `@external` third argument
