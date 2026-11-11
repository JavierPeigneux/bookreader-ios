#!/bin/zsh
# Respect an explicit toolchain; otherwise use the installed Xcode 27.2 RC.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-27.2.0-Release.Candidate.app/Contents/Developer}"
if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
  print -u2 'No se encuentra Xcode. Define DEVELOPER_DIR apuntando a Xcode 27.2 o posterior.'
  return 1
fi
