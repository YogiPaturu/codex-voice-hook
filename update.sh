#!/bin/sh
set -eu

REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
git -C "$REPO_DIR" pull --ff-only
"$REPO_DIR/install.sh"
