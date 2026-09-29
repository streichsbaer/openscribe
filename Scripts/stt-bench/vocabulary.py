"""Read OpenScribe vocabulary files: the shipped developer list, plus an optional extra file.

Format: one term per line, optional sounds-like spellings after a colon separated by commas, # comments.
Set STT_BENCH_VOCABULARY to a file path to evaluate a different list.
"""
import os
import pathlib

import workspace as ws

BUILT_IN = ws.REPO / "Sources" / "OpenScribe" / "Resources" / "Vocabulary" / "developer-terms.txt"


def parse(text):
    entries = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        term, _, aliases = line.partition(":")
        entries.append({"term": term.strip(), "aliases": [a.strip() for a in aliases.split(",") if a.strip()]})
    return entries


def entries():
    path = pathlib.Path(os.environ.get("STT_BENCH_VOCABULARY", BUILT_IN))
    return parse(path.read_text())


def whisper_prompt(limit_chars=700):
    """Whisper reads its prompt as preceding text; a comma list of spellings biases toward them."""
    terms, used = [], 0
    for e in entries():
        if used + len(e["term"]) + 2 > limit_chars:
            break
        terms.append(e["term"])
        used += len(e["term"]) + 2
    return "Glossary: " + ", ".join(terms) + "."
