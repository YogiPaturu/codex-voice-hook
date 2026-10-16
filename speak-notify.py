#!/usr/bin/env python3
"""Speak a short VOICE: line from a completed Codex response on macOS."""

import json
import fcntl
import re
import subprocess
import sys

SAFE_SPOKEN_TEXT = re.compile(r"[\w\s.,!?;’'()\-]+", re.UNICODE)
CODE_FILE = re.compile(
    r"\b[\w-]+\.(?:py|js|ts|tsx|jsx|sh|toml|json|log|md|txt|yaml|yml|rs|go|java|c|h)\b",
    re.IGNORECASE,
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


def main():
    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, TypeError):
        return 0

    if event.get("hook_event_name") != "Stop":
        return 0

    spoken = extract_voice_marker(event.get("last_assistant_message"))
    if spoken:
        # Serialize replacement so simultaneous terminal hooks cannot overlap.
        with open("/tmp/codex-voice-hook.lock", "w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            subprocess.run(
                ["/usr/bin/pkill", "-x", "say"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            subprocess.Popen(
                ["/usr/bin/say", "-r", "210", spoken],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
