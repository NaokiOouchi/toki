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

# 開発用の自己署名証明書で署名。これにより rebuild しても署名が安定し、
# macOS Keychain ACL（OAuth token アクセス権限）が永続化する。
# ユーザーが Keychain Access.app の Certificate Assistant で
# "Toki Dev" という名前の Code Signing 証明書（Self Signed Root）を
# 作成しておく必要がある（一度だけのセットアップ）。
# CODESIGN_IDENTITY 環境変数で署名 ID を上書き可能、未指定なら "Toki Dev"。
# 証明書が無い環境ではスキップして警告のみ（CI 等で codesign が無くてもビルドは通す）。
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-Toki Dev}"
if security find-identity -p codesigning -v | grep -q "$CODESIGN_IDENTITY"; then
    codesign --sign "$CODESIGN_IDENTITY" --force --deep --options runtime "$APP_DIR"
    echo "Signed with: $CODESIGN_IDENTITY"
else
    echo "Warning: codesign identity '$CODESIGN_IDENTITY' not found. Skipping signing."
    echo "  -> Keychain prompts will recur after each rebuild."
    echo "  -> Create one in Keychain Access.app: Certificate Assistant > Create a Certificate..."
    echo "     Name: $CODESIGN_IDENTITY / Identity Type: Self Signed Root / Certificate Type: Code Signing"
fi

echo "Built $APP_DIR"
echo "Run: open $APP_DIR"
