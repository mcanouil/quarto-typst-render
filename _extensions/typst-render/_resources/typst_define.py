"""Pass Python values into Typst code cells of the document.

Emits a Pandoc YAML metadata block carrying a JSON payload that the
typst-render Lua filter ingests and converts into a `#let typst_define = (...)`
binding available in every `{typst}` code block from that point onward.
"""

# Session-local accumulator. Each call updates this dict (last-write-wins on
# names, insertion order preserved per Python 3.7+) and re-emits the full
# accumulated payload as a metadata block. Pandoc merges metadata blocks at
# parse time (later same-key wins), so the final document metadata sees the
# largest accumulator state.
_typst_define_state = {}


def typst_define(**kwargs):
    import json
    from IPython.display import display, Markdown

    def _convert(v):
        try:
            import pandas as pd
            if isinstance(v, pd.DataFrame):
                return v.to_dict(orient="list")
        except ImportError:
            pass
        try:
            import polars as pl
            if isinstance(v, pl.DataFrame):
                return v.to_dict(as_series=False)
        except ImportError:
            pass
        try:
            import numpy as np
            if isinstance(v, np.ndarray):
                return v.tolist()
        except ImportError:
            pass
        return v

    for k, v in kwargs.items():
        _typst_define_state[k] = _convert(v)
    payload = {
        "contents": [
            {"name": k, "value": v} for k, v in _typst_define_state.items()
        ]
    }
    json_str = json.dumps(payload)
    # Hex-encode the JSON. Pandoc's smart-quote / dash / ellipsis transforms
    # would otherwise corrupt JSON quotes (`"` -> `“`/`”`) and any `--`/`...`
    # sequences inside string values during metadata block parsing.
    hex = json_str.encode("utf-8").hex()
    display(Markdown(f"\n---\ntypst_define: {hex}\n---\n"))
