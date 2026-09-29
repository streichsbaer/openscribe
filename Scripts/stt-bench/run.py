"""Run engines over prepared sets, one at a time so they never share the GPU.

Usage: run.py RUN_NAME --engines e1,e2 [--sets test-clean,test-other,user,clips] [--max-clip SECONDS]

Results go to runs/RUN_NAME/results/<engine>.jsonl (one JSON object per transcription):
  engine, set, id, dur (audio seconds), sec (processing seconds), rep, load (model load seconds), text
Clips up to 150 s run three times; the report uses the median.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time

import engines
import vocabulary
import workspace as ws


def reps(set_name, item):
    return 3 if set_name == "clips" and item["dur"] <= 150 else 1


def run_cli(name, spec, sets, out, max_clip):
    """whisper-cli / parakeet-cli. Clips: one process per call, like OpenScribe. Other sets: batches of 50."""
    tmp = tempfile.mkdtemp(prefix="stt-bench-")
    prompt = vocabulary.whisper_prompt() if spec.get("vocabulary") else None

    def call(items):
        links = []
        for i, it in enumerate(items):
            link = f"{tmp}/{i}.wav"
            if os.path.lexists(link):
                os.remove(link)
            os.symlink(it["wav"], link)
            links.append(link)
        args = [str(spec["binary"]), "-m", str(spec["model"]), "-otxt"]
        args += ["-nt", "-l", "auto"] if spec["cli"] == "whisper" else ["-np"]
        if prompt:
            args += ["--prompt", prompt]
        if spec["device"] == "cpu":
            args.append("-ng")
        for link in links:
            args += ["-f", link] if spec["cli"] == "whisper" else [link]
        t = time.perf_counter()
        p = subprocess.run(args, capture_output=True, text=True)
        sec = time.perf_counter() - t
        if p.returncode != 0:
            raise SystemExit(f"{name}: exit {p.returncode}\n{p.stderr[-2000:]}")
        m = re.search(r"load time =\s+([\d.]+) ms", p.stderr)
        load = float(m.group(1)) / 1000 if m else 0.0
        texts = []
        for link in links:
            texts.append(open(f"{link}.txt").read().strip())
            os.remove(f"{link}.txt")
        return texts, sec, load

    manifest = ws.manifest()
    call(manifest["clips"][:1])  # warm-up: page cache and Metal pipeline cache
    for s in sets:
        items = manifest[s]
        if s == "clips":
            for it in [i for i in items if i["dur"] <= max_clip]:
                for r in range(reps(s, it)):
                    (text,), sec, load = call([it])
                    out.write(json.dumps({"engine": name, "set": s, "id": it["id"], "dur": it["dur"], "sec": sec, "rep": r, "load": load, "text": text}) + "\n")
        else:
            for b in range(0, len(items), 50):
                batch = items[b:b + 50]
                texts, sec, load = call(batch)
                per = (sec - load) / sum(i["dur"] for i in batch)
                for it, text in zip(batch, texts):
                    out.write(json.dumps({"engine": name, "set": s, "id": it["id"], "dur": it["dur"], "sec": per * it["dur"], "rep": 0, "load": load, "text": text}) + "\n")
        out.flush()
        print(f"{name} {s} done", flush=True)


def run_mlx(name, spec, sets, out, max_clip):
    """parakeet-mlx and mlx-whisper, model kept loaded like an in-app engine."""
    import mlx.core as mx
    import soundfile as sf
    from huggingface_hub import snapshot_download

    def read(wav):
        a, sr = sf.read(wav, dtype="float32")
        assert sr == 16000
        return a

    local = snapshot_download(spec["repo"], revision=spec["revision"], cache_dir=ws.HF_HOME / "hub")
    if name.startswith("parakeet-mlx"):
        import parakeet_mlx.parakeet as pp
        from parakeet_mlx import from_pretrained
        pp.load_audio = lambda path, sr, dtype=mx.bfloat16: mx.array(read(str(path)))  # float32, as upstream returns
        t = time.perf_counter()
        model = from_pretrained(local)
        load = time.perf_counter() - t

        def transcribe(wav):
            return model.transcribe(wav, chunk_duration=120.0, overlap_duration=15.0).text
    else:
        import mlx_whisper
        from mlx_whisper.load_models import load_model
        t = time.perf_counter()
        load_model(local)
        load = time.perf_counter() - t

        def transcribe(wav):
            return mlx_whisper.transcribe(read(wav), path_or_hf_repo=local, verbose=None)["text"]

    manifest = ws.manifest()
    transcribe(manifest["clips"][0]["wav"])  # warm-up
    for s in sets:
        for it in [i for i in manifest[s] if s != "clips" or i["dur"] <= max_clip]:
            for r in range(reps(s, it)):
                t = time.perf_counter()
                text = transcribe(it["wav"])
                sec = time.perf_counter() - t
                out.write(json.dumps({"engine": name, "set": s, "id": it["id"], "dur": it["dur"], "sec": sec, "rep": r, "load": load, "text": text.strip()}) + "\n")
        out.flush()
        print(f"{name} {s} done", flush=True)


def run_swift(name, spec, sets, out_path, max_clip):
    """FluidAudio and Apple SpeechTranscriber through the STTBench Swift harness."""
    if not ws.STTBENCH_BIN.exists():
        raise SystemExit("STTBench is not built. Run: zsh Scripts/stt-bench/bench.sh build")
    config = {
        "engine": name, "sets": sets, "manifest": str(ws.MANIFEST), "output": str(out_path), "maxClip": max_clip,
        "fluidAudioModels": str(ws.FLUIDAUDIO_MODELS),
        "revisions": ws.item("fluidaudio-models")["repos"],
        "vocabulary": vocabulary.entries() if spec.get("vocabulary") else None,
        "boost": spec.get("boost", {}),
    }
    subprocess.run([str(ws.STTBENCH_BIN), json.dumps(config)], check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run")
    ap.add_argument("--engines", required=True)
    ap.add_argument("--sets", default="test-clean,test-other,user,clips")
    ap.add_argument("--max-clip", type=float, default=1e9)
    a = ap.parse_args()
    d = ws.run_dir(a.run)
    sets = a.sets.split(",")
    for name in a.engines.split(","):
        spec = engines.ENGINES[name]
        out_path = d / "results" / f"{name}.jsonl"
        print(f"== {name}", flush=True)
        if spec["runner"] == "swift":
            run_swift(name, spec, sets, out_path, a.max_clip)
        else:
            with open(out_path, "a") as out:
                {"cli": run_cli, "mlx": run_mlx}[spec["runner"]](name, spec, sets, out, a.max_clip)
    meta = d / "run.json"
    info = json.loads(meta.read_text()) if meta.exists() else {"created": time.strftime("%Y-%m-%d %H:%M"), "argv": []}
    info["argv"].append(sys.argv[1:])
    info["openscribeApp"] = engines.app_version()
    meta.write_text(json.dumps(info, indent=1))


if __name__ == "__main__":
    main()
