# Changelog

## Unreleased

### New Features

- feat: add `output-directory` and `output-filename` options to save compiled images to user-specified locations.

## 0.9.3 (2026-04-15)

### Bug Fixes

- fix: update the Typst language declaration to use curly braces ('{typst}') for CodeBlock.

## 0.9.2 (2026-04-15)

### Bug Fixes

- fix: resolve cache image paths relative to document directory for subdirectory rendering.

## 0.9.1 (2026-04-09)

### Bug Fixes

- fix: Use numeric type for `dpi` option instead of string.

## 0.9.0 (2026-03-23)

### Refactoring

- refactor: Replace monolithic `utils.lua` with focused modules (`string.lua`, `logging.lua`, `metadata.lua`, `pandoc-helpers.lua`, `html.lua`, `paths.lua`, `colour.lua`).

## 0.8.0 (2026-03-18)

- feat: add `foreground` option to set text fill colour for rendered images.
- feat: add brand/theme-aware colour support for `foreground` and `background`.
  Both options now accept Typst colour literals, CSS hex strings (auto-converted),
  `auto` (reads from `_brand.yml`), or a `{light, dark}` map for theme-aware rendering.
  HTML/Reveal.js outputs render both variants using Quarto's `.light-content`/`.dark-content` classes;
  other formats use `brand-mode` to select one variant.
- feat: add `align` option for horizontal image alignment (`left`, `center`, `right`, `default`).
- feat: support multiple preamble files via a list of strings or `.typ` paths.
- feat: surface Typst stderr in compilation error output for easier debugging.
- fix: prevent nil-defaulted options (`format`, `file`, `input`, `classes`, `label`, `align`, etc.)
  from leaking as HTML attributes on output images.
- fix: resolve table-valued colours for inline code to avoid runtime crashes with dual-mode global config.
- fix: escape image path in inline HTML image `src` attribute.
- fix: warn when global `input` option is not a YAML map.
- fix: warn when comment-pipe options appear after code instead of silently ignoring them.
- refactor: remove redundant `get_extension_config` call.
- docs: annotate global-only options in schema descriptions.

## 0.7.0 (2026-03-12)

- feat: add alt text accessibility for block and inline rendered images.
  Block images fall back to caption, then truncated source code, instead of empty alt text.
  Inline images use the Typst source code as alt text instead of a generic string.
  Users can provide explicit alt text on inline code via `` `{typst} ..`{alt="..."} ``.

## 0.6.1 (2026-03-11)

- fix: support inline Typst rendering in DOCX output with proper text-height sizing.
- fix: skip inline Typst for PowerPoint output with a warning (Pandoc limitation).
- fix: add generic `pandoc.Image` fallback for inline Typst in non-HTML formats.

## 0.6.0 (2026-03-11)

- feat: add inline Typst rendering support for `` `{typst} ...` `` expressions, compiled to images sized to match surrounding text.
- feat!: compile to image by default for Typst output (breaking change).
  The `output` option now accepts `true`, `false`, or `asis`.
  Use `output: asis` for native Typst passthrough (previously the default).

## 0.5.0 (2026-03-10)

- feat: add `root` option to set the Typst compilation root directory (`--root`).
- feat: add `font-path` option to specify additional font directories (`--font-path`).
- feat: add `input` option to pass key-value pairs to Typst via `--input` (accessible via `sys.inputs`).
- feat: add `package-path` option to specify a local Typst package directory (`--package-path`).
- feat: `font-path` now accepts a list of paths for multiple font directories.
- feat: add `cache: clean` mode to remove stale cache files after each render.
- feat: add multi-page output support with `pages` and `layout-ncol` options.
- refactor: use per-document cache subdirectories under `.quarto/typst-render/<doc-stem>/`.
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
