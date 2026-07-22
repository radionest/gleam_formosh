// Root-level shim for the CDN bundle entry point.
//
// `npm run build` invokes `lustre/dev build app --entry=cdn`, which assumes
// the entry module lives at `src/<entry>.gleam` (compiling to
// `build/dev/javascript/formosh/cdn.mjs`). The real implementation lives at
// `formosh/cdn.gleam` (src/formosh/cdn.gleam) for proper Gleam namespacing
// (see f932498) — this shim just forwards to it so the bundler's file-layout
// assumption is satisfied without re-introducing unnamespaced modules.
import formosh/cdn

pub fn main() {
  cdn.main()
}
