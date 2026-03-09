# Changelog

## Unreleased

### New Features

- feat: adopt Quarto "/" path convention for project-root-relative file paths (#13).

### Refactoring

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
