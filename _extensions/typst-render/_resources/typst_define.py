"""Pass Python values into Typst code cells of the document.

Emits a <script type="typst-define"> payload that the typst-render Lua filter
ingests and converts into a `#let typst_define = (...)` binding available in
every `{typst}` code block from that point onward.
"""


def typst_define(**kwargs):
    import json
    from IPython.display import display, HTML

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

    payload = {
        "contents": [
            {"name": k, "value": _convert(v)} for k, v in kwargs.items()
        ]
    }
    payload_str = json.dumps(payload).replace("</", "<\\/")
    display(HTML(f'<script type="typst-define">{payload_str}</script>'))
