# 016 — OAuth 公開対応（iOS Client + ASWebAuthenticationSession）

参照: `specs/ROADMAP.md` §2 Phase 1B
依存: `specs/015-app-sandbox.md` 完了済み（一部後方互換更新あり）
ステータス: **設計確定、実装未着手**

MAS 配布のため OAuth フローを公開対応にする。`client_secret` を完全廃止、
`~/.config/toki/oauth.json` 廃止、`LoopbackOAuthReceiver` 廃止、`network.server`
entitlement 削除し、iOS OAuth Client + custom URL scheme + ASWebAuthenticationSession
の業界標準パターンに移行する。

## 1. 目的

- **`client_secret` を完全廃止**（バイナリ解凍されても安全に）
- `~/.config/toki/oauth.json` 廃止 → **Bundle 内に client_id のみ埋め込み**
- `LoopbackOAuthReceiver` 廃止 → ASWebAuthenticationSession + custom scheme
- `network.server` entitlement 削除 → MAS 審査リスク減
- Sandbox 環境で OAuth サインインが動くようにする
- 既存ユーザーは新 client_id への再認証が必要（client_id 自体が変わるため）

## 2. 背景：選択肢の比較と最終決定

### 2.1 検討した全方式（実コード検証ベース）

| 方式 | client_secret | redirect | Chrome 互換 | infra | 実コード事例 | 採否 |
|---|---|---|---|---|---|---|
| Desktop + Loopback + PKCE only | – | – | – | – | **不可能** | × |
| Web app + Loopback + PKCE only | – | – | – | – | **不可能**（Web app も secret 必須） | × |
| iOS + Loopback + PKCE only | – | – | – | – | **不可能**（iOS は custom scheme only） | × |
| A. Desktop + Loopback + secret + PKCE | 必要 | loopback | ✅ | なし | AppAuth 公式サンプル only | 不採用 |
| B. iOS + Custom scheme + AppAuth + secret | 必要 | custom | ✅（custom scheme で Chrome 不具合回避）| なし | **MeetingBar**（MAS）| 不採用 |
| **C. iOS + Custom scheme + PKCE only + secret なし** | **不要** | custom | ✅ | なし | **Raycast 公式**サンプル | **採用** |
| D. Cloudflare Workers proxy | proxy 管理 | loopback | ✅ | あり | macOS OSS 0 件 | 不採用 |

### 2.2 C 採用の決定理由

- **`client_secret` 完全廃止**（Qiita 記事等の懸念解消、business logic からも消える）
- **`network.server` entitlement 削除**（MAS 審査リスク減）
- **Chrome 不具合は custom scheme で回避**（Apple Developer Forum thread/725547 で Apple エンジニアが示唆）
- **Raycast 公式サンプル**で実コード事例あり（Toki と類似の OSS Mac アプリ）
- ブラウザタブ汚染なし、認証専用ウィンドウが自動で閉じる → **アプリ離脱なしの UX**
- Loopback receiver の自前実装（150 行）を削除でコードシンプル化

### 2.3 捨てるもの

- 既存 `LoopbackOAuthReceiver.swift`
- `network.server` entitlement
- `~/.config/toki/oauth.json` の運用フロー（個人開発時のハック）

### 2.4 トレードオフ

- **Chrome の Google ログイン状態は使えない**（Safari の cookies を使う）
  - ただし iCloud Keychain で Auto-fill 可能、Safari に Google ログイン済み Mac ユーザーは多い
  - 初回未ログインユーザーは数十秒の手入力、以後は Safari cookies で 1 クリック
- 既存ユーザーの再認証が必要（新 client_id への移行）

## 3. ASWebAuthenticationSession の挙動（macOS）

```
[Toki menu]「Google Calendar 接続」
   ↓
[System dialog] "Toki" wants to use "google.com" to Sign In ─ [Cancel] [Continue]
   ↓
[認証専用ウィンドウ] accounts.google.com を開く（Safari engine、別ウィンドウ）
   ↓
[Google] ログイン + 同意（既ログイン or iCloud Keychain で Auto-fill）
   ↓
[Toki が受信] custom scheme com.googleusercontent.apps.<id>:/oauthredirect?code=...
   ↓
[認証ウィンドウ自動で閉じる、Toki にフォーカス戻る]
   ↓
[Toki] code + verifier → token 交換 → Keychain 保存
```

## 4. PKCE フロー（既存実装流用、`client_secret` 削除）

```
[Toki] code_verifier = 暗号学的乱数 32 bytes
       code_challenge = Base64URL(SHA256(code_verifier))

[ASWebAuth] → GET https://accounts.google.com/o/oauth2/v2/auth
        ?client_id=<EMBEDDED_IOS_CLIENT_ID>
        &redirect_uri=com.googleusercontent.apps.<reverse>:/oauthredirect
        &response_type=code
        &scope=https://www.googleapis.com/auth/calendar.readonly
        &state=<nonce>
        &code_challenge=<challenge>
        &code_challenge_method=S256

[ユーザー] Google で認証 → 同意

[Browser] → custom scheme redirect: com.googleusercontent.apps.<rev>:/oauthredirect?code=<auth_code>&state=<nonce>

[Toki] ASWebAuthenticationSession callback で受信、state 検証

[Toki] → POST https://oauth2.googleapis.com/token
        grant_type=authorization_code
        &client_id=<EMBEDDED_IOS_CLIENT_ID>
        &code=<auth_code>
        &redirect_uri=com.googleusercontent.apps.<rev>:/oauthredirect
        &code_verifier=<code_verifier>
        # ※ client_secret は送信しない！

[Google] code_verifier を SHA256 して code_challenge と一致確認
         一致すれば token 発行（iOS client は secret 不要）
```

## 5. ユーザー作業（実装着手の前提）

### 5.1 Google Cloud Console で iOS OAuth Client 作成

1. https://console.cloud.google.com/apis/credentials にアクセス
2. 既存「Toki Desktop」とは別に **新規 OAuth クライアント ID 作成**
3. アプリケーションの種類: **iOS**
4. 名前: `Toki Mac App`（任意の識別名）
5. **Bundle ID**: `jp.co.noouchi.toki`
6. App Store ID: **空欄**（v1.0 リリース後に追加可能）
7. Team ID: Apple Developer Team ID（registry でアプリ発行されない、紐付けのみ）
8. 「作成」をクリック
9. 表示される **iOS URL Scheme**（例：`com.googleusercontent.apps.123456789-xxxxxx`）と **クライアント ID**（例：`123456789-xxxxxx.apps.googleusercontent.com`）を控える

### 5.2 既存 Desktop OAuth Client は破棄して OK

新方式に移行後、既存 Desktop type は使わないので削除しても問題なし。
ただし、しばらく残しておけば既存ユーザーの旧版 Toki が動き続ける（互換性のため）。

### 5.3 OAuth Consent Screen の更新

- アプリ名: `Toki - Circle Calendar Clock`
- ユーザーサポートメール: 開発者メール
- アプリのロゴ: 後で App Icon 完成後に登録
- 認証情報のドメイン: 空欄でも OK（Testing モードなら）
- スコープ: `.../auth/calendar.readonly` のみ
- テストユーザー: 自分のメールアドレス + 必要に応じて

## 6. 実装内容

### 6.1 削除するファイル

- `Sources/Toki/Infrastructure/LoopbackOAuthReceiver.swift` — 全削除

### 6.2 改修するファイル

#### `Sources/Toki/Infrastructure/OAuthConfig.swift`

```swift
import Foundation

/// Google OAuth Client（iOS type）の設定。
/// PKCE 採用により client_secret は不要、Bundle 内に client_id のみ埋め込み。
/// iOS client は client_id 単独では認証不能（PKCE の code_verifier が必要）なので、
/// バイナリ解析されても安全。
struct OAuthConfig {
    let clientId: String
    /// custom URL scheme（reverse-DNS 形式）
    /// Info.plist の CFBundleURLTypes に同 scheme を登録すること。
    let redirectURI: String

    static let `default` = OAuthConfig(
        clientId: "<EMBEDDED_IOS_CLIENT_ID>",  // 例: 123456789-xxxxxx.apps.googleusercontent.com
        redirectURI: "<EMBEDDED_IOS_URL_SCHEME>:/oauthredirect"  // 例: com.googleusercontent.apps.123456789-xxxxxx:/oauthredirect
    )
}
```

#### `Sources/Toki/Infrastructure/GoogleOAuthClient.swift`

主な変更：
- `init` の `receiver` 引数を削除（LoopbackOAuthReceiver 不要）
- `beginAuthorization()` を `ASWebAuthenticationSession` ベースに書き換え
- `exchange()` から `client_secret` 削除
- `refresh()` から `client_secret` 削除
- `port(from:)` ヘルパー削除

ASWebAuthenticationSession 統合：
- `AuthenticationServices` framework import
- `ASWebAuthenticationPresentationContextProviding` 実装
- `ASWebAuthenticationSession` を `callbackURLScheme:` 指定で起動
- callback URL から `code` と `state` を抽出

### 6.3 追加するファイル

- なし（必要な機能は既存ファイルの改修と Info.plist で完結）

### 6.4 Info.plist 更新

Custom URL scheme を登録：

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>jp.co.noouchi.toki.oauth</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.googleusercontent.apps.123456789-xxxxxx</string>
        </array>
    </dict>
</array>
```

### 6.5 Entitlements 更新

`Toki/Toki/Toki.entitlements` から削除：

- `com.apple.security.network.server` ← 削除（LoopbackOAuthReceiver 廃止のため不要）

残す：
- `com.apple.security.app-sandbox`
- `com.apple.security.network.client`（Google Calendar API 通信用）

### 6.6 AppDelegate.swift の調整

- `LoopbackOAuthReceiver` の生成・依存注入を削除
- `GoogleOAuthClient` の init 引数から `receiver` 削除

## 7. テスト戦略

### 7.1 自動テスト

PKCE の純粋関数部分は既に動いてる（既存実装流用）：
- `code_verifier` 生成（32 byte 乱数 → Base64URL）
- `code_challenge` 生成（SHA256 → Base64URL）

新規追加テスト：
- `Tests/TokiTests/OAuthPKCETests.swift`
  - RFC 7636 のテストベクトル検証：
    ```
    verifier  = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
    ```

### 7.2 手動テスト

ASWebAuthenticationSession 統合は手動で確認：

- [ ] 起動 → メニューに「Google Calendar 接続」表示される
- [ ] クリックで Apple システム同意ダイアログ表示
- [ ] Continue で認証ウィンドウ表示
- [ ] Google ログイン + 同意成功
- [ ] 認証ウィンドウ自動で閉じる
- [ ] Calendar 取得・表示成功
- [ ] サインアウト → Keychain クリア
- [ ] 再サインイン成功
- [ ] アプリ再起動後も認証維持（refresh_token 動作確認）
- [ ] **Console.app で sandbox 違反が出ないこと**

## 8. 移行ガイド（既存ユーザー向け）

v0.x → v1.0 で：

- **client_id が変わるため、再認証が必須**
- 旧 `~/.config/toki/oauth.json` は無視される（削除して構いません）
- 起動後「Google Calendar 接続」メニューから再認証してください
- 認証フローが変わります：
  - **旧**：デフォルトブラウザが開く → localhost callback
  - **新**：Apple 提供の認証ウィンドウが浮く → 自動で閉じる
- Google 側のアプリ連携は新 client_id として認識される
  - 旧 Toki Desktop の連携は不要になったら手動で revoke 可能（https://myaccount.google.com/permissions ）

## 9. リスク・注意事項

- **既存ユーザーの再認証**：避けられない、リリースノートで明示
- **`<EMBEDDED_IOS_CLIENT_ID>` の管理**：Toki 用 iOS OAuth Client。漏洩しても PKCE で安全だが、クォータは共有
- **Safari 未ログインユーザー UX**：初回は手入力、以後は cookies で OK
- **OAuth Consent Screen の Testing モード制約**：累計 100 user 上限、超えたら Verification 申請必要
- **Verification 申請**：独自ドメイン必要、GitHub Pages では不可。v1.0 リリース時点では Testing で運用、Phase 5 後に独自ドメイン取得 + 申請を別 spec で

## 10. 完了条件

### 10.1 ユーザー側（Phase 0 並行）

- [ ] Google Cloud Console で iOS OAuth Client 作成
- [ ] client_id と URL scheme を確認

### 10.2 実装

- [ ] `Sources/Toki/Infrastructure/LoopbackOAuthReceiver.swift` 削除
- [ ] `Sources/Toki/Infrastructure/OAuthConfig.swift` 書き直し（iOS type 用、`default` 定数追加）
- [ ] `Sources/Toki/Infrastructure/GoogleOAuthClient.swift` 改修
  - [ ] ASWebAuthenticationSession 統合
  - [ ] client_secret パラメータ削除（exchange + refresh）
  - [ ] receiver 引数削除
- [ ] `Sources/Toki/App/AppDelegate.swift` 調整（receiver 依存削除）
- [ ] `Resources/Info.plist` に CFBundleURLTypes 追加
- [ ] `Toki/Toki/Toki.entitlements` から `network.server` 削除
- [ ] `Tests/TokiTests/OAuthPKCETests.swift` 追加（RFC 7636 テストベクトル）
- [ ] `swift build` / `swift test` / `xcodebuild build` 全部通る
- [ ] README から `~/.config/toki/oauth.json` 設定手順削除

### 10.3 動作確認

- [ ] アプリ起動 → 「Google Calendar 接続」表示
- [ ] ASWebAuth フローで認証成功
- [ ] Calendar 取得 → 表示成功
- [ ] サインアウト → 再認証成功
- [ ] Console.app で sandbox 違反なし

## 11. 関連 spec の更新

- **spec 015**：完了条件 §5.2「OAuth 動作検証」は本 spec 完了で達成
  - `network.server` entitlement 削除を反映（spec 015 のドキュメントも更新）

## 12. 次の Phase

spec 016 完了後、Phase 1 残作業：

- spec 017（エラーハンドリング強化、「右クリックで接続」UX 改善）
- spec 018（アクセシビリティ最低限）
- spec 019（ローカライズ）

これらは並行着手可能。

## 13. 参照

- `ROADMAP.md` §2 Phase 1B
- [RFC 7636: Proof Key for Code Exchange](https://datatracker.ietf.org/doc/html/rfc7636)
- [RFC 8252: OAuth 2.0 for Native Apps](https://datatracker.ietf.org/doc/html/rfc8252)
- [Google OAuth 2.0 for Mobile & Desktop Apps](https://developers.google.com/identity/protocols/oauth2/native-app)
- [ASWebAuthenticationSession - Apple Developer](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)
- [Authenticating a User Through a Web Service](https://developer.apple.com/documentation/authenticationservices/authenticating-a-user-through-a-web-service)
- 参考実装：
  - [Raycast 公式 Google OAuth サンプル](https://github.com/raycast/extensions/blob/main/examples/api-examples/src/oauth/google.tsx)
  - [MeetingBar の AppAuth 統合](https://github.com/leits/MeetingBar)
- 既存実装（改修対象）：
  - `Sources/Toki/Infrastructure/OAuthConfig.swift`
  - `Sources/Toki/Infrastructure/GoogleOAuthClient.swift`
  - `Sources/Toki/Infrastructure/LoopbackOAuthReceiver.swift`（削除予定）
