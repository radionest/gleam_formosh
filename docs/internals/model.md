---
type: internal
title: "Model"
description: "FormModel internals: path-based field addressing, the value tree, touched/errors/visibility state."
---

# Model (internals)

> **Stub.** Target length: ~400 words.

**Source**

- `src/formosh/form/model.gleam`
- `src/formosh/form/path.gleam`

**To document**

- The `FormModel` record: fields and what each holds.
- Path addressing — how `["address", "street"]` maps to a nested value.
  Link to `form/path.gleam`.
- Value tree representation (`Value` type: `StringValue`, `NumberValue`,
  `BoolValue`, `ObjectValue`, `ArrayValue`, `NullValue`).
- Auxiliary state: `touched` set, `errors` map, `visibility` map,
  `dirty` flag.
- Why the model is immutable and how updates return a new model.

**Cross-links**

- How paths get mutated → [Update](update.md)
- How visibility is computed → [Visibility](visibility.md)
