"""Show and clean everything the STT bench stores on this Mac.

Usage:
  inventory.py                 list items, sizes, and whether they exist
  inventory.py clean ID...     delete workspace items or cleanable external locations
  inventory.py clean --all     delete the whole workspace and every cleanable external location
"""
import os
import pathlib
import shutil
import subprocess
import sys

import workspace as ws


def size(p):
    if not p.exists():
        return None
    out = subprocess.run(["du", "-sk", str(p)], capture_output=True, text=True).stdout.split()
    return int(out[0]) * 1024 if out else 0


def human(n):
    if n is None:
        return "-"
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if n < 1024 or unit == "TB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024


def rows():
    inv = ws.inventory()
    extracted = set()
    for it in inv["items"]:
        yield it["id"], it["group"], ws.HOME / it["path"], True, it["purpose"]
        target = it.get("extract_to")
        if target and target not in extracted:
            extracted.add(target)
            yield f"{it['id']}:extracted", it["group"], ws.HOME / target, True, f"Extracted from {it['id']}."
    for it in inv["external"]:
        yield it["id"], "external", pathlib.Path(os.path.expanduser(it["path"])), it["cleanable"], it["purpose"]


def show():
    print(f"Workspace: {ws.HOME}  ({human(size(ws.HOME))} total)\n")
    print(f"{'id':36} {'group':9} {'size':>9}  path")
    for item_id, group, p, _, _ in rows():
        s = size(p)
        shown = p.relative_to(ws.HOME) if p.is_relative_to(ws.HOME) else p
        print(f"{item_id:36} {group:9} {human(s):>9}  {shown}{'' if s is not None else '  (missing)'}")
    known = {p for _, _, p, _, _ in rows() if p.is_relative_to(ws.HOME)}

    def strays(d):
        for c in sorted(d.iterdir()):
            if c in known:
                continue
            if any(c in k.parents for k in known):
                yield from strays(c)
            else:
                yield c

    stray = list(strays(ws.HOME)) if ws.HOME.exists() else []
    if stray:
        print("\nNot in the inventory (review, then add or delete):")
        for c in stray:
            print(f"  {human(size(c)):>9}  {c.relative_to(ws.HOME)}")


def clean(ids):
    table = {r[0]: r for r in rows()}
    targets = list(table) if ids == ["--all"] else ids
    for item_id in targets:
        _, group, p, cleanable, _ = table[item_id]
        if not cleanable:
            if ids != ["--all"]:
                print(f"skip {item_id}: not cleanable by the bench ({p})")
            continue
        if p.exists():
            shutil.rmtree(p) if p.is_dir() else p.unlink()
            print(f"deleted {item_id}: {p}")
    if ids == ["--all"] and ws.HOME.exists():
        shutil.rmtree(ws.HOME)
        print(f"deleted workspace: {ws.HOME}")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "clean":
        clean(sys.argv[2:])
    else:
        show()
