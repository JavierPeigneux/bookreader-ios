#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/xcode_env.sh
mkdir -p .build
xcrun swiftc Folisona/Models/Book.swift Folisona/Services/AppleSpeechService.swift ValidationHarness/AppleSpeechCheck.swift -o .build/AppleSpeechCheck
.build/AppleSpeechCheck "$@"
