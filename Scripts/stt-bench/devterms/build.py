"""Developer-terms eval audio.

Each speaker is a folder under data/devterms/<speaker>/ holding <sentence-id>.wav files.
  synthetic-<voice>  generated here with macOS `say`
  <your-name>        recorded with `bench.sh record-devterms <your-name>`

Usage: python -m devterms.build synth [VOICE...]
"""
import json
import pathlib
import subprocess
import sys

import soundfile as sf

import workspace as ws

SENTENCES = pathlib.Path(__file__).with_name("sentences.json")
ROOT = ws.DATA / "devterms"
VOICES = ["Samantha", "Daniel", "Karen", "Moira", "Rishi", "Tessa"]


def sentences():
    return json.loads(SENTENCES.read_text())["sentences"]


def synth(voices):
    for voice in voices:
        folder = ROOT / f"synthetic-{voice.lower()}"
        folder.mkdir(parents=True, exist_ok=True)
        for s in sentences():
            out = folder / f"{s['id']}.wav"
            if out.exists():
                continue
            subprocess.run([
                "say", "-v", voice, "-o", str(out), "--file-format=WAVE", "--data-format=LEI16@16000",
                s.get("speak", s["text"]),
            ], check=True)
        print(f"synthetic-{voice.lower()}: {len(list(folder.glob('*.wav')))} clips", flush=True)


def manifest_sets():
    by_id = {s["id"]: s for s in sentences()}
    sets = {}
    for folder in sorted(ROOT.glob("*")) if ROOT.exists() else []:
        items = []
        for wav in sorted(folder.glob("*.wav")):
            s = by_id.get(wav.stem)
            if s is None:
                continue
            info = sf.info(wav)
            items.append({"id": s["id"], "wav": str(wav), "ref": s["text"], "terms": s["terms"], "dur": info.frames / info.samplerate})
        if items:
            sets[f"devterms-{folder.name}"] = items
    return sets


if __name__ == "__main__":
    if sys.argv[1:2] == ["synth"]:
        synth(sys.argv[2:] or VOICES)
    else:
        raise SystemExit(__doc__)
