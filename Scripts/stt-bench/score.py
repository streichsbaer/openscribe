"""Score a run: WER (Whisper English normalizer, corpus level), dev-term recall, false vocabulary hits, latency.

Usage: score.py RUN_NAME   writes runs/RUN_NAME/summary.md and report_data.json
"""
import glob
import json
import re
import statistics
import sys

import jiwer
from whisper_normalizer.english import EnglishTextNormalizer

import engines
import vocabulary
import workspace as ws

norm = EnglishTextNormalizer()


def wer(pairs):
    pairs = [(norm(r), norm(h) or "<empty>") for r, h in pairs]
    pairs = [(r, h) for r, h in pairs if r.strip()]
    return round(100 * jiwer.wer([r for r, _ in pairs], [h for _, h in pairs]), 2) if pairs else None


def contains(text, term):
    return re.search(rf"(?<![\w.]){re.escape(term.lower())}(?![\w])", text.lower()) is not None


def main(run):
    d = ws.RUNS / run
    manifest = ws.manifest()
    items = {(s, it["id"]): it for s, its in manifest.items() for it in its}
    terms = [e["term"] for e in vocabulary.entries()]
    rows = {}
    for f in sorted(glob.glob(str(d / "results" / "*.jsonl"))):
        for line in open(f):
            r = json.loads(line)
            rows.setdefault(r["engine"], []).append(r)

    report = []
    for name, rs in rows.items():
        spec = engines.ENGINES.get(name, {})
        first = [r for r in rs if r["rep"] == 0 and (r["set"], r["id"]) in items]
        by_set = {}
        for r in first:
            by_set.setdefault(r["set"], []).append(r)
        entry = {k: spec.get(k) for k in ["label", "family", "runtime", "compute", "resident"]}
        entry.update({"id": name, "load": round(rs[0]["load"], 2), "sets": {}})
        for s, srs in by_set.items():
            pairs = [(items[(s, r["id"])]["ref"], r["text"]) for r in srs]
            m = {"n": len(srs), "wer": wer(pairs)}
            if s.startswith("devterms-"):
                want = [(t, r["text"]) for r in srs for t in items[(s, r["id"])].get("terms", [])]
                m["termRecall"] = round(100 * sum(contains(h, t) for t, h in want) / len(want), 1) if want else None
                m["missedTerms"] = sorted({t for t, h in want if not contains(h, t)})
            if s.startswith("devterms-") or s in ("test-clean", "test-other"):
                false_hits = []
                for r in srs:
                    ref = items[(s, r["id"])]["ref"]
                    false_hits += [t for t in terms if contains(r["text"], t) and not contains(ref, t)]
                m["falseVocabHits"] = len(false_hits)
                m["falseVocabTerms"] = sorted(set(false_hits))
            sec = sum(r["sec"] for r in srs)
            m["rtfx"] = round(sum(r["dur"] for r in srs) / sec, 1) if sec else None
            entry["sets"][s] = m
        lat = {}
        for r in rs:
            if r["set"] == "clips":
                lat.setdefault(r["id"], []).append(r["sec"])
        entry["latency"] = {c: round(statistics.median(v), 3) for c, v in lat.items()}
        report.append(entry)

    (d / "report_data.json").write_text(json.dumps(report, indent=1))
    sets = sorted({s for e in report for s in e["sets"]}, key=lambda s: (not s.startswith("test"), s))
    lines = [f"# Run {run}", "", "WER in percent (Whisper English normalizer, corpus level). Latency in seconds, median of 3.", ""]
    lines += ["| engine | " + " | ".join(sets) + " | 5 s | 30 s | 120 s |", "|---" * (len(sets) + 4) + "|"]
    for e in sorted(report, key=lambda e: e["id"]):
        cells = []
        for s in sets:
            m = e["sets"].get(s)
            if not m:
                cells.append("")
                continue
            c = f"{m['wer']}"
            if "termRecall" in m:
                c += f" / terms {m['termRecall']}%"
            if m.get("falseVocabHits"):
                c += f" / {m['falseVocabHits']} false"
            cells.append(c)
        l = e["latency"]
        lines.append(f"| {e['id']} | " + " | ".join(cells) + f" | {l.get('clip_5s', '')} | {l.get('clip_30s', '')} | {l.get('clip_120s', '')} |")
    missed = [(e["id"], s, m["missedTerms"]) for e in report for s, m in e["sets"].items() if m.get("missedTerms")]
    if missed:
        lines += ["", "## Missed developer terms", ""]
        lines += [f"- {eid} on {s}: {', '.join(t)}" for eid, s, t in sorted(missed)]
    (d / "summary.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main(sys.argv[1])
