#!/bin/bash
# Build CallRec.app (menu bar front end) into ~/Applications. No Xcode required.
set -euo pipefail
cd "$(dirname "$0")"
APP="${1:-$HOME/Applications/CallRec.app}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O CallRecBar.swift -o "$APP/Contents/MacOS/CallRec"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>CallRec</string>
  <key>CFBundleExecutable</key><string>CallRec</string>
  <key>CFBundleIdentifier</key><string>org.zazet.callrec</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>CallRec records your calls locally so they can be transcribed on this machine.</string>
</dict></plist>
PLIST

# Stable ad-hoc identity, so macOS keeps the microphone grant across rebuilds.
codesign --force --sign - --identifier org.zazet.callrec "$APP"
echo "built → $APP"
