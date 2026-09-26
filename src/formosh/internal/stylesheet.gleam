/// The library's own stylesheet: the defaults a feature cannot work
/// without, in the lowest-priority cascade layer of the component.
///
/// `form/view.gleam` renders it once per form, as the first child of
/// `formosh-container`. Inside a shadow root it precedes every adopted page
/// stylesheet, so `formosh` is the first-declared layer and any consumer
/// rule — unlayered or in a later layer, at any specificity — overrides
/// these defaults without `!important`. Every selector sits in `:where()`,
/// so nothing here competes by specificity either.
///
/// Inline `style` is reserved for runtime state the component's own logic
/// depends on (the swipe widget's drag offset and fly-off). A default with
/// a sensible alternative belongs here.
import lustre/element.{type Element}
import lustre/element/html

// Unquoted attribute values keep this string free of escapes. Never write an
// exact-match `[part="…"]` here: render tests detect elements by the literal
// `part="…"` string, and this text is part of every full-form render.
const css = "@layer formosh {
  :where([part~=row]) {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, var(--formosh-row-min, 12rem)), 1fr));
    gap: var(--formosh-row-gap, 1rem);
  }
  :where([part~=row] > *) {
    min-width: 0;
  }
  :where([part~=array-item-body]) {
    display: grid;
    grid-template-rows: 1fr;
    overflow: hidden;
    transition: grid-template-rows var(--formosh-collapse-duration, 180ms) ease;
  }
  :where([part~=array-item][data-collapsed] > [part~=array-item-body]) {
    grid-template-rows: 0fr;
  }
  :where([part~=array-item-body] > [part~=array-item-fields]) {
    min-height: 0;
  }
  @media (prefers-reduced-motion: reduce) {
    :where([part~=array-item-body]) {
      transition-duration: 0s;
    }
  }
}"

/// The `<style>` element carrying the library stylesheet.
pub fn element() -> Element(msg) {
  html.style([], css)
}
