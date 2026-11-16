#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/xcode_env.sh
exec python3 scripts/screenshots.py "$@"
