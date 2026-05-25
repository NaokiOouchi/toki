# 016 — OAuth 公開対応（PKCE 化）

参照: `specs/ROADMAP.md` §2 Phase 1B
依存: `specs/015-app-sandbox.md` 完了済み
ステータス: **設計確定、実装未着手**

MAS 配布のため OAuth フローを公開対応にする。`client_secret` を完全廃止して
PKCE フロー（RFC 7636）に移行し、`~/.config/toki/oauth.json` の手動配置運用も
廃止する。Sandbox 環境で動く OAuth サインインを実現する。

## 1. 目的

- `client_secret` を **完全廃止**（バイナリ解凍されても安全に）
- `~/.config/toki/oauth.json` 廃止 → **Bundle 内に client_id 埋め込み**
- 既存の Loopback OAuth receiver（Chrome 互換性のため）は維持
- Sandbox 環境で OAuth サインインが動くようにする
- 既存ユーザーの再認証はやむなし（client_id は同じなので Google 側の連携は維持）

## 2. 背景：選択肢の比較と決定

### 2.1 検討した方式

| 方式 | client_secret | UX | Sandbox | Chrome 互換 | 採否 |
|---|---|---|---|---|---|
| **A. PKCE + loopback** | 不要 | デフォルトブラウザ起動 | ✅ | ✅ | **採用** |
| B. ASWebAuthenticationSession + PKCE | 不要 | in-app overlay (Safari) | ✅ | ❌ Chrome cookies 使えない | 不採用（v1.1+ で再検討）|
| C. OAuth Proxy（Cloudflare Workers）| server に隠す | デフォルトブラウザ起動 | ✅ | ✅ | 不採用（infra 運用過剰）|
| D. Device Flow（RFC 8628）| 不要 | ❌ 数字 code 手入力 | ✅ | – | 不採用（UX 悪）|

### 2.2 A 採用の決定理由

- **Chrome ユーザーに優しい**：Toki のターゲット（Google Calendar ユーザー）は Chrome 利用率高い
- 既存 `LoopbackOAuthReceiver` をそのまま流用（実装最小）
- ブラウザ切替パターンは Slack / Notion / Figma 等と同じ標準動線
- Google Cloud Console の Desktop app type OAuth Client もそのまま使える
- `network.server` entitlement は OAuth callback 用と明示すれば審査通過可能

## 3. PKCE フロー概要（RFC 7636）

```
[Toki] code_verifier = 暗号学的乱数 32 bytes
       code_challenge = Base64URL(SHA256(code_verifier))

[Toki] → ブラウザ: GET https://accounts.google.com/o/oauth2/v2/auth
        ?client_id=...
        &redirect_uri=http://localhost:8081/callback
        &response_type=code
        &scope=...
        &state=...
        &code_challenge=<code_challenge>
        &code_challenge_method=S256

[ユーザー] Google で認証 → 認可

[Browser] → localhost:8081/callback?code=<auth_code>&state=...

[Toki] LoopbackOAuthReceiver で受信、state 検証

[Toki] → Google: POST https://oauth2.googleapis.com/token
        grant_type=authorization_code
        &client_id=...
        &code=<auth_code>
        &redirect_uri=http://localhost:8081/callback
        &code_verifier=<code_verifier>   ← client_secret の代わり

[Google] code_verifier を SHA256 して code_challenge と一致確認
         一致すれば token 発行
```

**ポイント**：
- `client_secret` は完全に送信しない（パラメータからも削除）
- `code_verifier` がアプリ内でのみ生成・保持されるため、盗聴やバイナリ解析されてもセッション固有で再利用不能
- 同じ client_id でも、`code_verifier` を持つアプリだけが token を取得可能

## 4. 実装内容

### 4.1 OAuthConfig.swift の改修

**変更前：**
```swift
struct OAuthConfig: Decodable {
    let clientId: String
    let clientSecret: String      // ← 削除
    let redirectURI: String

    static func load() -> OAuthConfig? {
        // ~/.config/toki/oauth.json 読み込み ← 削除
    }
}
```

**変更後：**
```swift
struct OAuthConfig {
    let clientId: String
    let redirectURI: String

    /// Bundle 内に埋め込まれた public client_id を返す。
    /// PKCE 採用により client_secret は廃止、client_id 単独では認証不能なので
    /// バイナリ解析で抜かれても安全。
    static let `default` = OAuthConfig(
        clientId: "<EMBEDDED_CLIENT_ID>",
        redirectURI: "http://localhost:8081/callback"
    )
}
```

`<EMBEDDED_CLIENT_ID>` は実装時に Google Cloud Console で発行された Desktop app
type の client_id を埋め込む。

### 4.2 GoogleOAuthClient.swift の改修

PKCE 関連のメソッド追加：

```swift
import CryptoKit

extension GoogleOAuthClient {
    /// PKCE code_verifier を生成（32 bytes 暗号学的乱数 → Base64URL）
    static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    /// code_verifier から code_challenge を計算（SHA256 → Base64URL）
    static func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }
}

/// Base64URL encoding helper
extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
```

認証 URL 構築時：
- 既存パラメータに `code_challenge` + `code_challenge_method=S256` を追加
- `code_verifier` をセッション中保持（再起動で破棄）

Token 交換時：
- `client_secret` パラメータを削除
- `code_verifier` パラメータを追加

### 4.3 LoopbackOAuthReceiver.swift

**変更なし**。既存のロジックそのまま流用。port 8081 固定、callback path
固定、state 検証ロジックも維持。

### 4.4 ~/.config/toki/oauth.json の扱い

- v1.0 から **完全廃止**（Sandbox で読めない）
- 既存ユーザーには「v1.0 アップデートで OAuth 設定方法が変わりました、
  サインインし直してください」と通知（リリースノートで案内）
- ファイル自体は削除しなくて良い（無視される）

### 4.5 README の更新

`~/.config/toki/oauth.json` を作る手順を削除。代わりに「サインインボタン
を押すだけ」に簡素化。

## 5. ファイル別の変更概要

| ファイル | 変更内容 | 差分行数（概算）|
|---|---|---|
| `Sources/Toki/Infrastructure/OAuthConfig.swift` | client_secret 削除 / load() 廃止 / default 定数追加 | 全面書き直し（30 行 → 15 行）|
| `Sources/Toki/Infrastructure/GoogleOAuthClient.swift` | PKCE メソッド追加 / 認証 URL 構築変更 / token 交換変更 | +50 行 |
| `Sources/Toki/Infrastructure/LoopbackOAuthReceiver.swift` | なし | 0 |
| `Sources/Toki/App/AppDelegate.swift` | `OAuthConfig.load()` → `OAuthConfig.default` 参照に変更 | ~5 行 |
| `Sources/Toki/Composition/ClockViewModel.swift` | 影響なし（OAuth 抽象化されてる）| 0 |
| `README.md` | OAuth 設定手順削除 | 修正 |

## 6. テスト戦略

Domain 層ではないが、純粋関数として以下をテスト可能：

- `generateCodeVerifier()`：32 bytes、URL-safe Base64 形式の検証
- `generateCodeChallenge(from:)`：既知の verifier で期待される challenge が出るか
- RFC 7636 のテストベクトル使用：
  ```
  verifier  = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
  challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
  ```

`Tests/TokiTests/` に新規 test target？  
→ 既存の Domain テストとは分離。`OAuthPKCETests.swift` を追加。

## 7. 移行ガイド（既存ユーザー向け）

v0.x → v1.0 で：
- `~/.config/toki/oauth.json` は読み込まれなくなります（削除して構いません）
- 初回起動時に「Google Calendar 接続」メニューから再認証してください
- Google 側のアプリ連携は同じ client_id なので、再認証は **1 クリックで完了**
  （Google 側の同意画面はスキップされ、Toki が改めて token を取得するだけ）

## 8. リスク・注意事項

- **既存ユーザーの再認証が必要**：避けられない。リリースノートで明示
- **`<EMBEDDED_CLIENT_ID>` の管理**：私的な OAuth Client であり Toki 用に
  Google Cloud Console で作成・管理。漏洩しても PKCE があるので安全だが、
  クォータは共有されるので注意（個人開発の規模なら問題ない）
- **port 8081 が他アプリで使用中の場合**：起動失敗。動的 port 割り当てへの
  移行は別 spec で検討（ただし Google OAuth は redirect_uri 完全一致なので
  動的 port 化は OAuth Client 側で複数 port 登録が必要）
- **Loopback サーバ起動権限（network.server）**：MAS 審査で説明可能にする
  ため、Privacy Policy / Description で「OAuth callback 用のローカル受信のみ」
  と明示

## 9. 完了条件

- [ ] `Sources/Toki/Infrastructure/OAuthConfig.swift` 書き直し
  - [ ] client_secret 削除
  - [ ] load() 廃止
  - [ ] `default` 定数追加（Bundle 内 client_id 埋め込み）
- [ ] `Sources/Toki/Infrastructure/GoogleOAuthClient.swift` 改修
  - [ ] PKCE code_verifier / code_challenge 生成関数追加
  - [ ] 認証 URL に code_challenge 追加
  - [ ] token 交換時に code_verifier 送信、client_secret 削除
- [ ] `Sources/Toki/App/AppDelegate.swift` を `OAuthConfig.default` に更新
- [ ] `Tests/TokiTests/OAuthPKCETests.swift` 追加（RFC 7636 ベクトル検証）
- [ ] `swift build` / `swift test` / `xcodebuild build` 全部通る
- [ ] README から `~/.config/toki/oauth.json` 設定手順削除
- [ ] **動作確認**：Sandbox 環境で OAuth サインイン → Calendar 取得 → 表示
  - これにより spec 015 の完了条件 §5.2 も達成

## 10. 次の Phase

spec 016 完了後、Phase 1 残作業：
- spec 017（エラーハンドリング強化、「右クリックで接続」UX 改善）
- spec 018（アクセシビリティ最低限）
- spec 019（ローカライズ）

これらは並行着手可能。

## 11. 参照

- `ROADMAP.md` §2 Phase 1B
- [RFC 7636: Proof Key for Code Exchange](https://datatracker.ietf.org/doc/html/rfc7636)
- [Google OAuth 2.0 for Desktop Apps](https://developers.google.com/identity/protocols/oauth2/native-app)
- 既存実装：
  - `Sources/Toki/Infrastructure/OAuthConfig.swift`
  - `Sources/Toki/Infrastructure/GoogleOAuthClient.swift`
  - `Sources/Toki/Infrastructure/LoopbackOAuthReceiver.swift`
