#!/usr/bin/env python3
"""Speak a short VOICE: line from a completed Codex response on macOS."""

import json
import fcntl
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import time

SAFE_SPOKEN_TEXT = re.compile(r"[\w\s.,!?;’'()\-]+", re.UNICODE)
CODE_FILE = re.compile(
    r"\b[\w-]+\.(?:py|js|ts|tsx|jsx|sh|toml|json|log|md|txt|yaml|yml|rs|go|java|c|h)\b",
    re.IGNORECASE,
)
QUEUE_DB = "/tmp/codex-voice-hook-queue.sqlite3"
WORKER_LOCK = "/tmp/codex-voice-hook-worker.lock"


def extract_voice_marker(response):
    if not isinstance(response, str):
        return None
    in_fence = False
    fence_char = None
    for line in response.splitlines():
        fence = re.match(r"\s*(```|~~~)", line)
        if fence:
            token = fence.group(1)
            if not in_fence:
                in_fence, fence_char = True, token[0]
            elif token[0] == fence_char:
                in_fence, fence_char = False, None
            continue
        if in_fence:
            continue
        match = re.fullmatch(r"\s*VOICE:\s*(.*?)\s*", line, flags=re.IGNORECASE)
        if not match:
            continue
        text = match.group(1).strip()
        if (
            not text
            or not SAFE_SPOKEN_TEXT.fullmatch(text)
            or "_" in text
            or CODE_FILE.search(text)
        ):
            return None
        return text
    return None


def enqueue(project, spoken):
    with sqlite3.connect(QUEUE_DB, timeout=10) as db:
        db.execute("CREATE TABLE IF NOT EXISTS speech (id INTEGER PRIMARY KEY, text TEXT NOT NULL)")
        db.execute("INSERT INTO speech (text) VALUES (?)", (f"{project}. {spoken}",))
    subprocess.Popen(
        [sys.executable, str(Path(__file__).resolve()), "--worker"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def run_worker():
    with open(WORKER_LOCK, "w") as lock:
        # Each enqueue launches a worker; waiting workers prevent lost wakeups.
        fcntl.flock(lock, fcntl.LOCK_EX)
        while True:
            with sqlite3.connect(QUEUE_DB, timeout=10) as db:
                db.execute("CREATE TABLE IF NOT EXISTS speech (id INTEGER PRIMARY KEY, text TEXT NOT NULL)")
                row = db.execute("SELECT id, text FROM speech ORDER BY id LIMIT 1").fetchone()
            if row is None:
                return 0
            subprocess.run(
                ["/usr/bin/say", "-r", "210", row[1]],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            with sqlite3.connect(QUEUE_DB, timeout=10) as db:
                db.execute("DELETE FROM speech WHERE id = ?", (row[0],))
            time.sleep(0.1)


def stop_speech():
    with sqlite3.connect(QUEUE_DB, timeout=10) as db:
        db.execute("CREATE TABLE IF NOT EXISTS speech (id INTEGER PRIMARY KEY, text TEXT NOT NULL)")
        db.execute("DELETE FROM speech")
    subprocess.run(
        ["/usr/bin/pkill", "-x", "say"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return 0


def main():
    if sys.argv[1:] == ["--worker"]:
        return run_worker()
    if sys.argv[1:] == ["--stop"]:
        return stop_speech()

    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, TypeError):
        return 0

    if event.get("hook_event_name") != "Stop":
        return 0

    spoken = extract_voice_marker(event.get("last_assistant_message"))
    if spoken:
        cwd = event.get("cwd") or os.getcwd()
        project = re.sub(r"[^\w -]", "", Path(cwd).name).replace("_", " ").strip()[:40]
        enqueue(project or "Codex", spoken)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
