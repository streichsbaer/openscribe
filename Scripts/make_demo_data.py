#!/usr/bin/env python3
"""Build a demo OpenScribe data folder for docs screenshots.

Creates recent sessions with synthesized audio, raw and polished text, and a stats ledger with
ten weeks of local Parakeet usage. Nothing here comes from a real user.

Usage:
  python3 Scripts/make_demo_data.py OUT_DIR [--models-from DIR]

--models-from links an existing Models folder so the Data tab shows installed models.
Then run the UI smoke with --data-dir OUT_DIR.
"""
import argparse
import json
import random
import shutil
import subprocess
import tempfile
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

SESSIONS = [
    # (days ago, hour, minute, text, vocabulary fixes)
    (0, 16, 12, "Let's push the branch and open the PR. Then check the cron job in the tmux session before the demo.",
     [("tea mux", "tmux")]),
    (0, 15, 58, "Tell the team the release is out and Homebrew picks it up with brew upgrade.", []),
    (0, 15, 41, "Add a test for the retry logic and run it with pytest before lunch.", []),
    (0, 14, 56, "Summarize the three risks from the planning doc and send them to the team.", []),
    (1, 18, 20, "Draft a short changelog note about vocabulary and the new Parakeet engine.", []),
    (1, 11, 15, "Remind me to rotate the staging API key after the migration.", []),
    (1, 9, 40, "Move the standup to ten thirty and ask Sam to bring the latency numbers.", []),
    (2, 17, 5, "Refactor the settings view so each tab lives in its own file.", []),
    (3, 10, 22, "Check why the nightly build takes twice as long since Tuesday.", []),
    (4, 16, 48, "Write the release notes in three short bullets, no marketing speak.", []),
    (5, 13, 30, "Open an issue for the flaky snapshot test on Intel.", []),
    (6, 12, 2, "The heatmap looks good, ship it after the docs review.", []),
]


def iso(moment: datetime) -> str:
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def synthesize(text: str, target: Path) -> float:
    with tempfile.TemporaryDirectory() as scratch:
        aiff = Path(scratch) / "speech.aiff"
        subprocess.run(["say", "-v", "Samantha", "-r", "175", "-o", str(aiff), text], check=True)
        subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", str(aiff), str(target)], check=True)
    info = subprocess.run(["afinfo", str(target)], check=True, capture_output=True, text=True).stdout
    for line in info.splitlines():
        if "estimated duration" in line:
            return float(line.split(":")[1].split()[0])
    return 4.0


def event(session_id: str, when: datetime, words: int, seconds: float, processing_ms: int) -> dict:
    return {
        "id": str(uuid.uuid4()).upper(),
        "sessionId": session_id,
        "timestamp": iso(when),
        "stage": "transcription",
        "providerId": "parakeet",
        "model": "parakeet-ultra",
        "inputUnits": round(seconds, 2),
        "outputUnits": float(words),
        "inputUnit": "audio_seconds",
        "outputUnit": "words",
        "inputTokens": None,
        "outputTokens": None,
        "recordingDurationMs": int(seconds * 1000),
        "wordsPerMinute": round(words / (seconds / 60), 1) if seconds > 0 else None,
        "wordDelta": None,
        "wordDeltaPercent": None,
        "processingDurationMs": processing_ms,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("out_dir")
    parser.add_argument("--models-from")
    args = parser.parse_args()

    out = Path(args.out_dir).expanduser().resolve()
    if out.exists():
        shutil.rmtree(out)
    (out / "Recordings").mkdir(parents=True)
    (out / "Stats").mkdir()
    if args.models_from:
        (out / "Models").symlink_to(Path(args.models_from).expanduser().resolve(), target_is_directory=True)

    random.seed(29)
    now = datetime.now().astimezone()
    today = now.replace(hour=0, minute=0, second=0, microsecond=0)
    events = []

    for days_ago, hour, minute, text, fixes in SESSIONS:
        created = today - timedelta(days=days_ago) + timedelta(hours=hour, minutes=minute)
        if created > now:
            created = now - timedelta(minutes=5 + days_ago)
        session_id = str(uuid.uuid4()).upper()
        folder = out / "Recordings" / created.strftime("%Y-%m-%d") / f"{created.strftime('%H%M%S')}-{session_id}"
        folder.mkdir(parents=True)
        seconds = synthesize(text, folder / "audio.m4a")
        (folder / "raw.txt").write_text(text)
        (folder / "polished.md").write_text(text)
        stopped = created + timedelta(seconds=seconds)
        metadata = {
            "sessionId": session_id,
            "createdAt": iso(created),
            "stoppedAt": iso(stopped),
            "durationMs": int(seconds * 1000),
            "inputDeviceName": "MacBook Pro Microphone",
            "sampleRate": 16000,
            "channels": 1,
            "sttProvider": "parakeet",
            "sttModel": "parakeet-ultra",
            "polishProvider": "disabled",
            "polishModel": "passthrough",
            "languageMode": "auto",
            "state": "completed",
            "stateTransitions": [
                {"state": "recording", "timestamp": iso(created), "details": "Session started"},
                {"state": "completed", "timestamp": iso(stopped), "details": "Transcription complete"},
            ],
            "audioFilePath": str(folder / "audio.m4a"),
            "rawFilePath": str(folder / "raw.txt"),
            "polishedFilePath": str(folder / "polished.md"),
        }
        if fixes:
            metadata["vocabularyFixes"] = [{"heard": heard, "term": term} for heard, term in fixes]
        (folder / "session.json").write_text(json.dumps(metadata, indent=2, sort_keys=True))
        events.append(event(session_id, stopped, len(text.split()), seconds, random.randint(80, 190)))

    # Earlier usage that only shows in Stats: about ten weeks of dictation on most weekdays.
    for days_ago in range(0, 70):
        day = today - timedelta(days=days_ago)
        weekend = day.weekday() >= 5
        if random.random() < (0.25 if weekend else 0.85):
            for _ in range(random.randint(2, 6 if not weekend else 2)):
                words = random.randint(40, 190)
                seconds = words / random.uniform(1.7, 2.3)
                when = day + timedelta(hours=random.randint(9, 18), minutes=random.randint(0, 59))
                if when > now:
                    continue
                events.append(event(str(uuid.uuid4()).upper(), when, words, seconds, random.randint(80, 220)))

    events.sort(key=lambda item: item["timestamp"])
    with (out / "Stats" / "usage.events.jsonl").open("w") as ledger:
        for item in events:
            ledger.write(json.dumps(item, sort_keys=True) + "\n")

    print(f"Demo data: {out} ({len(SESSIONS)} sessions, {len(events)} stats events)")


if __name__ == "__main__":
    main()
