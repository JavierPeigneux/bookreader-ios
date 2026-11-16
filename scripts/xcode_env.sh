#!/bin/zsh
# Respect an explicit toolchain without changing the global xcode-select setting.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  if [[ -x /Applications/Xcode-27.2.0-Release.Candidate.app/Contents/Developer/usr/bin/xcodebuild ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-27.2.0-Release.Candidate.app/Contents/Developer
  else
    export DEVELOPER_DIR="$(xcode-select -p)"
  fi
fi
if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
  print -u2 'No se encuentra Xcode. Define DEVELOPER_DIR apuntando a Xcode 27.2 o posterior.'
  return 1
fi
