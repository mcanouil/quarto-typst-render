// Prepended to a block through the `preamble` option.
#let badge(body, fill: teal) = box(
  fill: fill.lighten(70%),
  radius: 4pt,
  inset: (x: 8pt, y: 5pt),
  text(size: 11pt, body),
)
