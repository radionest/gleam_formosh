---
okf_version: "0.1"
name: formosh
description: "Documentation bundle for Formosh, a JSON Schema (draft 2020-12) form generator for Gleam / Lustre."
---

# Formosh — Knowledge Bundle

[Formosh](https://github.com/radionest/gleam_formosh) is a type-safe **JSON
Schema form generator** for [Gleam](https://gleam.run) /
[Lustre](https://hexdocs.pm/lustre/). Hand it a JSON Schema (draft 2020-12);
it hands you back a live, validated form built on Lustre's Model-View-Update
architecture.

**You don't need to write Gleam to use it.** Formosh ships as a Web
Component (`<formosh-form>`) with a CDN bundle, so a plain HTML + JavaScript
page can mount a fully validated form from a schema with no build step and
no Gleam toolchain. The Gleam API is there for embedding inside Lustre apps;
the Web Component is there for everything else.

This directory is an [Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md) (OKF v0.1) bundle — a folder of
markdown files with YAML frontmatter. Every concept file carries a `type` in
its frontmatter (the only key OKF strictly requires); `index.md` files carry
no concept frontmatter.

> ⚠️ **Alpha.** Formosh's API is unstable and will change. Treat these docs
> as a snapshot of the current (`0.8.x`) behaviour, not a stable contract.

## How this bundle is organized

The bundle is split into **four audiences**. Pick the one that matches what
you're trying to do:

| Audience | Question it answers | Start here |
|----------|---------------------|------------|
| **Concepts** | What *is* Formosh and how is it put together? | [Overview](concepts/overview.md) |
| **Guides** | How do I *use* it in my app? | [Quickstart](guides/quickstart.md) |
| **Reference** | What does the API / schema support look like? | [Public API](reference/api.md) |
| **Internals** | How does the engine work under the hood (for maintainers)? | [Model](internals/model.md) |

## Reading order by goal

**"I just want a form on my page."**
[Web Component](guides/web-component.md) — works from plain HTML/JS, no
Gleam required. Start here if you're not a Gleam project.

**"I want a form on my page and I do use Gleam."**
[Quickstart](guides/quickstart.md) → [Web Component](guides/web-component.md).

**"I'm embedding Formosh in a Lustre app."**
[Quickstart](guides/quickstart.md) → [Configuration](guides/configuration.md) → [Public API](reference/api.md).

**"I need to know which JSON Schema keywords work."**
[Schema Keywords](reference/schema-keywords.md) → [Widget Selection](reference/widgets.md).

**"I'm modifying Formosh itself."**
[Architecture](concepts/architecture.md) → the four [Internals](internals/index.md) pages.

## Conventions used in this bundle

- Code blocks tagged `gleam` come from (or compile against) the current
  source in `src/`. Snippets that are illustrative-only are marked.
- Cross-links between concepts use relative markdown paths so they resolve
  whether you browse on GitHub, in an OKF viewer, or locally with `cat`.
- The README at the repo root remains the canonical quick reference; this
  bundle exists to go deeper than a README can.

# Top-level indices

* [Concepts](concepts/index.md)
* [Guides](guides/index.md)
* [Reference](reference/index.md)
* [Internals](internals/index.md)
