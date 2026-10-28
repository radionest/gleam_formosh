# Internals

Business logic for developers working *on* Formosh (not just using it).
Read [Architecture](../concepts/architecture.md) first for the module map;
these pages go one level deeper.

* [Model](model.md) — the `FormModel` record, path addressing, the value tree.
* [Update](update.md) — `Msg` handling: the field-edit pipeline, array invariants, union branch switching, the submit flow.
* [Parser](parser.md) — schema parse pipeline: `$ref`, `allOf`, `anyOf` normalization, unsatisfiable-constraint rejection.
* [Visibility](visibility.md) — runtime resolution: conditionals, union branches, and the hidden-path submit gate.
