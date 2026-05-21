# 005 — Google Calendar API 経由の event detail URL 取得 技術プラン

`specs/005-google-calendar-api.md` を技術プランに展開したもの。`/tasks` で atomic task に分解する元となる。

## 0. 確定済み設計判断

ユーザーとの合意事項：

1. **Google Calendar API 経由で `htmlLink` を取得**して確実な detail URL を実現
2. **OAuth + REST を自前実装**（外部ライブラリ追加禁止）、URLSession + Security Framework + Network framework
3. **OAuth は 1 アカウント分のみ**保持（複数アカウントは Phase 3）
4. **client_id / client_secret は `~/.config/toki/oauth.json`** から読む（設定 UI は MVP 範囲外）
5. **redirect_uri は loopback `http://localhost:8081/callback`** 固定
6. **token 保存は macOS Keychain**（Security Framework 直叩き）
7. **API は `events.list?iCalUID=<uid>&singleEvents=true`** を全 calendar に対して並列実行
8. **キャッシュは in-memory のみ**（`EKEventStoreChanged` 通知時に clear）
9. **spec 004 の `googleEventDetailURL` / `normalizeGoogleUID` / `utcOccurrenceDateString` は削除**、`googleCalendarDayURL` は fallback として維持
10. **Domain `Event.webURL: URL?`** を追加、`RenderableEvent.webURL` で伝播
11. **API 失敗は silent fail**（log のみ）、clock 表示は止めない
12. **OAuth 未接続時 UX** は MVP では何も表示しない、右クリックメニューで「Google Calendar 接続」のみ
13. **PKCE 採用**（S256、CryptoKit で実装）で client_secret 漏洩リスクを低減

## 1. Requirements restatement

spec 004 で reverse-engineered eid 経路を実装したが、Workspace+Exchange ハイブリッド event（ENEOS 等）で破綻することが実機検証で判明。本 iteration では：

1. **Google Calendar API の `events.list?iCalUID=<uid>`** を呼んで `htmlLink` を取得し、確実な detail URL を実現
2. **OAuth 2.0 (Loopback IP) + REST** を URLSession + Security Framework + Network framework で自前実装
3. **Domain `Event.webURL: URL?` を追加**、`RenderableEvent` で UI まで伝播、`ClockViewModel.handleArcTap` を `webURL` ベースに簡素化
4. **spec 004 の eid helper 3 個を削除**、`googleCalendarDayURL` は fallback として維持
5. 既存 Domain テスト 36 ケースは pass を維持（ヘルパに `webURL: URL? = nil` 引数追加で吸収）

## 2. Open Questions — 解決済み

spec 005 の 13 項目すべて [CONFIDENT] で着手可能：

### OAuth 設計
1. **client_id / client_secret の保管** → `~/.config/toki/oauth.json`（設定 UI は MVP 範囲外）
2. **redirect_uri** → `http://localhost:8081/callback` 固定、競合時は log + 接続失敗で抜ける
3. **token 保存先** → Keychain Security Framework 直叩き、service `dev.pokotech.Toki`
4. **OAuth フロー中の UX** → Toki 通常表示のまま、ブラウザ consent → loopback 受領、完了/失敗ともに log のみ

### API 呼び出し設計
5. **events.list vs events.get** → `events.list?iCalUID=<uid>&singleEvents=true`（1 calendar 1 リクエスト）
6. **多 calendar 跨ぎ** → `calendars.list` で全 calendar 取得 → 各 calendar に並列で events.list
7. **レート制限** → 個人利用なら問題なし、429 時のみ exponential backoff（最大 3 回）
8. **キャッシュ** → in-memory dict、`EKEventStoreChanged` 通知時に clear

### Domain / UI 影響
9. **webURL の nil 判定場所** → ViewModel `handleArcTap` 内
10. **OAuth 未接続時 UX** → MVP は fallback 動作のみ、視覚 indicator なし
11. **複数アカウント対応** → Phase 3 行き

### CLAUDE.md 抵触
12. **外部ライブラリ** → 自前実装で抵触なし
13. **設定 UI** → JSON file 経由で MVP

## 3. ファイル別変更計画

### 新規（5 ファイル）

| パス | 概要 | 想定行数 | 公開 API |
|---|---|---|---|
| `Sources/Toki/Infrastructure/OAuthConfig.swift` | `~/.config/toki/oauth.json` 読み込み | 40 | `OAuthConfig.load() -> OAuthConfig?` |
| `Sources/Toki/Infrastructure/KeychainStore.swift` | Security Framework wrapper | 70 | `set` / `get` / `delete` |
| `Sources/Toki/Infrastructure/LoopbackOAuthReceiver.swift` | Network.framework loopback HTTP server | 90 | `waitForCode(port:expectedState:)` |
| `Sources/Toki/Infrastructure/GoogleOAuthClient.swift` | consent / token 交換 / refresh / revoke | 180 | `beginAuthorization()` / `getValidAccessToken()` / `revoke()` / `isAuthorized` |
| `Sources/Toki/Infrastructure/GoogleCalendarAPI.swift` | calendars.list + events.list で htmlLink 取得 | 130 | `fetchHTMLLinks(forICalUIDs:)` |

### 編集

| パス | 変更概要 | 想定差分 |
|---|---|---|
| `Sources/Toki/Domain/Event.swift` | `webURL: URL?` を struct + init に追加 | +3/-1 |
| `Sources/Toki/Domain/DayTimeline.swift` | `clip()` で `webURL: event.webURL` を継承 | +1 |
| `Sources/Toki/Infrastructure/EventKitGateway.swift` | `googleAPI` 注入、`fetchTodayTimeline` 拡張、cache 追加 | +50/-2 |
| `Sources/Toki/UI/RenderableEvent.swift` | `webURL: URL?` 追加 | +3 |
| `Sources/Toki/Composition/ClockViewModel.swift` | spec 004 helper 削除、`handleArcTap` 書き換え、`canvasEvents` で webURL 伝播 | +10/-65 |
| `Sources/Toki/App/AppDelegate.swift` | OAuth 組み立て + 右クリックメニュー動的構築 | +35/-3 |
| `Tests/TokiTests/EventTests.swift` / `EventStatusTests.swift` / `DayTimelineTests.swift` | `makeEvent` に `webURL: URL? = nil` 引数追加 | +2/-1 each |
| `SPEC.md`（任意） | クリック挙動と OAuth フローを整合 | +15/-5 |

## 4. OAuth フロー詳細

### ライフサイクル
1. アプリ起動時に `OAuthConfig.load()`、nil なら oauthClient = nil（接続メニュー非表示）
2. consent URL 生成（PKCE、state nonce）→ `NSWorkspace.shared.open(_:)`
3. `LoopbackOAuthReceiver.waitForCode(port: 8081, expectedState:)` で待つ
4. code を `completeAuthorization(code:)` で token に交換
5. access_token / refresh_token / expiry を Keychain 保存
6. 以降は `getValidAccessToken()` で expiry チェック → 切れていれば自動 refresh

### consent URL
```
https://accounts.google.com/o/oauth2/v2/auth
  ?client_id=<client_id>
  &redirect_uri=http://localhost:8081/callback
  &response_type=code
  &scope=https://www.googleapis.com/auth/calendar.readonly
  &access_type=offline
  &prompt=consent
  &state=<nonce>
  &code_challenge=<S256(verifier)>
  &code_challenge_method=S256
```

### token 交換 POST
```
POST https://oauth2.googleapis.com/token
client_id, client_secret, code, redirect_uri, grant_type=authorization_code, code_verifier
```

### refresh
```
POST https://oauth2.googleapis.com/token
client_id, client_secret, refresh_token, grant_type=refresh_token
```

### revoke
```
POST https://oauth2.googleapis.com/revoke?token=<refresh_token>
```
revoke 成功時に Keychain クリア。

### PKCE
- `code_verifier`：64 byte ランダム → base64url
- `code_challenge`：SHA-256(verifier) を base64url（CryptoKit `SHA256`）

### エラー時 retry
- 401 → refresh → 1 回リトライ。refresh も 401 → Keychain クリア、未接続状態へ
- 429 → exponential backoff 最大 3 回
- ネットワークエラー → silent fail

## 5. API 呼び出し詳細

### 全体フロー
```
fetchHTMLLinks(forICalUIDs: ["uid1", "uid2", ...])
  → 1. getValidAccessToken()
  → 2. GET /calendarList → calendar.id 配列
  → 3. withTaskGroup で各 uid を並列処理：
        for cal in calendars (sequential or async let):
          GET /calendars/<cal_id>/events?iCalUID=<uid>&singleEvents=true
        最初に htmlLink を返した結果を採用
  → 4. [String: URL] map 返却
```

### events.list レスポンス
```json
{
  "items": [
    { "id": "...", "iCalUID": "...", "htmlLink": "https://www.google.com/calendar/event?eid=..." }
  ]
}
```

### エラーハンドリング
- 401 → token refresh → 1 度リトライ（`getValidAccessToken` 内で）
- 404 → skip その calendar
- 5xx → backoff retry 1 回
- それ以外 → log + nil（map に該当 key なし）

## 6. Infrastructure 層詳細

### 6.1 `KeychainStore.swift`（70 行）
```swift
final class KeychainStore {
    private let service: String
    init(service: String = "dev.pokotech.Toki")
    func set(_ value: String, forKey key: String) throws
    func get(_ key: String) -> String?
    func delete(_ key: String) throws
}
```
- `kSecClass = kSecClassGenericPassword`
- service = `dev.pokotech.Toki`、account = key（`oauth.access_token` 等）

### 6.2 `OAuthConfig.swift`（40 行）
```swift
struct OAuthConfig: Decodable {
    let client_id: String
    let client_secret: String
    let redirect_uri: String
    static func load() -> OAuthConfig?
}
```
- 形式：`{ "client_id": "...", "client_secret": "...", "redirect_uri": "http://localhost:8081/callback" }`
- ファイルなし → nil

### 6.3 `LoopbackOAuthReceiver.swift`（90 行）
```swift
final class LoopbackOAuthReceiver {
    func waitForCode(port: UInt16, expectedState: String) async throws -> String
}
```
- `NWListener` で TCP listen → HTTP request line をパース
- `/callback?code=...&state=...` から `code` 抽出、`state` 検証
- 成功時 HTTP 200 + 「接続完了」HTML、エラー時 HTTP 400
- 1 接続で listener 停止

### 6.4 `GoogleOAuthClient.swift`（180 行）
```swift
final class GoogleOAuthClient {
    var isAuthorized: Bool { keychain.get("oauth.refresh_token") != nil }
    func beginAuthorization() async throws
    func getValidAccessToken() async throws -> String
    func revoke() async throws
    // private: exchange, refresh, makeConsentURL, makeCodeVerifier, codeChallenge, makeNonce
}
```

### 6.5 `GoogleCalendarAPI.swift`（130 行）
```swift
final class GoogleCalendarAPI {
    func fetchHTMLLinks(forICalUIDs uids: [String]) async throws -> [String: URL]
    // private: fetchCalendarIds, findHTMLLink
}
```

## 7. EventKitGateway 詳細

### 拡張プロパティ
```swift
final class EventKitGateway {
    private let googleAPI: GoogleCalendarAPI?  // 新規
    private var htmlLinkCache: [String: URL] = [:]  // 新規

    init(calendar: Calendar = .current, googleAPI: GoogleCalendarAPI? = nil)
}
```

### `fetchTodayTimeline()` 拡張
1. EKEvent 配列取得（既存）
2. `convert(_:)` で Event 配列に変換（webURL = nil で初期化）
3. **新規**：`@google.com` を含む event の iCalUID を抽出、cache 未 hit のみ抽出
4. **新規**：`googleAPI?.fetchHTMLLinks(forICalUIDs:)` で取得、cache に格納
5. **新規**：webURL を埋め込んだ Event を再生成
6. `DayTimeline.make` に渡す（既存）

### cache invalidation
`start()` 内の `EKEventStoreChanged` sink で `htmlLinkCache.removeAll()` を追加。

### 設計判断
- API 失敗は silent（log + clock 表示維持）
- googleAPI = nil なら旧挙動（webURL = nil のまま）

## 8. Composition 層詳細

### `canvasEvents` で webURL 伝播
```swift
RenderableEvent(
    // 既存
    calendarTitle: ev.calendarTitle,
    webURL: ev.webURL   // 新規
)
```

### `handleArcTap` 簡素化
```swift
func handleArcTap(at point: CGPoint, geometry: ClockGeometry) {
    guard let event = hitTest(point: point, events: canvasEvents, geometry: geometry) else { return }
    hoveredTooltip = nil
    let url: URL
    if let webURL = event.webURL {
        url = webURL
    } else {
        guard let dayURL = URL(string: Self.googleCalendarDayURL(for: event.start, calendar: calendar)) else { return }
        url = dayURL
    }
    NSWorkspace.shared.open(url)
}
```

### spec 004 helper 削除
削除：`calendarURL(for:calendar:)` / `googleEventDetailURL(for:)` / `normalizeGoogleUID(_:)` / `utcOccurrenceDateString(_:)`
維持：`googleCalendarDayURL(for:calendar:)`（fallback）

## 9. App 層詳細

### 依存組み立て
```swift
let oauthClient = OAuthConfig.load().map { config in
    GoogleOAuthClient(config: config, keychain: KeychainStore(), receiver: LoopbackOAuthReceiver())
}
let googleAPI = oauthClient.map { GoogleCalendarAPI(oauth: $0) }
let gw = EventKitGateway(googleAPI: googleAPI)
```

### 右クリックメニュー動的構築
```swift
if let oauth = oauthClient {
    if oauth.isAuthorized {
        menu.addItem(... "Google Calendar 切断" ...)
    } else {
        menu.addItem(... "Google Calendar 接続" ...)
    }
    menu.addItem(NSMenuItem.separator())
}
menu.addItem(... "Toki を終了" ...)
```
- `oauthClient == nil`（config なし）→ 接続項目すら出さない

## 10. 実装フェーズ順序

11 タスク、順序依存あり：

### Phase 1: Domain 拡張
1. **`feat(domain): Event に webURL を追加`**：Event + DayTimeline.clip + テスト 3 ファイル更新

### Phase 2: OAuth 基盤
2. **`feat(infra): KeychainStore 実装`**：Security Framework wrapper
3. **`feat(infra): OAuthConfig 実装`**：JSON 読み込み
4. **`feat(infra): LoopbackOAuthReceiver 実装`**：Network.framework HTTP server
5. **`feat(infra): GoogleOAuthClient 実装`**：consent / PKCE / token 交換 / refresh / revoke

### Phase 3: API 層
6. **`feat(infra): GoogleCalendarAPI 実装`**：calendars.list + events.list 並列

### Phase 4: Gateway / UI 統合
7. **`feat(infra): EventKitGateway に API 連携を組み込み`**：googleAPI 注入 + webURL 詰めなおし + cache
8. **`feat(ui): RenderableEvent に webURL を追加`**：UI 層伝播
9. **`refactor(composition): spec 004 helper 削除 + handleArcTap を webURL ベースに書き換え`**

### Phase 5: App メニュー
10. **`feat(app): AppDelegate に Google Calendar 接続/切断メニュー追加`**：動的メニュー構築

### Phase 6: ドキュメント（任意）
11. **`docs(spec): SPEC.md を spec 005 整合に更新`**

各タスクの完了条件は `swift build` + `swift test`（36 ケース全 pass）+ 手動検証（必要な場合）。

## 11. リスク

| # | リスク | 重大度 | 緩和策 |
|---|---|---|---|
| R1 | OAuth client_id 未配置 | LOW | `oauthClient == nil` で接続メニュー非表示、ドキュメントで案内 |
| R2 | ネットワーク/API 失敗 | MED | silent fail（log + webURL = nil）、clock 表示維持 |
| R3 | Keychain アクセス権限拒否 | LOW | エラー log、isAuthorized = false で fallback 動作 |
| R4 | loopback ポート 8081 競合 | LOW | NWListener bind 失敗を throw、log で通知 |
| R5 | access_token expiry 判定誤差 | LOW | 60 秒マージンで早めに refresh |
| R6 | Workspace event の iCalUID 検索精度 | **MED** | Task 6 完了時に手動検証、events.list が Workspace event を返すか確認必須 |
| R7 | Domain テスト 36 ケース影響 | LOW | ヘルパに `webURL: URL? = nil` 引数追加で吸収 |
| R8 | Equatable 影響 | LOW | id ベース維持 |
| R9 | ファイル長 < 400 行 | LOW | GoogleOAuthClient (180) / GoogleCalendarAPI (130) で十分余裕 |
| R10 | 関数長 < 50 行 | LOW | helper 分割で対応 |
| R11 | protocol 切らない | LOW | final class 単独、テストモック不要 |
| R12 | client_secret 漏洩 | LOW | PKCE 採用でリスク低減、Keychain 保存はせず JSON 配置はユーザー責任 |
| R13 | state nonce 検証漏れ | LOW | LoopbackOAuthReceiver で必ず検証、不一致は throw |
| R14 | refresh_token 漏洩 | LOW | Keychain 保存、OS 管理の ACL |

## 12. テスト方針

### 自動テスト
- Domain 36 ケース全 pass 維持（ヘルパ引数追加で吸収）
- 新規 Domain テスト：不要（webURL は値伝播のみ）

### 手動チェックリスト（Task 10 完了時）
1. OAuth 未設定時：接続項目非表示、終了のみ
2. OAuth 設定済・未接続：「接続」項目表示
3. 接続フロー：consent → loopback 受領 → Keychain 保存
4. 接続後：「切断」項目に変わる
5. Google event クリック → ブラウザで detail（Workspace event も OK）
6. 非 Google event → 今日のビュー fallback
7. ネットワーク切断時 → fallback、クラッシュなし
8. 1 時間放置後クリック → 自動 refresh → detail
9. 切断 → Keychain クリア → 次は fallback
10. アプリ再起動 → 接続状態が維持
11. EKEventStoreChanged 発火 → cache クリア → 再 fetch
12. 既存挙動（時計 / ツールチップ / 中央 3 行 / 次の予定 / メニュー）に影響なし

## 13. Out of scope

spec 005 §Non-goals 再掲（やらない項目）：

- 全 event の API 取得
- イベント編集機能
- 複数 Google アカウント並列対応（Phase 3）
- フル設定 UI（Phase 3）
- 非 Google event の web 詳細 URL（Outlook / iCloud）
- Google Tasks / その他 Google サービス
- 永続キャッシュ
- GoogleSignIn / GoogleAPIClientForREST 等 SDK 採用
- `calendar.readonly` 以外の scope
- OAuth client_id の hard-code 配布

## 参考ファイル

- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/specs/005-google-calendar-api.md`
- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/CLAUDE.md`
- 参考 plan：`specs/003-hover-tooltip-and-browser-plan.md`、`specs/004-event-detail-and-tooltip-flip-plan.md`

次のステップ：`/tasks 005-google-calendar-api` で atomic task ファイル化 → fresh subagent で 1 commit ずつ実装。OAuth Client は Google Cloud Console でユーザーが事前作成。
