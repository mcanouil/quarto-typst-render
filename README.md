# Typst Render Extension For Quarto

A Quarto filter extension that compiles ` ```{typst} ` code blocks and inline `` `{typst} ...` `` expressions to images (PNG, SVG, or PDF) using the Typst binary bundled with Quarto.
This makes Typst diagrams, figures, tables, and equations usable across all output formats (HTML, PDF via LaTeX, DOCX, RevealJS, and more).

By default, blocks are compiled to images for all output formats, including Typst.
Use `output: asis` for native passthrough when the output format is Typst.

## Installation

```bash
quarto add mcanouil/quarto-typst-render@0.5.0
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

### Inline Expressions

Render Typst expressions inline using backtick code with the `typst` class.
The rendered image scales to match the surrounding text size.

```markdown
Here is a red word `{typst} #text(red)[hello]` in the middle of a sentence.

Inline maths: `{typst} $ x^2 + y^2 = z^2 $` renders as a formula image.
```

Global options (`format`, `dpi`, `preamble`, `background`, `output`) apply to inline expressions.
Block-only options (`echo`, `eval`, `label`, `cap`, `alt`, `file`, `pages`, `layout-ncol`, `output-location`) are not available for inline expressions.

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

### Multi-Page Output

When Typst produces multiple pages (e.g., using `#pagebreak()`), all pages are included by default.
Use `pages` to select specific pages and `layout-ncol` to arrange them in columns.

````markdown
```{typst}
//| layout-ncol: 2
//| width: 8cm
//| height: 6cm
#align(center + horizon)[*Page 1*]
#pagebreak()
#align(center + horizon)[*Page 2*]
```
````

Select specific pages with `pages`:

````markdown
```{typst}
//| pages: 1
//| width: 8cm
//| height: 6cm
#align(center + horizon)[*Shown*]
#pagebreak()
#align(center + horizon)[*Hidden*]
```
````

### Engine-Generated Blocks

R, Python, or Julia cells with `output: asis` can output ` ```{typst} ` blocks.
The filter processes these after engine execution.

## Configuration

Configure the filter globally in your document YAML.
Most options can be set globally and overridden per block using comment+pipe syntax (`//| key: value`).
See [Global-Only Options](#global-only-options) for options that cannot be overridden per block.

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

Input variables (accessible via `sys.inputs` in Typst code):

```yaml
extensions:
  typst-render:
    input:
      theme: dark
      lang: en
```

Cache cleanup removes stale files from previous renders:

```yaml
extensions:
  typst-render:
    cache: clean
```

Per-block input override using comma-separated syntax:

````markdown
```{typst}
//| input: theme=light,lang=fr
#sys.inputs.at("theme")
```
````

### Options

| Option            | Type            | Default   | Description                                                                       |
| ----------------- | --------------- | --------- | --------------------------------------------------------------------------------- |
| `format`          | string          | (auto)    | Image format: `png`, `svg`, `pdf`.                                                |
| `dpi`             | string          | `"144"`   | Pixels per inch (PNG only).                                                       |
| `width`           | string          | `"auto"`  | Page width for image compilation (ignored with `output: asis`).                   |
| `height`          | string          | `"auto"`  | Page height for image compilation (ignored with `output: asis`).                  |
| `margin`          | string          | `"0.5em"` | Page margin for image compilation; block `inset` with `output: asis`.             |
| `background`      | string          | `"none"`  | Page fill for image compilation; block `fill` with `output: asis`.                |
| `preamble`        | string          | `""`      | Typst code or path to a `.typ` file prepended before user code.                   |
| `cache`           | boolean\|string | `true`    | Cache compiled images. Use `"clean"` to also remove stale cache files.            |
| `input`           | object          | (none)    | Key-value pairs passed as `--input` flags to Typst CLI.                           |
| `file`            | string          | (none)    | Path to external `.typ` file to render.                                           |
| `echo`            | boolean\|string | `false`   | Show Typst source code alongside output (`true`, `false`, `fenced`).              |
| `eval`            | boolean         | `true`    | Compile Typst code to image.                                                      |
| `include`         | boolean         | `true`    | Include block in output. Set `false` to suppress entirely.                        |
| `output`          | boolean\|string | `true`    | Show rendered output. Use `asis` for native Typst passthrough.                    |
| `output-location` | string          | (none)    | Output placement in Reveal.js (`fragment`, `slide`, `column`, `column-fragment`). |
| `classes`         | string          | (none)    | Space-separated CSS classes on the output image (e.g., `r-stretch`).              |
| `pages`           | string          | `"all"`   | Pages to include from multi-page output: `all`, `1`, `1-3`, `2,5`, `3-`.          |
| `layout-ncol`     | string          | (none)    | Number of columns for arranging multi-page output. Omit for vertical stack.       |

Any unknown option with a string value is forwarded as an HTML attribute on the output image element (e.g., `//| style: "max-height: 300px;"`).
Values that look like booleans (`true`/`false`) must be quoted to be forwarded (e.g., `//| data-lazy: "true"`).

### Global-Only Options

These options can only be set in the document YAML and cannot be overridden per block.

| Option         | Type          | Default             | Description                                                           |
| -------------- | ------------- | ------------------- | --------------------------------------------------------------------- |
| `root`         | string        | (project directory) | Root directory for Typst compilation.                                 |
| `font-path`    | string\|array | (none)              | Path or list of paths to directories containing additional fonts.     |
| `package-path` | string        | (none)              | Path to a directory containing Typst packages (offline/reproducible). |

### Per-Block Cross-Referencing Options

| Option         | Type   | Description                                                                      |
| -------------- | ------ | -------------------------------------------------------------------------------- |
| `label`        | string | Quarto cross-ref label (e.g., `fig-x`, `tbl-y`, `lst-z`).                        |
| `cap`          | string | Caption text for the labelled block.                                             |
| `alt`          | string | Alternative text for accessibility.                                              |
| `<prefix>-cap` | string | Prefix-specific caption (e.g., `fig-cap`). Overrides `cap` for matching labels.  |
| `<prefix>-alt` | string | Prefix-specific alt text (e.g., `fig-alt`). Overrides `alt` for matching labels. |

### Auto-Selected Image Format

| Output Format   | Default Image Format |
| --------------- | -------------------- |
| HTML / RevealJS | `svg`                |
| LaTeX / Beamer  | `pdf`                |
| Typst           | `png`                |
| DOCX / PPTX     | `png`                |
| Other           | `png`                |

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
- `output: asis` uses native passthrough for Typst output; behaves as `true` for other formats.

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
