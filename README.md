# Typst Render Extension For Quarto

A Quarto filter extension that compiles ` ```{typst} ` code blocks and inline `` `{typst} ...` `` expressions to images (PNG, SVG, or PDF) using the Typst binary bundled with Quarto.

This makes Typst diagrams, figures, tables, and equations usable across all output formats (HTML, PDF via LaTeX, DOCX, RevealJS, and more).

By default, blocks are compiled to images for all output formats, including Typst.
Use `output: asis` for native passthrough when the output format is Typst.

## Installation

```bash
quarto add mcanouil/quarto-typst-render@0.20.0
```

This will install the extension under the `_extensions` subdirectory.

If you are using version control, you will want to check in this directory.

## Documentation

The full documentation lives at <https://m.canouil.dev/quarto-typst-render/>: every global and per-block option, inline expressions, cross-referencing, multi-page output, and figures compiled by the extension itself.

[`example.qmd`](example.qmd) is a short, standalone starting point you can copy, rendered to every supported format and attached to each release.

## Licence

[MIT](https://github.com/mcanouil/quarto-typst-render?tab=MIT-1-ov-file#readme).
