#!/bin/bash
set -euo pipefail

CONFIG="${1:-debug}"
swift build -c "$CONFIG"

BIN_DIR=".build/$CONFIG"
APP_DIR=".build/Toki.app"
CONTENTS="$APP_DIR/Contents"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

cp "$BIN_DIR/Toki" "$CONTENTS/MacOS/Toki"
cp "Resources/Info.plist" "$CONTENTS/Info.plist"

echo "Built $APP_DIR"
echo "Run: open $APP_DIR"
