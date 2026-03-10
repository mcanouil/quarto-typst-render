# Changelog

## Unreleased

- feat: add `root` option to set the Typst compilation root directory (`--root`).
- feat: add `font-path` option to specify additional font directories (`--font-path`).
- feat: add `input` option to pass key-value pairs to Typst via `--input` (accessible via `sys.inputs`).
- feat: add `package-path` option to specify a local Typst package directory (`--package-path`).
- feat: `font-path` now accepts a list of paths for multiple font directories.
- feat: add `cache: clean` mode to remove stale cache files after each render.
- refactor: use stdin instead of temporary files for Typst compilation.

## 0.4.0 (2026-03-09)

- feat: add `classes` option for CSS classes on output image elements.
- feat: add `img-fluid` class by default for responsive images in HTML output.
- feat: forward unknown code-cell options as HTML attributes on the output image element.

## 0.3.0 (2026-03-09)

### New Features

- feat: add `output-location` support for Reveal.js presentations (fragment, slide, column, column-fragment).
- feat: adopt Quarto "/" path convention for project-root-relative file paths (#13).
- feat: add `include` and `output` options to control block visibility and compilation.
- feat: add prefix-aware option resolution (`cap`, `alt`, `align`) to `code-cell` module.

### Refactoring

- refactor: move cross-referencing logic (`ref_type`, `resolve_caption`, `resolve_alt`, `wrap_crossref`) to `code-cell` module.
- refactor: use `quarto.format.*` API for output format detection (#4).
- refactor: use `pandoc.path.join()` for path construction (#5).
- refactor: use `quarto.utils.string_to_inlines()` for caption parsing (#6).
- refactor: simplify `resolve_typst_bin()` by removing `pcall` wrapper (#7).
- refactor: inline format validation and remove `validation` module dependency (#8).
- refactor: use `pandoc.utils.stringify` directly (#9).
- refactor: remove unused `validation` module (#11).

## 0.2.0 (2026-03-08)

- refactor: use explicit `--format` flag for `typst compile` command.

## 0.1.0 (2026-03-08)

- feat: initialise typst-render extension.
