"""Engine registry. Each entry names a runner and the metadata the report uses."""
import plistlib

import workspace as ws

WHISPER_MODELS = ["base", "small", "medium", "large-v3-turbo"]

# FluidAudio vocabulary boosting settings under test. Empty keys keep FluidAudio defaults.
#   rescue: spotter-anchored acoustic rescue on/off; rescueMinSim / rescueMultiMinSim: its similarity floors
#   taperPivot / taperExponent: weaken the boost for short terms; minSimilarity: string similarity gate
BOOST_VARIANTS = {
    "norescue": {"rescue": False},
    "floors": {"rescueMinSim": 0.30, "rescueMultiMinSim": 0.50, "taperPivot": 5, "taperExponent": 2.0},
    "norescue-taper": {"rescue": False, "taperPivot": 5, "taperExponent": 2.0},
    "norescue-sim65": {"rescue": False, "minSimilarity": 0.65},
    "norescue-taper-sim65": {"rescue": False, "taperPivot": 5, "taperExponent": 2.0, "minSimilarity": 0.65},
    "norescue-sim75": {"rescue": False, "minSimilarity": 0.75},
    "norescue-taper-sim75": {"rescue": False, "taperPivot": 5, "taperExponent": 2.0, "minSimilarity": 0.75},
    "norescue-sim75-short85": {"rescue": False, "minSimilarity": 0.75, "shortLength": 5, "shortSimilarity": 0.85},
}


def app_version():
    info = ws.APP_WHISPER_CLI.parents[1] / "Info.plist"
    return plistlib.loads(info.read_bytes()).get("CFBundleShortVersionString", "?") if info.exists() else "not installed"


def _engines():
    e = {}
    for m in WHISPER_MODELS:
        for dev in ["cpu", "gpu"]:
            e[f"whispercpp-app-{m}-{dev}"] = {
                "runner": "cli", "cli": "whisper", "binary": ws.APP_WHISPER_CLI,
                "model": ws.path(f"whisper-ggml-{m}"), "device": dev,
                "label": f"whisper {m}", "family": "Whisper", "runtime": "whisper.cpp in OpenScribe.app",
                "compute": dev.upper(), "resident": False,
            }
            e[f"whispercpp194-{m}-{dev}"] = {
                "runner": "cli", "cli": "whisper", "binary": ws.WHISPER_CPP_194_BIN / "whisper-cli",
                "model": ws.path(f"whisper-ggml-{m}"), "device": dev,
                "label": f"whisper {m}", "family": "Whisper", "runtime": "whisper.cpp 1.9.4",
                "compute": dev.upper(), "resident": False,
            }
    e["whispercpp194-large-v3-turbo-gpu-vocab"] = dict(e["whispercpp194-large-v3-turbo-gpu"], vocabulary=True,
                                                       label="whisper large-v3-turbo + vocabulary")
    for q in ["q8_0", "f16"]:
        for dev in ["cpu", "gpu"]:
            e[f"parakeetcpp194-v3-{q}-{dev}"] = {
                "runner": "cli", "cli": "parakeet", "binary": ws.WHISPER_CPP_194_BIN / "parakeet-cli",
                "model": ws.path(f"parakeet-gguf-v3-{q}"), "device": dev,
                "label": f"Parakeet v3 {q}", "family": "Parakeet", "runtime": "parakeet-cli 1.9.4",
                "compute": dev.upper(), "resident": False,
            }
    hf = ws.item("hf-mlx-models")["repos"]
    for v in ["v2", "v3"]:
        repo = f"mlx-community/parakeet-tdt-0.6b-{v}"
        e[f"parakeet-mlx-{v}"] = {
            "runner": "mlx", "repo": repo, "revision": hf[repo],
            "label": f"Parakeet {v}", "family": "Parakeet", "runtime": "parakeet-mlx", "compute": "GPU", "resident": True,
        }
    repo = "mlx-community/whisper-large-v3-turbo"
    e["mlx-whisper-large-v3-turbo"] = {
        "runner": "mlx", "repo": repo, "revision": hf[repo],
        "label": "whisper large-v3-turbo", "family": "Whisper", "runtime": "mlx-whisper", "compute": "GPU", "resident": True,
    }
    for v, name in [("v2", "Parakeet v2"), ("v3", "Parakeet v3"), ("ultra", "Parakeet Ultra")]:
        for units in ["ane", "gpu"]:
            e[f"fluidaudio-{v}-{units}"] = {
                "runner": "swift", "label": name, "family": "Parakeet", "runtime": "FluidAudio (Core ML)",
                "compute": "ANE" if units == "ane" else "GPU", "resident": True,
            }
    e["fluidaudio-ultra-gpu-vocab"] = dict(e["fluidaudio-ultra-gpu"], vocabulary=True, label="Parakeet Ultra + vocabulary")
    for variant, boost in BOOST_VARIANTS.items():
        e[f"fluidaudio-ultra-gpu-vocab@{variant}"] = dict(
            e["fluidaudio-ultra-gpu-vocab"], boost=boost, label=f"Parakeet Ultra + vocabulary ({variant})")
    e["apple-speechtranscriber"] = {
        "runner": "swift", "label": "SpeechTranscriber", "family": "Apple", "runtime": "Speech framework",
        "compute": "ANE", "resident": True,
    }
    return e


ENGINES = _engines()
