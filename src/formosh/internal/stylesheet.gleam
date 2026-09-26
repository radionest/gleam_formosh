//// The library's own stylesheet: the defaults a feature cannot work
//// without, in the lowest-priority cascade layer of the component.
////
//// `form/view.gleam` renders it once per form, as the first child of
//// `formosh-container`. Inside a shadow root it precedes every adopted page
//// stylesheet, so any consumer rule — unlayered or in an adopted layer, at
//// any specificity — overrides these defaults without `!important`. In a
//// plain Lustre app it is a page stylesheet placed after the page's own, so
//// a page that declares cascade layers must declare `formosh` first
//// (`@layer formosh, …;`). Every selector sits in `:where()`, so nothing
//// here competes by specificity either.
////
//// Inline `style` is reserved for runtime state the component's own logic
//// depends on (the swipe widget's drag offset and fly-off). A default with
//// a sensible alternative belongs here.

import lustre/element.{type Element}
import lustre/element/html

// Unquoted attribute values keep this string free of escapes. Never write an
// exact-match `[part="…"]` here: render tests detect elements by the literal
// `part="…"` string, and this text is part of every full-form render.
// Every selector is scoped to `.formosh-container`: in a plain Lustre app this
// `<style>` is a page stylesheet, and Lustre copies page stylesheets into every
// other component's shadow root, so a bare `[part~=row]` would style any
// element on the page that uses the same part name.
const css = "@layer formosh {
  :where(.formosh-container [part~=row]) {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, var(--formosh-row-min, 12rem)), 1fr));
    gap: var(--formosh-row-gap, 1rem);
  }
  :where(.formosh-container [part~=row] > *) {
    min-width: 0;
  }
  :where(.formosh-container [part~=array-item-body]) {
    display: grid;
    grid-template-rows: 1fr;
    overflow: hidden;
    transition: grid-template-rows var(--formosh-collapse-duration, 180ms) ease;
  }
  :where(.formosh-container [part~=array-item][data-collapsed] > [part~=array-item-body]) {
    grid-template-rows: 0fr;
  }
  :where(.formosh-container [part~=array-item-body] > [part~=array-item-fields]) {
    min-height: 0;
  }
  @media (prefers-reduced-motion: reduce) {
    :where(.formosh-container [part~=array-item-body]) {
      transition-duration: 0s;
    }
  }
}"

/// The `<style>` element carrying the library stylesheet.
pub fn element() -> Element(msg) {
  html.style([], css)
}
