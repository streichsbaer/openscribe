"""Prepare bench audio and data/manifest.json.

Sets:
  test-clean, test-other  300 random LibriSpeech utterances each (seed 1234)
  clips                   dictation-length clips of 5, 15, 30, 60, 120, 600 s from test-clean
  user                    completed OpenScribe sessions, with the stored raw transcript as reference
  devterms-*              scripted developer-terms recordings (see devterms/README.md)
"""
import glob
import json
import os
import random
import subprocess

import numpy as np
import soundfile as sf

import workspace as ws

SR = 16000
LS = ws.HOME / "downloads" / "datasets" / "librispeech" / "LibriSpeech"
RECORDINGS = os.path.expanduser("~/Library/Application Support/OpenScribe/Recordings")


def load_split(split):
    utts = []
    for tf in sorted(glob.glob(f"{LS}/{split}/*/*/*.trans.txt")):
        d = os.path.dirname(tf)
        for line in open(tf):
            uid, text = line.strip().split(" ", 1)
            utts.append({"id": uid, "flac": f"{d}/{uid}.flac", "ref": text})
    return utts


def write(folder, name, audio, ref):
    out = ws.DATA / folder / f"{name}.wav"
    out.parent.mkdir(parents=True, exist_ok=True)
    sf.write(out, audio, SR, subtype="PCM_16")
    return {"id": name, "wav": str(out), "ref": ref, "dur": len(audio) / SR}


def librispeech(rng):
    sets = {}
    for split in ["test-clean", "test-other"]:
        pick = sorted(rng.sample(load_split(split), 300), key=lambda u: u["id"])
        items = []
        for u in pick:
            a, sr = sf.read(u["flac"], dtype="float32")
            assert sr == SR
            items.append(write("librispeech", u["id"], a, u["ref"]))
        sets[split] = items
    return sets


def clips():
    clean = load_split("test-clean")
    durs = {u["id"]: sf.info(u["flac"]).duration for u in clean}
    items = []
    for target in [5, 15, 30]:
        u = min(clean, key=lambda u: abs(durs[u["id"]] - target))
        a, _ = sf.read(u["flac"], dtype="float32")
        items.append(write("clips", f"clip_{target}s", a, u["ref"]))
    gap = np.zeros(int(0.3 * SR), dtype=np.float32)
    for target in [60, 120, 600]:
        parts, refs, total = [], [], 0.0
        for u in clean[500:]:
            a, _ = sf.read(u["flac"], dtype="float32")
            parts += [a, gap]
            refs.append(u["ref"])
            total += len(a) / SR + 0.3
            if total >= target:
                break
        items.append(write("clips", f"clip_{target}s", np.concatenate(parts), " ".join(refs)))
    return items


def user_sessions():
    items = []
    for sj in sorted(glob.glob(f"{RECORDINGS}/*/*/session.json")):
        s = json.load(open(sj))
        d = os.path.dirname(sj)
        raw = os.path.join(d, "raw.txt")
        if s.get("state") != "completed" or not os.path.exists(raw):
            continue
        ref = open(raw).read().strip()
        if not ref:
            continue
        out = ws.DATA / "user" / f"{s['sessionId']}.wav"
        out.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", f"{d}/audio.m4a", str(out)], check=True)
        info = sf.info(out)
        items.append({
            "id": s["sessionId"], "wav": str(out), "ref": ref, "dur": info.frames / info.samplerate,
            "refSource": f"{s.get('sttProvider')}/{s.get('sttModel')}",
        })
    return items


def devterms():
    """Scripted developer-terms sets: one per speaker folder under data/devterms/<speaker>/."""
    import devterms.build as dt
    return dt.manifest_sets()


if __name__ == "__main__":
    rng = random.Random(1234)
    manifest = {}
    manifest.update(librispeech(rng))
    manifest["clips"] = clips()
    manifest["user"] = user_sessions()
    manifest.update(devterms())
    ws.DATA.mkdir(parents=True, exist_ok=True)
    ws.MANIFEST.write_text(json.dumps(manifest, indent=1))
    for k, v in manifest.items():
        print(f"{k:22} {len(v):4} items {sum(i['dur'] for i in v):8.1f} s")
