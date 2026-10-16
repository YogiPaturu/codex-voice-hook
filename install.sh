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
printf 'Hook files now use the checkout at %s\n' "$REPO_DIR"
printf 'Restart Codex if it is running. Update later with: %s/update.sh\n' "$REPO_DIR"
