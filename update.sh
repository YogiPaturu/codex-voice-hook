#!/bin/sh
set -eu

REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
git -C "$REPO_DIR" pull --ff-only
printf 'Refreshing all Codex Voice Hook scripts and configuration...\n'
exec "$REPO_DIR/install.sh"
