# 015 — App Sandbox 対応

参照: `specs/ROADMAP.md` §2 Phase 1A
依存: `specs/015a-xcode-project-migration.md` 完了済み
ステータス: **Sandbox 設定完了 / OAuth 動作検証は spec 016 完了後に持ち越し**

Mac App Store 配布必須の App Sandbox に対応する。Entitlements ファイルを
作成し、最小権限で Toki の全機能が動くことを確認する。

## 1. 目的

- MAS 配布の必須条件 `com.apple.security.app-sandbox = true` を満たす
- 必要最小限の entitlements に絞る（過剰権限申請は審査落ち / 不要なリスク）
- Sandbox 環境下で既存機能（OAuth / Calendar API / Keychain / UserDefaults）の動作確認

## 2. Toki が必要な Entitlements

機能と必要 entitlement の対応：

| 機能 | Entitlement Key | 値 | 必須/任意 |
|---|---|---|---|
| App Sandbox 自体（MAS 必須）| `com.apple.security.app-sandbox` | `true` | **必須** |
| Google Calendar API 通信 | `com.apple.security.network.client` | `true` | **必須** |
| OAuth Loopback サーバ（LoopbackOAuthReceiver）| `com.apple.security.network.server` | `true` | **必須** ⚠️ |
| Keychain アクセス | （app-sandbox + bundle identifier で自動隔離）| – | 不要（自動）|
| UserDefaults | （sandbox 内で自動）| – | 不要（自動）|
| ファイル選択ダイアログ | `com.apple.security.files.user-selected.read-only` | – | 不要（v1.0 未使用）|
| Calendar.app アクセス | `com.apple.security.personal-information.calendars` | – | 不要（Google Calendar API 使用、macOS Calendar.app は使わない）|
| カメラ / マイク / 連絡先 | – | – | 不要 |

### 2.1 `network.server` の必要性（重要）

Toki の OAuth フローは：
1. ブラウザに Google 認証 URL を開く
2. ユーザー認証後、`http://localhost:<port>/callback?code=...` にリダイレクト
3. `LoopbackOAuthReceiver` がローカルで listen して code を受信

→ ローカルで listen するため `network.server` 必須。

MAS 審査で「なぜ server 権限が必要か」を聞かれる可能性あり。Privacy Policy
と Description で「OAuth コールバック受信のみで外部からの接続は受け付けない」
旨を明記しておくと安全。

## 3. 実装手順

### Step 1: Toki.entitlements 作成

`Toki/Toki/Toki.entitlements` に以下を配置（Claude 側で実装）：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
</dict>
</plist>
```

### Step 2: Xcode で App Sandbox capability 追加（ユーザー作業）

1. Xcode で project を開く
2. TARGETS > Toki > **Signing & Capabilities** タブ
3. `+ Capability` → **App Sandbox** を追加
4. App Sandbox の中で以下にチェック：
   - **Network: Outgoing Connections (Client)** ✓
   - **Network: Incoming Connections (Server)** ✓
   - 他はすべて **OFF**
5. 自動で生成 / 更新される `Toki.entitlements` の内容が Step 1 と一致するか確認

### Step 3: scripts/build-app.sh に entitlements 適用

既存 build-app.sh の codesign コマンドに `--entitlements` フラグを追加する。
これで SwiftPM build した .app も Sandbox 適用される（開発時の動作確認用）。

### Step 4: ビルド確認（CLI）

```bash
# Xcode build
xcodebuild -project Toki/Toki.xcodeproj -scheme Toki -configuration Debug build

# SwiftPM build + bundle
./scripts/build-app.sh
```

### Step 5: 動作確認（手動）

Sandbox 環境で以下が動くか確認：

- [ ] アプリ起動（クラッシュしない）
- [ ] Google OAuth サインインフロー
  - [ ] ブラウザが開く（`NSWorkspace.shared.open`）
  - [ ] localhost callback 受信（LoopbackOAuthReceiver）
  - [ ] Keychain に token 保存
- [ ] Calendar イベント取得（network.client）
- [ ] 円形時計に描画
- [ ] 設定変更 → UserDefaults 保存 → 再起動後に復元
- [ ] サインアウト → Keychain クリア
- [ ] 再度サインイン

### Step 6: Console.app でエラー監視

Sandbox 違反は Console.app の sandboxd ログに出る：

```bash
log stream --predicate 'process == "sandboxd"' --info | grep Toki
```

または Console.app で "sandbox" でフィルタ。

## 4. リスク・注意事項

- **Loopback server は審査で質問される可能性**：審査 reject 時の説明文を準備
- **既存の OAuth implementation が Sandbox 環境で動くか不明**：実機検証必須
- **Keychain item の access control**：sandbox 化で過去の token が読めなくなる可能性 → 初回 sandbox 起動時に再ログインが必要かも
- **NSWorkspace.shared.open** は sandbox でも許可されるが、対象 URL によっては制限される
- **DerivedData の古い build を消す**：sandbox 設定変更時はクリーンビルド推奨

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/Toki-*
```

## 5. 完了条件

### 5.1 Sandbox 設定（本 spec で完了）

- [x] `Toki/Toki/Toki.entitlements` 作成
- [x] pbxproj に `CODE_SIGN_ENTITLEMENTS = Toki/Toki.entitlements` 設定（CLI で python 経由）
- [x] `xcodebuild build` 通る
- [x] scripts/build-app.sh に entitlements 適用
- [x] アプリ起動確認（クラッシュなし）
- [x] codesign で entitlements が .app に焼き込まれている確認
- [ ] Xcode で App Sandbox capability 追加（UI 側、ユーザー作業、後で追加でも OK）

### 5.2 OAuth 動作検証（spec 016 完了後に持ち越し）

⚠️ Sandbox 化により `~/.config/toki/oauth.json` が読めなくなり、OAuth フローが
動かなくなる。これは spec 016（OAuth 公開対応）の解決事項。

spec 016 完了後に以下を検証：

- [ ] OAuth サインイン → Calendar 取得 → 表示まで完了
- [ ] 設定保存・読み込み確認
- [ ] Console.app で sandbox 違反が出ないこと

## 5.3 spec 015 単独で発覚した既知の問題

- `~/.config/toki/oauth.json` 読み込み失敗 → メニューが「終了」だけになる
  - → spec 016 で OAuth 設定の取得元を Bundle 内 / PKCE フローに切替で解決
- 中央テキスト「右クリックで接続」の UX 問題（時計を右クリックしても何も起きない）
  - → spec 017（エラーハンドリング強化）で UX 改善

## 6. 次の Phase

- **spec 016**：OAuth 公開対応（client_secret 漏洩対策、PKCE 化）
- **spec 017**：エラーハンドリング強化（UI で見える形に）
- **spec 018**：アクセシビリティ最低限
- **spec 019**：ローカライズ（日英）

これら 4 spec は Phase 1A 完了後に並行着手可能。

## 7. 参照

- `ROADMAP.md` §2 Phase 1A
- [App Sandbox documentation - Apple](https://developer.apple.com/documentation/security/app_sandbox)
- [Entitlements documentation - Apple](https://developer.apple.com/documentation/bundleresources/entitlements)
- 既存 `Sources/Toki/Infrastructure/LoopbackOAuthReceiver.swift`
