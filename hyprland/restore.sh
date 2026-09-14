#!/usr/bin/env bash
# Restore shares the installer's fixed destination allow-list and rollback logic.
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
exec bash "$SCRIPT_DIR/install.sh" --restore "$@"
