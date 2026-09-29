"""Compare vocabulary variants across runs: term recall on dev-terms sets vs false insertions on general speech.

Usage: compare.py RUN [RUN ...]   (runs must be scored first)
"""
import json
import sys

import workspace as ws

print(f"{'run / engine':72} {'recall':>6} {'devWER':>6} {'devFP':>5} {'lsFP':>4} {'clean':>5} {'other':>5} {'user':>5}")
for run in sys.argv[1:]:
    for r in json.load(open(ws.RUNS / run / "report_data.json")):
        dev = [m for s, m in r["sets"].items() if s.startswith("devterms-")]
        if not dev:
            continue
        g = lambda s: r["sets"].get(s, {}).get("wer")
        print(f"{run + ' / ' + r['id']:72} {sum(m['termRecall'] for m in dev) / len(dev):6.1f} "
              f"{sum(m['wer'] for m in dev) / len(dev):6.2f} {sum(m.get('falseVocabHits', 0) for m in dev):5} "
              f"{sum(r['sets'].get(s, {}).get('falseVocabHits', 0) for s in ['test-clean', 'test-other']):4} "
              f"{g('test-clean')!s:>5} {g('test-other')!s:>5} {g('user')!s:>5}")
