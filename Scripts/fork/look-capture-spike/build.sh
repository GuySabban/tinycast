#!/bin/bash
# Build and sign the throwaway Look capture spike into build/LookCaptureSpike.app. Usage: build.sh [stamp]
set -euo pipefail

cd "$(dirname "$0")/../../.." || exit 1
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
IDENTITY="Tinycast Self-Signed"
STAMP="${1:-$(date +%Y%m%d%H%M%S)}"
APP="build/LookCaptureSpike.app"
SRC="Scripts/fork/look-capture-spike"

if ! security find-identity -p codesigning | grep -q "$IDENTITY"; then
    echo "✗ '$IDENTITY' code-signing identity not found — create it once (docs/signing.md)." >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" build/look-capture-spike
echo "let buildStamp = \"$STAMP\"" > build/look-capture-spike/Stamp.swift
xcrun swiftc -swift-version 6 -O -parse-as-library -target arm64-apple-macos26.0 \
    -o "$APP/Contents/MacOS/LookCaptureSpike" \
    "$SRC/LookCaptureSpike.swift" build/look-capture-spike/Stamp.swift
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>io.github.guysabban.spotcast.look-capture-spike</string>
    <key>CFBundleName</key><string>LookCaptureSpike</string>
    <key>CFBundleExecutable</key><string>LookCaptureSpike</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.0.1</string>
    <key>CFBundleVersion</key><string>$STAMP</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
codesign -dvvv "$APP" 2>&1 | grep -E "^(Identifier|CDHash)="
codesign -d -r- "$APP" 2>&1 | grep designated
echo "✓ $APP (stamp $STAMP)"
