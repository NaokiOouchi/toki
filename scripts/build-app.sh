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

# 開発用の証明書で署名。これにより rebuild しても署名が安定し、
# macOS Keychain ACL（OAuth token アクセス権限）が永続化する。
#
# 優先順位（最初に見つかったものを使用）：
#   1. CODESIGN_IDENTITY 環境変数で明示指定された identity
#   2. "Toki Dev"（ユーザー自身が Keychain Access で作成した自己署名）
#   3. 任意の "Apple Development: ..." identity（Xcode サインインで取得済み）
#   4. どれも無ければスキップして警告（CI 等向け）
pick_codesign_identity() {
    if [ -n "${CODESIGN_IDENTITY:-}" ]; then
        echo "$CODESIGN_IDENTITY"
        return
    fi
    if security find-identity -p codesigning -v 2>/dev/null | grep -q "Toki Dev"; then
        echo "Toki Dev"
        return
    fi
    local apple_dev_id
    apple_dev_id=$(security find-identity -p codesigning -v 2>/dev/null \
        | grep -oE '"Apple Development:[^"]*"' \
        | head -1 \
        | sed 's/^"//;s/"$//')
    if [ -n "$apple_dev_id" ]; then
        echo "$apple_dev_id"
        return
    fi
    echo ""
}

CODESIGN_IDENTITY_RESOLVED=$(pick_codesign_identity)
# spec 015: App Sandbox 対応のため entitlements を適用する。
# Xcode 側と同じ entitlements ファイルを共有することで、
# SwiftPM build した .app も Sandbox 環境で動作確認できる。
ENTITLEMENTS_FILE="Toki/Toki/Toki.entitlements"
if [ -n "$CODESIGN_IDENTITY_RESOLVED" ]; then
    if [ -f "$ENTITLEMENTS_FILE" ]; then
        codesign --sign "$CODESIGN_IDENTITY_RESOLVED" --force --deep \
            --options runtime --entitlements "$ENTITLEMENTS_FILE" "$APP_DIR"
        echo "Signed with: $CODESIGN_IDENTITY_RESOLVED (with entitlements)"
    else
        codesign --sign "$CODESIGN_IDENTITY_RESOLVED" --force --deep --options runtime "$APP_DIR"
        echo "Signed with: $CODESIGN_IDENTITY_RESOLVED (no entitlements file found)"
    fi
else
    echo "Warning: no codesigning identity found. Skipping signing."
    echo "  -> Keychain prompts will recur after each rebuild."
    echo "  -> Create one in Keychain Access.app: Certificate Assistant > Create a Certificate..."
    echo "     Name: Toki Dev / Identity Type: Self Signed Root / Certificate Type: Code Signing"
fi

echo "Built $APP_DIR"
echo "Run: open $APP_DIR"
