# Typst Render Extension For Quarto

A Quarto filter extension that compiles ` ```{typst} ` code blocks to images (PNG, SVG, or PDF) using the Typst binary bundled with Quarto.
This makes Typst diagrams, figures, tables, and equations usable across all output formats (HTML, PDF via LaTeX, DOCX, RevealJS, and more).

When the output format is Typst, blocks pass through natively without image conversion.

## Installation

```bash
quarto add mcanouil/quarto-typst-render@0.3.0
```

This will install the extension under the `_extensions` subdirectory.

If you are using version control, you will want to check in this directory.

## Usage

To use the extension, add the following to your document's front matter:

```yaml
filters:
  - typst-render
```

For cross-referencing support, use timing control:

```yaml
filters:
  - path: typst-render
    at: pre-quarto
```

Then write Typst code blocks in your document:

````markdown
```{typst}
#set text(size: 16pt)
Hello from *Typst*!
```
````

### Per-Block Options

Use comment+pipe syntax (`//| key: value`) at the top of the code block:

````markdown
```{typst}
//| width: 10cm
//| dpi: 288
//| format: png
#align(center)[A custom-sized block.]
```
````

### Cross-Referencing

Use `//| label:` and `//| cap:` for Quarto cross-references.
Generic `cap` and `alt` options work with any label prefix.
Prefix-specific variants (e.g., `fig-cap`, `tbl-alt`) override the generic options when the label matches.
Any Quarto cross-reference type is supported (`fig-`, `tbl-`, `lst-`, etc.), including custom types defined under `crossref.custom` in the document YAML.

````markdown
```{typst}
//| label: fig-my-diagram
//| cap: "A captioned Typst figure."
//| alt: "Description for screen readers."
#circle(radius: 1cm, fill: blue)
```

See @fig-my-diagram for the rendered figure.
````

### Echo and Eval Control

Show source code alongside the rendered output, or display source only:

````markdown
```{typst}
//| echo: true
$ E = m c^2 $
```

```{typst}
//| echo: fenced
$ E = m c^2 $
```

```{typst}
//| eval: false
//| echo: true
This code is shown but not compiled.
```
````

Use `echo: fenced` to display source code wrapped in fenced code block markers (` ```{typst} `), including any comment+pipe options (except `echo` itself).
This mirrors Quarto's native `echo: fenced` behaviour for computational cells.

### External File Rendering

Render an external `.typ` file instead of inline code:

````markdown
```{typst}
//| file: path/to/file.typ
```
````

### Engine-Generated Blocks

R, Python, or Julia cells with `output: asis` can output ` ```{typst} ` blocks.
The filter processes these after engine execution.

## Configuration

Configure the filter globally in your document YAML.
All options can be set globally and overridden per block using comment+pipe syntax (`//| key: value`).

Inline preamble:

```yaml
extensions:
  typst-render:
    dpi: "288"
    margin: "1em"
    preamble: '#set text(font: "Libertinus Serif")'
```

File-based preamble (any value ending in `.typ` is read as a file):

```yaml
extensions:
  typst-render:
    preamble: "preamble.typ"
```

### Options

| Option            | Type            | Default   | Description                                                          |
| ----------------- | --------------- | --------- | -------------------------------------------------------------------- |
| `format`          | string          | (auto)    | Image format: `png`, `svg`, `pdf`.                                   |
| `dpi`             | string          | `"144"`   | Pixels per inch (PNG only).                                          |
| `width`           | string          | `"auto"`  | Page width for image compilation (ignored in Typst output).          |
| `height`          | string          | `"auto"`  | Page height for image compilation (ignored in Typst output).         |
| `margin`          | string          | `"0.5em"` | Page margin for image compilation; block `inset` in Typst output.    |
| `background`      | string          | `"none"`  | Page fill for image compilation; block `fill` in Typst output.       |
| `preamble`        | string          | `""`      | Typst code or path to a `.typ` file prepended before user code.      |
| `cache`           | boolean         | `true`    | Cache compiled images.                                               |
| `file`            | string          | (none)    | Path to external `.typ` file to render.                              |
| `echo`            | boolean\|string | `false`   | Show Typst source code alongside output (`true`, `false`, `fenced`). |
| `eval`            | boolean         | `true`    | Compile Typst code to image.                                         |
| `include`         | boolean         | `true`    | Include block in output. Set `false` to suppress entirely.           |
| `output`          | boolean         | `true`    | Show rendered output. Set `false` to skip compilation.               |
| `output-location` | string          | (none)    | Output placement in Reveal.js (`fragment`, `slide`, `column`, `column-fragment`). |
| `classes`         | string          | (none)    | Space-separated CSS classes on the output image (e.g., `r-stretch`). |

Any unknown option with a string value is forwarded as an HTML attribute on the output image element (e.g., `//| style: "max-height: 300px;"`).
Values that look like booleans (`true`/`false`) must be quoted to be forwarded (e.g., `//| data-lazy: "true"`).

### Per-Block Cross-Referencing Options

| Option         | Type   | Description                                                                      |
| -------------- | ------ | -------------------------------------------------------------------------------- |
| `label`        | string | Quarto cross-ref label (e.g., `fig-x`, `tbl-y`, `lst-z`).                        |
| `cap`          | string | Caption text for the labelled block.                                             |
| `alt`          | string | Alternative text for accessibility.                                              |
| `<prefix>-cap` | string | Prefix-specific caption (e.g., `fig-cap`). Overrides `cap` for matching labels.  |
| `<prefix>-alt` | string | Prefix-specific alt text (e.g., `fig-alt`). Overrides `alt` for matching labels. |

### Auto-Selected Image Format

| Output Format   | Default Image Format  |
| --------------- | --------------------- |
| HTML / RevealJS | `svg`                 |
| LaTeX / Beamer  | `pdf`                 |
| Typst           | (native pass-through) |
| DOCX / PPTX     | `png`                 |
| Other           | `png`                 |

### Echo/Eval Behaviour

| `eval`  | `echo`   | Result                                           |
| ------- | -------- | ------------------------------------------------ |
| `true`  | `false`  | Image only (default).                            |
| `true`  | `true`   | Source code block + image below.                 |
| `true`  | `fenced` | Fenced source code block (with markers) + image. |
| `false` | `true`   | Source code listing only.                        |
| `false` | `fenced` | Fenced source code listing only (with markers).  |
| `false` | `false`  | Nothing rendered (hidden block).                 |

The `include` and `output` options take precedence over the eval/echo matrix:

- `include: false` hides the entire block regardless of eval/echo settings.
- `output: false` skips compilation and shows only the source code (if echo is enabled).

## Example

Here is the source code for a minimal example: [`example.qmd`](example.qmd).

Output of `example.qmd`:

- [HTML](https://m.canouil.dev/quarto-typst-render/).
- [Typst](https://m.canouil.dev/quarto-typst-render/example-typst.pdf).
- [PDF (XeLaTeX)](https://m.canouil.dev/quarto-typst-render/example-xelatex.pdf).
- [PDF (LuaLaTeX)](https://m.canouil.dev/quarto-typst-render/example-lualatex.pdf).
- [PDF (PDFLaTeX)](https://m.canouil.dev/quarto-typst-render/example-pdflatex.pdf).
- [RevealJS](https://m.canouil.dev/quarto-typst-render/example-revealjs.html).
- [Beamer](https://m.canouil.dev/quarto-typst-render/example-beamer.pdf).
- [DOCX](https://m.canouil.dev/quarto-typst-render/example-docx.docx).
- [PPTX](https://m.canouil.dev/quarto-typst-render/example-pptx.pptx).
