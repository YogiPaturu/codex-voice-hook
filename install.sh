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

HOOKS_CONFIG="$CODEX_DIR/hooks.json"
/usr/bin/python3 - "$HOOKS_CONFIG" "$HOOKS_DIR/speak-notify.py" <<'PY'
import json
from pathlib import Path
import shlex
import shutil
import sys
import time

config_path = Path(sys.argv[1])
hook_script = Path(sys.argv[2])
if config_path.exists():
    config = json.loads(config_path.read_text())
else:
    config = {"hooks": {}}

hooks = config.setdefault("hooks", {})
groups = hooks.setdefault("PermissionRequest", [])
if not isinstance(groups, list):
    raise SystemExit("hooks.PermissionRequest must be an array")

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
        backup = config_path.with_name(
            config_path.name + ".backup-" + time.strftime("%Y%m%d-%H%M%S")
        )
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
    config_path.write_text(json.dumps(config, indent=2) + "\n")
    print("Registered PermissionRequest speech hook")
PY

printf 'Hook files now use the checkout at %s\n' "$REPO_DIR"
printf 'Restart Codex if it is running. Update later with: %s/update.sh\n' "$REPO_DIR"
