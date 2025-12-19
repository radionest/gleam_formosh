// CDN entry point for Formosh
// This module is used as the entry point for CDN builds.
// It auto-registers the Web Component and exposes the API.

import component
import gleam/io

/// Main function called when the bundle is loaded.
/// Automatically registers the formosh-form Web Component.
pub fn main() {
  case component.register() {
    Ok(_) -> {
      io.println("Formosh: Web Component <formosh-form> registered successfully")
    }
    Error(_) -> {
      io.println("Formosh: Failed to register Web Component")
    }
  }
}
