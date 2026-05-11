#' Register a passthrough knitr engine for `{typst}` code blocks.
#'
#' Without this, knitr emits "Unknown language engine 'typst'" warnings and
#' wraps the block in a cell-output div with a `typst` (singular) class. The
#' engine simply re-emits the chunk source as a `` ```{typst} `` fenced block
#' so pandoc sees the literal `{typst}` class that the typst-render filter
#' expects.
if (requireNamespace("knitr", quietly = TRUE)) {
  knitr::knit_engines$set(typst = function(options) {
    code <- paste(options[["code"]], collapse = "\n")
    knitr::asis_output(paste0("\n```{typst}\n", code, "\n```\n"))
  })
}

#' Pass R values into Typst code cells of the document.
#'
#' Emits a `<script type="typst-define">` payload that the typst-render Lua
#' filter ingests and converts into a `#let typst_define = (...)` binding
#' available in every `{typst}` code block from that point onward.
#'
#' @param ... Named or positional values.
#'   Unnamed positional values use the deparsed expression as the key.
#' @return A `knitr::asis_output` object; visible only as a side effect when
#'   placed in a knitr chunk.
typst_define <- function(...) {
  quos <- rlang::enquos(...)
  vars <- rlang::list2(...)
  passed_names <- names(vars)
  if (is.null(passed_names)) passed_names <- rep("", length(vars))
  inferred <- vapply(quos, rlang::as_label, character(1))
  nm <- ifelse(nzchar(passed_names), passed_names, inferred)
  contents <- jsonlite::toJSON(
    list(contents = mapply(
      function(name, value) list(name = name, value = value),
      nm, vars,
      SIMPLIFY = FALSE, USE.NAMES = FALSE
    )),
    dataframe = "columns",
    null = "null",
    na = "null",
    auto_unbox = TRUE,
    digits = NA
  )
  contents <- gsub("</", "<\\/", contents, fixed = TRUE)
  knitr::asis_output(paste0(
    '<script type="typst-define">', contents, "</script>"
  ))
}
