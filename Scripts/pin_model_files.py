#!/usr/bin/env python3
"""Pin a multi-file Hugging Face model for OpenScribe's model catalog.

Downloads every file of REPO at REVISION, hashes it, and prints a Swift array of ModelAssetFile
values for Sources/OpenScribe/Core/ParakeetModelFiles.swift.

Usage: python3 Scripts/pin_model_files.py REPO REVISION SWIFT_NAME [--include PREFIX ...]

Without --include, every file except .gitattributes and README.md is pinned.
"""
import argparse
import hashlib
import json
import urllib.request

ap = argparse.ArgumentParser()
ap.add_argument("repo")
ap.add_argument("revision")
ap.add_argument("name")
ap.add_argument("--include", nargs="*", default=None, help="only pin paths starting with these prefixes")
args = ap.parse_args()

api = f"https://huggingface.co/api/models/{args.repo}/revision/{args.revision}?blobs=true"
info = json.load(urllib.request.urlopen(api))
if info["sha"] != args.revision:
    raise SystemExit(f"revision mismatch: asked {args.revision}, got {info['sha']}")

lines = []
for sibling in sorted(info["siblings"], key=lambda s: s["rfilename"]):
    path = sibling["rfilename"]
    if path in (".gitattributes", "README.md"):
        continue
    if args.include is not None and not any(path.startswith(p) for p in args.include):
        continue
    url = f"https://huggingface.co/{args.repo}/resolve/{args.revision}/{path}"
    h = hashlib.sha256()
    size = 0
    with urllib.request.urlopen(url) as r:
        for chunk in iter(lambda: r.read(1 << 20), b""):
            h.update(chunk)
            size += len(chunk)
    digest = h.hexdigest()
    lfs = (sibling.get("lfs") or {}).get("sha256")
    if lfs and lfs != digest:
        raise SystemExit(f"{path}: LFS sha256 {lfs} does not match download {digest}")
    lines.append(f'        .init(path: "{path}", sizeBytes: {size}, sha256: "{digest}")')

print(f"    // {args.repo} at {args.revision}")
print(f"    static let {args.name}: [ModelAssetFile] = [")
print(",\n".join(lines))
print("    ]")
