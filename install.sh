#!/bin/sh
set -eu

REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CODEX_DIR=${CODEX_HOME:-"$HOME/.codex"}
HOOKS_DIR="$CODEX_DIR/hooks"
mkdir -p "$HOOKS_DIR"

link_file() {
    source=$1
    target=$2
    if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
        return
    fi
    if [ -e "$target" ] || [ -L "$target" ]; then
        backup="$target.backup-$(date +%Y%m%d-%H%M%S)"
        mv "$target" "$backup"
        printf 'Saved existing file as %s\n' "$backup"
    fi
    ln -s "$source" "$target"
    printf 'Linked %s\n' "$target"
}

link_file "$REPO_DIR/speak-notify.py" "$HOOKS_DIR/speak-notify.py"
link_file "$REPO_DIR/stop-speech" "$HOOKS_DIR/stop-speech"

# Keep the response instruction in sync with this checkout while leaving the
# user's other global instructions untouched.
AGENTS_FILE="$CODEX_DIR/AGENTS.md"
/usr/bin/python3 - "$AGENTS_FILE" <<'PY'
from pathlib import Path
import shutil
import sys
import tempfile
import time

path = Path(sys.argv[1])
if path.is_symlink():
    raise SystemExit(f"{path} is a symlink; leaving it unchanged")

start = "<!-- codex-voice-hook:start -->"
end = "<!-- codex-voice-hook:end -->"
managed = f"""{start}
For Codex CLI responses in macOS Terminal, include a final single-line `🗣️ VOICE: ...` marker on its own line, with a line break before it, only when meaningful work is complete, a significant problem occurs, a decision is needed, or the user explicitly asks for speech. When a decision is needed, repeat the exact decision question and options verbatim in the marker so the user hears the choice Codex is waiting on. Keep it plain language; do not put code, file paths, or terminal logs in the marker. Omit the marker for all other responses.
{end}"""

text = path.read_text() if path.exists() else ""
begin = text.find(start)
finish = text.find(end)
if begin >= 0 and finish >= begin:
    finish += len(end)
    updated = text[:begin] + managed + text[finish:]
elif begin >= 0 or finish >= 0:
    raise SystemExit(f"{path} contains an incomplete voice hook block; leaving it unchanged")
else:
    # Migrate the earlier plain VOICE instruction in place when present. This
    # changes only that instruction and retains every surrounding line.
    legacy = "For Codex CLI responses in macOS Terminal, include a final single-line `VOICE: ...` marker"
    lines = text.splitlines(keepends=True)
    legacy_index = next(
        (index for index, line in enumerate(lines) if line.lstrip().startswith(legacy)),
        None,
    )
    if legacy_index is not None:
        before = "".join(lines[:legacy_index]).rstrip()
        after = "".join(lines[legacy_index + 1:]).lstrip("\n")
        updated = (before + ("\n\n" if before else "") + managed +
                   ("\n\n" + after if after else "\n"))
    else:
        updated = text.rstrip() + ("\n\n" if text.strip() else "") + managed + "\n"

if updated == text:
    print("Codex voice instruction is up to date")
else:
    if path.exists():
        stem = path.name + ".backup-" + time.strftime("%Y%m%d-%H%M%S")
        backup = path.with_name(stem)
        suffix = 1
        while backup.exists():
            backup = path.with_name(f"{stem}-{suffix}")
            suffix += 1
        shutil.copy2(path, backup)
        print(f"Saved existing instructions as {backup}")
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=path.parent,
        prefix=path.name + ".", suffix=".tmp", delete=False
    ) as temporary_file:
        temporary_file.write(updated)
        temporary = Path(temporary_file.name)
    if path.exists():
        temporary.chmod(path.stat().st_mode)
    temporary.replace(path)
    print("Updated the Codex voice instruction")
PY

HOOKS_CONFIG="$CODEX_DIR/hooks.json"
/usr/bin/python3 - "$HOOKS_CONFIG" "$HOOKS_DIR/speak-notify.py" <<'PY'
import json
from pathlib import Path
import shlex
import shutil
import sys
import tempfile
import time

config_path = Path(sys.argv[1])
hook_script = Path(sys.argv[2])
if config_path.is_symlink():
    raise SystemExit(f"{config_path} is a symlink; leaving it unchanged")
if config_path.exists():
    config = json.loads(config_path.read_text())
else:
    config = {"hooks": {}}
if not isinstance(config, dict):
    raise SystemExit("hooks.json must contain a JSON object; leaving it unchanged")

hooks = config.setdefault("hooks", {})
if not isinstance(hooks, dict):
    raise SystemExit("hooks in hooks.json must be an object; leaving it unchanged")
groups = hooks.setdefault("PermissionRequest", [])
if not isinstance(groups, list):
    raise SystemExit("hooks.PermissionRequest must be an array; leaving hooks.json unchanged")

command = f"/usr/bin/python3 {shlex.quote(str(hook_script))}"
already_registered = any(
    isinstance(group, dict)
    and any(
        isinstance(item, dict) and item.get("command") == command
        for item in group.get("hooks", [])
    )
    for group in groups
)

if already_registered:
    print("PermissionRequest speech hook is already registered")
else:
    if config_path.exists():
        stem = config_path.name + ".backup-" + time.strftime("%Y%m%d-%H%M%S")
        backup = config_path.with_name(stem)
        suffix = 1
        while backup.exists():
            backup = config_path.with_name(f"{stem}-{suffix}")
            suffix += 1
        shutil.copy2(config_path, backup)
        print(f"Saved existing hook config as {backup}")
    groups.append(
        {
            "hooks": [
                {
                    "type": "command",
                    "command": command,
                    "timeout": 10,
                }
            ]
        }
    )
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=config_path.parent,
        prefix=config_path.name + ".", suffix=".tmp", delete=False
    ) as temporary_file:
        temporary_file.write(json.dumps(config, indent=2) + "\n")
        temporary = Path(temporary_file.name)
    if config_path.exists():
        temporary.chmod(config_path.stat().st_mode)
    temporary.replace(config_path)
    print("Registered PermissionRequest speech hook")
PY

CODEX_CONFIG="$CODEX_DIR/config.toml"
/usr/bin/python3 - "$CODEX_CONFIG" "$HOOKS_DIR/speak-notify.py" <<'PY'
from pathlib import Path
import re
import shutil
import sys
import tempfile
import time

config_path = Path(sys.argv[1])
hook_script = Path(sys.argv[2])
if config_path.is_symlink():
    raise SystemExit(f"{config_path} is a symlink; leaving it unchanged")
command = f'/usr/bin/python3 "{hook_script}"'
toml_command = command.replace("\\", "\\\\").replace('"', '\\"')
group = f'{{ hooks = [{{ type = "command", command = "{toml_command}" }}] }}'
text = config_path.read_text() if config_path.exists() else ""

if toml_command in text:
    print("Stop speech hook is already registered")
else:
    if not text:
        updated = f"[hooks]\nStop = [{group}]\n"
    else:
        section = re.search(r"(?m)^\s*\[hooks\]\s*(?:#.*)?$", text)
        if not section:
            # Codex stores internal hook state in [hooks.state.*]. That does
            # not define the user hook table, so place [hooks] before it.
            state_section = re.search(r"(?m)^\s*\[\[?hooks\.state(?:\.|\])", text)
            root_hooks = re.search(r"(?m)^\s*hooks\s*=", text)
            other_hooks_table = re.search(r"(?m)^\s*\[\[?hooks\.(?!state(?:\.|\]))[^\]]+\]\]?", text)
            if root_hooks or other_hooks_table:
                raise SystemExit(
                    "config.toml defines hooks in another form; leaving it unchanged. "
                    "Add the Stop speech hook manually."
                )
            if state_section:
                insertion = state_section.start()
                prefix = text[:insertion].rstrip()
                suffix = text[insertion:]
                updated = prefix + f"\n\n[hooks]\nStop = [{group}]\n\n" + suffix
            else:
                updated = text.rstrip() + f"\n\n[hooks]\nStop = [{group}]\n"
        else:
            next_section = re.search(r"(?m)^\s*\[\[?[^\]]+\]\]?\s*(?:#.*)?$", text[section.end():])
            section_end = section.end() + next_section.start() if next_section else len(text)
            body = text[section.end():section_end]
            stop_key = re.search(r"(?m)^(\s*Stop\s*=\s*)(\[)", body)
            if not stop_key:
                if re.search(r"(?m)^\s*Stop\s*=", body):
                    raise SystemExit("hooks.Stop exists but is not an array; add the speech hook manually")
                insertion = section.end()
                updated = text[:insertion] + f"\nStop = [{group}]\n" + text[insertion:]
            else:
                value_start = section.end() + stop_key.start(2)
                depth = 0
                quote = None
                escaped = False
                close = None
                index = value_start
                while index < section_end:
                    char = text[index]
                    if quote:
                        if escaped:
                            escaped = False
                        elif char == "\\":
                            escaped = True
                        elif char == quote:
                            quote = None
                        index += 1
                        continue
                    if char in ('"', "'"):
                        quote = char
                    elif char == "#":
                        newline = text.find("\n", index, section_end)
                        if newline < 0:
                            break
                        index = newline + 1
                        continue
                    elif char == "[":
                        depth += 1
                    elif char == "]":
                        depth -= 1
                        if depth == 0:
                            close = index
                            break
                    index += 1
                if close is None:
                    raise SystemExit("Could not find the end of hooks.Stop array in config.toml")
                current = text[value_start + 1:close].rstrip()
                separator = "" if not current.strip() else (" " if current.endswith(",") else ", ")
                updated = text[:close] + separator + group + text[close:]

    if updated != text:
        if config_path.exists():
            stem = config_path.name + ".backup-" + time.strftime("%Y%m%d-%H%M%S")
            backup = config_path.with_name(stem)
            suffix = 1
            while backup.exists():
                backup = config_path.with_name(f"{stem}-{suffix}")
                suffix += 1
            shutil.copy2(config_path, backup)
            print(f"Saved existing config as {backup}")
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=config_path.parent,
            prefix=config_path.name + ".", suffix=".tmp", delete=False
        ) as temporary_file:
            temporary_file.write(updated)
            temporary = Path(temporary_file.name)
        if config_path.exists():
            temporary.chmod(config_path.stat().st_mode)
        temporary.replace(config_path)
        print("Registered Stop speech hook")
PY

printf 'Hook files now use the checkout at %s\n' "$REPO_DIR"
printf 'Restart Codex if it is running. Update later with: %s/update.sh\n' "$REPO_DIR"
