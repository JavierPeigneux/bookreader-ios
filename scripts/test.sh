#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/xcode_env.sh
if [[ -z "${READER_DESTINATION:-}" ]]; then
  reader_device=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
inventory=json.load(sys.stdin)["devices"]
devices=[device for runtime,entries in inventory.items() if runtime.startswith("com.apple.CoreSimulator.SimRuntime.iOS-27-2") for device in entries]
ranked=sorted(devices,key=lambda d:("Duo" not in d["name"],d["name"]))
if not ranked: sys.exit("No hay simuladores iOS 27.2. Instala el runtime y crea un dispositivo en Xcode.")
print(ranked[0]["udid"])
')
  export READER_DESTINATION="platform=iOS Simulator,id=$reader_device"
fi
xcodebuild -project BookreaderSimulator.xcodeproj -scheme Bookreader \
  -destination "$READER_DESTINATION" \
  -derivedDataPath .build/simulator272 -clonedSourcePackagesDirPath .build/SourcePackages test CODE_SIGNING_ALLOWED=NO "$@"
