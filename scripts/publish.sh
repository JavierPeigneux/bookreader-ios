#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/xcode_env.sh
if [[ ! -x .build/publish-venv/bin/python ]]; then
  python3 -m venv .build/publish-venv
  .build/publish-venv/bin/pip install -r scripts/publish-requirements.txt
fi
exec .build/publish-venv/bin/python scripts/publish.py "$@"
