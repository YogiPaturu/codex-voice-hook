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

SAFE_SPOKEN_TEXT = re.compile(r"[\w\s.,!?;:’'()\-]+", re.UNICODE)
CODE_FILE = re.compile(
    r"\b[\w-]+\.(?:py|js|ts|tsx|jsx|sh|toml|json|log|md|txt|yaml|yml|rs|go|java|c|h)\b",
    re.IGNORECASE,
)
DECISION_QUESTION = re.compile(
    r"\b(?:which|what|should i|would you like|do you want|shall i|"
    r"want me to|would you prefer|do you prefer)\b",
    re.IGNORECASE,
)
EXPLICIT_DECISION = re.compile(
    r"\b(?:please\s+)?(?:choose|select|pick)\b|"
    r"\b(?:need|awaiting|waiting for)\s+(?:your\s+)?(?:decision|choice|approval)\b|"
    r"\bdecision needed\b",
    re.IGNORECASE,
)
QUEUE_DB = "/tmp/codex-voice-hook-queue.sqlite3"
WORKER_LOCK = "/tmp/codex-voice-hook-worker.lock"
COMPUTER_USE = (
    Path.home()
    / ".codex/computer-use/Codex Computer Use.app/Contents/SharedSupport/"
    "SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient"
)


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
        match = re.fullmatch(r"\s*(?:🗣️\s*)?VOICE:\s*(.*?)\s*", line, flags=re.IGNORECASE)
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


def extract_decision_request(response):
    """Speak a clear choice request when the response has no VOICE marker."""
    if not isinstance(response, str):
        return None

    in_fence = False
    paragraphs = []
    current = []
    for line in response.splitlines():
        fence = re.match(r"\s*(```|~~~)", line)
        if fence:
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if not line.strip():
            if current:
                paragraphs.append(" ".join(current))
                current = []
            continue
        if re.match(r"\s*(?:🗣️\s*)?VOICE:", line, flags=re.IGNORECASE):
            continue
        line = re.sub(r"^\s*(?:[-*+]\s+|\d+[.)]\s+|#+\s*)", "", line)
        line = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", line)
        line = re.sub(r"https?://\S+", "", line)
        line = re.sub(r"[`*_>#]", "", line).strip()
        if line:
            current.append(line)
    if current:
        paragraphs.append(" ".join(current))

    for paragraph in reversed(paragraphs):
        paragraph = re.sub(r"\s+", " ", paragraph).replace("—", ", ").replace("–", "-").strip()
        is_question = "?" in paragraph and DECISION_QUESTION.search(paragraph)
        is_explicit = EXPLICIT_DECISION.search(paragraph)
        if not (is_question or is_explicit):
            continue
        if (
            SAFE_SPOKEN_TEXT.fullmatch(paragraph)
            and "_" not in paragraph
            and not CODE_FILE.search(paragraph)
        ):
            return paragraph
    return None


def permission_request_message():
    """Keep approval prompts short and avoid speaking tool details."""
    return "Decision needed."


def project_name(cwd):
    path = Path(cwd).expanduser().resolve()
    try:
        root = subprocess.run(
            ["/usr/bin/git", "-C", str(path), "rev-parse", "--show-toplevel"],
            check=True,
            capture_output=True,
            text=True,
            timeout=1,
        ).stdout.strip()
        if root:
            path = Path(root)
    except (OSError, subprocess.SubprocessError):
        markers = ("pyproject.toml", "package.json", "Cargo.toml", "go.mod", "Makefile", "justfile", "composer.json")
        for parent in (path, *path.parents):
            if (parent / ".git").exists() or any((parent / marker).is_file() for marker in markers):
                path = parent
                break
    name = re.sub(r"[^\w -]", "", path.name).replace("_", " ").strip()[:40]
    return name or "Codex"


def enqueue(project, spoken):
    with sqlite3.connect(QUEUE_DB, timeout=10) as db:
        db.execute("CREATE TABLE IF NOT EXISTS speech (id INTEGER PRIMARY KEY, text TEXT NOT NULL)")
        db.execute("INSERT INTO speech (text) VALUES (?)", (f"Project {project}. {spoken}",))
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

    is_cli_notification = len(sys.argv) > 1
    if is_cli_notification:
        payload = sys.argv[-1]
    elif not sys.stdin.isatty():
        payload = sys.stdin.read()
    else:
        payload = "{}"
    try:
        event = json.loads(payload)
    except (json.JSONDecodeError, TypeError):
        return 0

    if is_cli_notification:
        if COMPUTER_USE.is_file():
            try:
                subprocess.Popen(
                    [str(COMPUTER_USE), "turn-ended", payload],
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
            except OSError:
                pass
        if event.get("type") != "agent-turn-complete":
            return 0
        response = event.get("last-assistant-message")
        cwd = event.get("cwd")
    else:
        hook_event = event.get("hook_event_name")
        if hook_event == "PermissionRequest":
            # Permission prompts are separate from the completed assistant
            # message, so announce the pending decision without trying to
            # infer or speak the prompt text.
            cwd = event.get("cwd") or event.get("current_working_directory") or os.getcwd()
            enqueue(project_name(cwd), permission_request_message())
            return 0
        if hook_event != "Stop":
            return 0
        response = event.get("last_assistant_message")
        cwd = event.get("cwd")

    spoken = extract_voice_marker(response) or extract_decision_request(response)
    if spoken:
        cwd = cwd or event.get("current_working_directory") or os.getcwd()
        enqueue(project_name(cwd), spoken)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
