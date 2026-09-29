"""Workspace layout for the STT bench. Every script resolves paths through here."""
import json
import os
import pathlib

BENCH = pathlib.Path(__file__).resolve().parent
REPO = BENCH.parents[1]
HOME = pathlib.Path(os.environ.get("STT_BENCH_HOME", REPO / "artifacts" / "stt-bench")).resolve()

DOWNLOADS = HOME / "downloads"
HF_HOME = DOWNLOADS / "hf"
FLUIDAUDIO_MODELS = DOWNLOADS / "models" / "fluidaudio"
BUILD = HOME / "build"
DATA = HOME / "data"
RUNS = HOME / "runs"
MANIFEST = DATA / "manifest.json"
INVENTORY = BENCH / "inventory.json"

APP_WHISPER_CLI = pathlib.Path("/Applications/OpenScribe.app/Contents/Resources/bin/whisper-cli")
WHISPER_CPP_194_BIN = BUILD / "whisper.cpp-1.9.4" / "build" / "bin"
STTBENCH_BIN = BUILD / "swift" / "release" / "STTBench"


def inventory():
    return json.loads(INVENTORY.read_text())


def item(item_id):
    return next(i for i in inventory()["items"] if i["id"] == item_id)


def path(item_id):
    return HOME / item(item_id)["path"]


def run_dir(name):
    d = RUNS / name
    (d / "results").mkdir(parents=True, exist_ok=True)
    (d / "logs").mkdir(parents=True, exist_ok=True)
    return d


def manifest():
    return json.loads(MANIFEST.read_text())
