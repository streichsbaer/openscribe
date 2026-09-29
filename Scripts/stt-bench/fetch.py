"""Download and verify inventory items. Skips anything already present with the right hash.

Usage: fetch.py [ID...]   (default: every file, archive, and hf item)
"""
import hashlib
import subprocess
import sys
import tarfile
import urllib.request

import workspace as ws


def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch_file(it):
    dest = ws.HOME / it["path"]
    if dest.exists() and sha256(dest) == it["sha256"]:
        return dest
    dest.parent.mkdir(parents=True, exist_ok=True)
    part = dest.with_suffix(dest.suffix + ".part")
    print(f"downloading {it['id']} ({it['bytes'] / 1e6:.0f} MB)", flush=True)
    urllib.request.urlretrieve(it["url"], part)
    got = sha256(part)
    if got != it["sha256"]:
        part.unlink()
        raise SystemExit(f"{it['id']}: sha256 mismatch, expected {it['sha256']}, got {got}")
    part.rename(dest)
    return dest


def fetch_archive(it):
    archive = fetch_file(it)
    target = ws.HOME / it["extract_to"]
    marker = target / f".extracted-{it['id']}"
    if marker.exists():
        return
    target.mkdir(parents=True, exist_ok=True)
    print(f"extracting {it['id']}", flush=True)
    with tarfile.open(archive) as tar:
        tar.extractall(target, filter="data")
    marker.touch()


def fetch_hf(it):
    from huggingface_hub import snapshot_download
    for repo, revision in it["repos"].items():
        snapshot_download(repo, revision=revision, cache_dir=ws.HF_HOME / "hub")


def build_whisper_cpp():
    """Build whisper-cli and parakeet-cli 1.9.4 with the same CMake options as the app bundle script."""
    root = ws.HOME / ws.item("whisper-cpp-1.9.4-source")["extract_to"]
    source = root / "whisper.cpp-1.9.4"
    build = root / "build"
    if (build / "bin" / "whisper-cli").exists() and (build / "bin" / "parakeet-cli").exists():
        return
    print("building whisper.cpp 1.9.4", flush=True)
    subprocess.run(["cmake", "-S", source, "-B", build, "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0"], check=True)
    subprocess.run(["cmake", "--build", build, "--target", "whisper-cli", "parakeet-cli", "--config", "Release", "-j"], check=True)


def main(ids):
    items = ws.inventory()["items"]
    selected = [i for i in items if not ids or i["id"] in ids]
    for it in selected:
        if it["kind"] == "file":
            fetch_file(it)
        elif it["kind"] == "archive":
            fetch_archive(it)
        elif it["kind"] == "hf":
            fetch_hf(it)
    if not ids or "whisper-cpp-1.9.4-source" in ids:
        build_whisper_cpp()
    print("fetch complete", flush=True)


if __name__ == "__main__":
    main(sys.argv[1:])
