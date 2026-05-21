# 005 — google-calendar-api: Tasks

参照: `specs/005-google-calendar-api.md` / `specs/005-google-calendar-api-plan.md`

合計: **11 tasks**

実装順序：上から順に。各 task は fresh subagent に渡して 1 commit ずつ。

新規 Infrastructure 5 ファイル + 既存 Domain / Infrastructure / UI / Composition / App / Tests 編集。

## ユーザー側の前提作業

実装前に Google Cloud Console で OAuth Client を作成し、`~/.config/toki/oauth.json` を配置：

```json
{
  "client_id": "...",
  "client_secret": "...",
  "redirect_uri": "http://localhost:8081/callback"
}
```

詳細は spec 005 plan §4 を参照。

---

## Task 1: Event に webURL を追加

**Commit**: `feat(domain): Event に webURL を追加`

**目的**: Domain `Event` に `webURL: URL?` を追加し、Google Calendar API で取得した `htmlLink` を Infrastructure から Composition まで通せるようにする。

**コンテキスト**:
- 参照: spec 005 §AC「Domain 影響」、plan §4
- 前提: 既存 `Event` は id / title / start / end / calendarColor / externalIdentifier / calendarTitle
- 不変条件は変えない（既存：`!id.isEmpty`、`start < end`）
- `webURL` は **Optional（`URL?`）**、nil は非 Google event or API 取得失敗を意味する
- `Equatable` は **id ベース維持**

**実装内容**:

### ファイル 1: `Sources/Toki/Domain/Event.swift`（編集）

`calendarTitle` の直後に `webURL: URL?` を追加し、init signature の末尾にデフォルト引数 `webURL: URL? = nil` を追加：

```swift
struct Event: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let calendarColor: CGColor
    let externalIdentifier: String?
    let calendarTitle: String
    /// Google Calendar API で取得した event detail URL（`htmlLink`）。
    /// 非 Google event / API 取得失敗の場合は nil。
    let webURL: URL?

    init?(id: String, title: String, start: Date, end: Date,
          calendarColor: CGColor, externalIdentifier: String?,
          calendarTitle: String, webURL: URL? = nil) {
        guard !id.isEmpty, start < end else { return nil }
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.calendarColor = calendarColor
        self.externalIdentifier = externalIdentifier
        self.calendarTitle = calendarTitle
        self.webURL = webURL
    }
}

extension Event: Equatable {
    static func == (lhs: Event, rhs: Event) -> Bool {
        lhs.id == rhs.id
    }
}
```

### ファイル 2: `Sources/Toki/Domain/DayTimeline.swift`（編集）

`clip(_:toDayOf:calendar:)` 内の `Event(...)` 呼び出しに `webURL: event.webURL` を継承（既存 Event の `webURL` を新しい clipped Event に伝播）：

Read で現状確認、`Event(id: event.id, ...)` の最後に `webURL: event.webURL` を追加。

### ファイル 3〜5: テスト 3 ファイル（編集）

`Tests/TokiTests/EventTests.swift` / `EventStatusTests.swift` / `DayTimelineTests.swift` の `makeEvent` ヘルパに `webURL: URL? = nil` 引数を追加し、`Event(...)` 呼び出しにも `webURL: webURL` を追記。**ケース本体は無変更**。

**完了条件**:
- [ ] `grep -n "let webURL: URL?" Sources/Toki/Domain/Event.swift` が 1 件マッチ
- [ ] `grep -n "webURL: event.webURL" Sources/Toki/Domain/DayTimeline.swift` が 1 件マッチ
- [ ] `grep -nE "webURL: URL\? = nil" Tests/TokiTests/EventTests.swift Tests/TokiTests/EventStatusTests.swift Tests/TokiTests/DayTimelineTests.swift` が 3 件マッチ
- [ ] `swift build` 成功
- [ ] `swift test` で既存 36 ケース全 pass

**コミット**:
```bash
git add Sources/Toki/Domain/Event.swift Sources/Toki/Domain/DayTimeline.swift Tests/TokiTests/EventTests.swift Tests/TokiTests/EventStatusTests.swift Tests/TokiTests/DayTimelineTests.swift
git commit -m "feat(domain): Event に webURL を追加"
```

**依存**: なし

---

## Task 2: KeychainStore 実装

**Commit**: `feat(infra): KeychainStore 実装（Security Framework wrapper）`

**目的**: macOS Keychain に OAuth token を保存するための薄い wrapper を実装。Security Framework 直叩き、外部ライブラリなし。

**コンテキスト**:
- 参照: plan §6.1
- 前提: `kSecClass = kSecClassGenericPassword`、service `dev.pokotech.Toki`、account はキー名（`oauth.access_token` 等）
- 値は `Data(value.utf8)` で保存、取得時は逆変換

**実装内容**:

ファイル: `Sources/Toki/Infrastructure/KeychainStore.swift`（新規）

```swift
import Foundation
import Security

/// macOS Keychain への薄い wrapper。
/// Generic Password（`kSecClassGenericPassword`）を service + account で識別。
/// OAuth token の保存／取得／削除に使う。
final class KeychainStore {
    enum KeychainStoreError: Error {
        case osStatus(OSStatus)
    }

    private let service: String

    init(service: String = "dev.pokotech.Toki") {
        self.service = service
    }

    /// 既存 entry があれば更新、なければ追加。
    func set(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainStoreError.osStatus(errSecParam)
        }
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let updateAttrs: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainStoreError.osStatus(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainStoreError.osStatus(updateStatus)
        }
    }

    func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.osStatus(status)
        }
    }
}
```

**完了条件**:
- [ ] `grep -n "final class KeychainStore" Sources/Toki/Infrastructure/KeychainStore.swift` が 1 件マッチ
- [ ] `import Security` が含まれる
- [ ] `swift build` 成功
- [ ] `swift test` 36 ケース全 pass

**コミット**:
```bash
git add Sources/Toki/Infrastructure/KeychainStore.swift
git commit -m "feat(infra): KeychainStore 実装（Security Framework wrapper）"
```

**依存**: Task 1（直接の依存はないが順序的に Domain 拡張後）

---

## Task 3: OAuthConfig 実装

**Commit**: `feat(infra): OAuthConfig 実装（~/.config/toki/oauth.json 読み込み）`

**目的**: ユーザーが Google Cloud Console で作成した OAuth Client の認証情報を `~/.config/toki/oauth.json` から読み込む。設定 UI は MVP 範囲外なので JSON 直書きで運用。

**コンテキスト**:
- 参照: plan §6.2
- 前提: ファイルが存在しない場合 nil 返却（OAuth 未設定扱い）、`OAuthClient == nil` で接続メニュー非表示

**実装内容**:

ファイル: `Sources/Toki/Infrastructure/OAuthConfig.swift`（新規）

```swift
import Foundation

/// Google OAuth Client の設定。
/// ユーザーが Google Cloud Console で OAuth Client（Desktop アプリ）を作成し
/// `~/.config/toki/oauth.json` に貼り付ける運用。
/// 設定ファイルが存在しない場合は nil を返し、OAuth 未設定として扱う。
struct OAuthConfig: Decodable {
    let clientId: String
    let clientSecret: String
    let redirectURI: String

    private enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case clientSecret = "client_secret"
        case redirectURI = "redirect_uri"
    }

    /// `~/.config/toki/oauth.json` を読み込んで OAuthConfig を返す。
    /// ファイルなし / パース失敗の場合は nil。
    static func load() -> OAuthConfig? {
        let path = ("~/.config/toki/oauth.json" as NSString).expandingTildeInPath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        return try? JSONDecoder().decode(OAuthConfig.self, from: data)
    }
}
```

**完了条件**:
- [ ] `grep -n "struct OAuthConfig" Sources/Toki/Infrastructure/OAuthConfig.swift` が 1 件マッチ
- [ ] `static func load() -> OAuthConfig?` が含まれる
- [ ] `swift build` 成功
- [ ] `swift test` 36 ケース全 pass

**コミット**:
```bash
git add Sources/Toki/Infrastructure/OAuthConfig.swift
git commit -m "feat(infra): OAuthConfig 実装（~/.config/toki/oauth.json 読み込み）"
```

**依存**: Task 1

---

## Task 4: LoopbackOAuthReceiver 実装

**Commit**: `feat(infra): LoopbackOAuthReceiver 実装（loopback HTTP server）`

**目的**: OAuth consent 後のリダイレクト先（`http://localhost:8081/callback?code=...&state=...`）を Network.framework の loopback HTTP server で受領する。

**コンテキスト**:
- 参照: plan §6.3
- 前提: `NWListener` で TCP listener 起動、1 接続だけ受け取る
- HTTP request line を最低限パース：`GET /callback?code=...&state=... HTTP/1.1`
- `state` 検証で CSRF 防止、不一致は throw
- 成功時に「接続完了」HTML を返してブラウザでメッセージ表示

**実装内容**:

ファイル: `Sources/Toki/Infrastructure/LoopbackOAuthReceiver.swift`（新規）

```swift
import Foundation
import Network

/// OAuth Loopback IP redirect を受領するための loopback HTTP server。
/// `http://localhost:<port>/callback?code=...&state=...` を 1 接続だけ待ち、
/// state を検証してから code を返す。
final class LoopbackOAuthReceiver {
    enum ReceiverError: Error {
        case bindFailed
        case missingCode
        case stateMismatch
        case malformedRequest
    }

    /// 指定ポートで listener を起動し、code を返す。
    /// 1 接続受領後 listener は自動停止。
    func waitForCode(port: UInt16, expectedState: String) async throws -> String {
        let nwPort = NWEndpoint.Port(integerLiteral: port)
        guard let listener = try? NWListener(using: .tcp, on: nwPort) else {
            throw ReceiverError.bindFailed
        }
        return try await withCheckedThrowingContinuation { continuation in
            listener.newConnectionHandler = { [weak listener] connection in
                Self.handle(connection: connection, expectedState: expectedState) { result in
                    listener?.cancel()
                    continuation.resume(with: result)
                }
                connection.start(queue: .global())
            }
            listener.start(queue: .global())
        }
    }

    private static func handle(connection: NWConnection, expectedState: String,
                               completion: @escaping (Result<String, Error>) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
            defer { connection.cancel() }
            guard let data, let request = String(data: data, encoding: .utf8) else {
                Self.sendHTTPResponse(connection: connection, status: 400, body: "Bad Request")
                completion(.failure(ReceiverError.malformedRequest))
                return
            }
            let firstLine = request.components(separatedBy: "\r\n").first ?? ""
            guard let pathQuery = Self.extractPathQuery(from: firstLine) else {
                Self.sendHTTPResponse(connection: connection, status: 400, body: "Bad Request")
                completion(.failure(ReceiverError.malformedRequest))
                return
            }
            let params = Self.parseQuery(pathQuery)
            guard let code = params["code"] else {
                Self.sendHTTPResponse(connection: connection, status: 400, body: "Missing code")
                completion(.failure(ReceiverError.missingCode))
                return
            }
            guard params["state"] == expectedState else {
                Self.sendHTTPResponse(connection: connection, status: 400, body: "State mismatch")
                completion(.failure(ReceiverError.stateMismatch))
                return
            }
            Self.sendHTTPResponse(connection: connection, status: 200,
                                  body: "<html><body>Toki: 接続完了。このタブを閉じてください。</body></html>")
            completion(.success(code))
        }
    }

    private static func extractPathQuery(from requestLine: String) -> String? {
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }
        let target = parts[1]
        guard let qIndex = target.firstIndex(of: "?") else { return nil }
        return String(target[target.index(after: qIndex)...])
    }

    private static func parseQuery(_ query: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in query.components(separatedBy: "&") {
            let kv = pair.components(separatedBy: "=")
            guard kv.count == 2,
                  let key = kv[0].removingPercentEncoding,
                  let value = kv[1].removingPercentEncoding else { continue }
            result[key] = value
        }
        return result
    }

    private static func sendHTTPResponse(connection: NWConnection, status: Int, body: String) {
        let statusText = status == 200 ? "OK" : "Bad Request"
        let response = "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        connection.send(content: response.data(using: .utf8),
                        completion: .contentProcessed { _ in })
    }
}
```

**完了条件**:
- [ ] `grep -n "final class LoopbackOAuthReceiver" Sources/Toki/Infrastructure/LoopbackOAuthReceiver.swift` が 1 件マッチ
- [ ] `import Network` が含まれる
- [ ] `swift build` 成功
- [ ] `swift test` 36 ケース全 pass

**コミット**:
```bash
git add Sources/Toki/Infrastructure/LoopbackOAuthReceiver.swift
git commit -m "feat(infra): LoopbackOAuthReceiver 実装（loopback HTTP server）"
```

**依存**: Task 1

---

## Task 5: GoogleOAuthClient 実装

**Commit**: `feat(infra): GoogleOAuthClient 実装（consent / PKCE / token 交換 / refresh / revoke）`

**目的**: Google OAuth 2.0 (Loopback IP) フローを管理する class。consent URL 生成、code → token 交換、token refresh、revoke を担当。

**コンテキスト**:
- 参照: plan §4「OAuth フロー詳細」、§6.4
- 前提: PKCE 採用（CryptoKit `SHA256` で code_challenge 生成）
- token は KeychainStore に保存（`oauth.access_token` / `oauth.refresh_token` / `oauth.access_token_expiry`）
- 401 → refresh → 1 度リトライ、失敗時は Keychain クリア
- 関数長 < 50 行、ファイル長 < 200 行を目標に helper 分割

**実装内容**:

ファイル: `Sources/Toki/Infrastructure/GoogleOAuthClient.swift`（新規、約 180 行）

主要メソッド：
- `var isAuthorized: Bool`：refresh_token 有無で判定
- `func beginAuthorization() async throws`：PKCE verifier 生成 → consent URL 生成 → NSWorkspace.open → LoopbackOAuthReceiver.waitForCode → token 交換
- `func getValidAccessToken() async throws -> String`：expiry チェック、必要なら refresh
- `func revoke() async throws`：POST /revoke + Keychain クリア

private helper：
- `makeCodeVerifier()`：64 byte ランダム → base64url
- `codeChallenge(from verifier: String)`：SHA-256(verifier) を base64url（CryptoKit）
- `makeNonce()`：32 byte ランダム → base64url（state nonce）
- `makeConsentURL(challenge:state:)`
- `exchange(code:verifier:)`：POST /token
- `refresh()`：POST /token with refresh_token

URL：
- consent: `https://accounts.google.com/o/oauth2/v2/auth?...`
- token: `https://oauth2.googleapis.com/token`
- revoke: `https://oauth2.googleapis.com/revoke?token=...`

scope: `https://www.googleapis.com/auth/calendar.readonly`

**完了条件**:
- [ ] `grep -n "final class GoogleOAuthClient" Sources/Toki/Infrastructure/GoogleOAuthClient.swift` が 1 件マッチ
- [ ] `import CryptoKit` が含まれる
- [ ] public メソッド `beginAuthorization` / `getValidAccessToken` / `revoke` / `isAuthorized` 確認
- [ ] PKCE の S256 challenge 生成ロジックが含まれる
- [ ] `swift build` 成功
- [ ] `swift test` 36 ケース全 pass
- [ ] ファイル長 < 250 行

**コミット**:
```bash
git add Sources/Toki/Infrastructure/GoogleOAuthClient.swift
git commit -m "feat(infra): GoogleOAuthClient 実装（consent / PKCE / token 交換 / refresh / revoke）"
```

**依存**: Task 2, 3, 4

---

## Task 6: GoogleCalendarAPI 実装

**Commit**: `feat(infra): GoogleCalendarAPI 実装（calendars.list / events.list / htmlLink 取得）`

**目的**: Google Calendar API で iCalUID から `htmlLink` を取得する。複数 iCalUID × 複数 calendar を `withTaskGroup` で並列処理。

**コンテキスト**:
- 参照: plan §5「API 呼び出し詳細」、§6.5
- 前提: `oauth.getValidAccessToken()` で token を取得、401 リトライは oauth 側で吸収
- `calendars.list` で全 calendar 取得 → 各 calendar に `events.list?iCalUID=<uid>&singleEvents=true` を並列実行
- レスポンス `items[0].htmlLink` を採用

**実装内容**:

ファイル: `Sources/Toki/Infrastructure/GoogleCalendarAPI.swift`（新規、約 130 行）

```swift
final class GoogleCalendarAPI {
    private let oauth: GoogleOAuthClient
    private let session: URLSession

    init(oauth: GoogleOAuthClient, session: URLSession = .shared) {
        self.oauth = oauth
        self.session = session
    }

    /// 複数の iCalUID に対して各 calendar を並列検索し、htmlLink マップを返す。
    /// 該当なし / API エラーの場合は map に含めない。
    func fetchHTMLLinks(forICalUIDs uids: [String]) async throws -> [String: URL] {
        guard !uids.isEmpty else { return [:] }
        let token = try await oauth.getValidAccessToken()
        let calendars = try await fetchCalendarIds(token: token)

        return await withTaskGroup(of: (String, URL?).self) { group in
            for uid in uids {
                group.addTask {
                    let url = await self.findHTMLLink(uid: uid, calendars: calendars, token: token)
                    return (uid, url)
                }
            }
            var result: [String: URL] = [:]
            for await (uid, url) in group {
                if let url { result[uid] = url }
            }
            return result
        }
    }

    private func fetchCalendarIds(token: String) async throws -> [String] {
        // GET https://www.googleapis.com/calendar/v3/users/me/calendarList
        // Authorization: Bearer <token>
        // レスポンス items[].id を抽出
    }

    private func findHTMLLink(uid: String, calendars: [String], token: String) async -> URL? {
        // 各 calendar に対して GET events?iCalUID=<uid>&singleEvents=true
        // 最初に items[0].htmlLink を返した結果を採用
        // エラー時は silent fail（nil 返却）
    }
}
```

**完了条件**:
- [ ] `grep -n "final class GoogleCalendarAPI" Sources/Toki/Infrastructure/GoogleCalendarAPI.swift` が 1 件マッチ
- [ ] `fetchHTMLLinks(forICalUIDs:)` が public
- [ ] `withTaskGroup` 使用箇所が含まれる
- [ ] `iCalUID` query param 使用箇所が含まれる
- [ ] `swift build` 成功
- [ ] `swift test` 36 ケース全 pass

**コミット**:
```bash
git add Sources/Toki/Infrastructure/GoogleCalendarAPI.swift
git commit -m "feat(infra): GoogleCalendarAPI 実装（calendars.list / events.list / htmlLink 取得）"
```

**依存**: Task 5

---

## Task 7: EventKitGateway に API 連携を組み込み

**Commit**: `feat(infra): EventKitGateway に Google Calendar API 連携を組み込み`

**目的**: `EventKitGateway` に `GoogleCalendarAPI` を注入し、`fetchTodayTimeline` 後段で `@google.com` を含む event の `htmlLink` を取得して `Event.webURL` を埋め込む。in-memory cache で N+1 を回避、`EKEventStoreChanged` で cache invalidate。

**コンテキスト**:
- 参照: plan §7
- 前提: `googleAPI` は Optional、nil なら旧挙動（webURL = nil のまま）
- API 失敗は silent（log + clock 表示維持）
- Event は immutable struct なので、API 結果反映時は new Event を生成

**実装内容**:

ファイル: `Sources/Toki/Infrastructure/EventKitGateway.swift`（編集）

```swift
final class EventKitGateway {
    private let store = EKEventStore()
    private let calendar: Calendar
    private let googleAPI: GoogleCalendarAPI?           // 新規
    private var htmlLinkCache: [String: URL] = [:]      // 新規

    private let subject: CurrentValueSubject<DayTimeline, Never>
    private var cancellables = Set<AnyCancellable>()

    init(calendar: Calendar = .current, googleAPI: GoogleCalendarAPI? = nil) {
        self.calendar = calendar
        self.googleAPI = googleAPI
        let initialDate = calendar.startOfDay(for: Date())
        self.subject = CurrentValueSubject(DayTimeline(date: initialDate, events: []))
    }

    // 既存：timelineUpdates / requestAccess

    func start() {
        cancellables.removeAll()
        NotificationCenter.default
            .publisher(for: .EKEventStoreChanged, object: store)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.htmlLinkCache.removeAll()      // 新規：cache クリア
                Task { await self?.reload() }
            }
            .store(in: &cancellables)
        Task { await reload() }
    }

    // 既存：stop

    func fetchTodayTimeline() async -> DayTimeline {
        let dayStart = calendar.startOfDay(for: Date())
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return DayTimeline(date: dayStart, events: [])
        }
        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
        let ekEvents = store.events(matching: predicate)

        var rawEvents: [Event] = []
        var allDayFlags: [Bool] = []
        for ek in ekEvents {
            guard let event = Self.convert(ek) else { continue }
            rawEvents.append(event)
            allDayFlags.append(ek.isAllDay)
        }

        // 新規：Google event の htmlLink を API で取得 → cache 更新
        await enrichWithHTMLLinks(rawEvents: rawEvents)

        // 新規：webURL を埋め込んだ Event を再生成
        let enriched = rawEvents.map { ev -> Event in
            let webURL = ev.externalIdentifier.flatMap { htmlLinkCache[$0] }
            return Event(id: ev.id, title: ev.title,
                         start: ev.start, end: ev.end,
                         calendarColor: ev.calendarColor,
                         externalIdentifier: ev.externalIdentifier,
                         calendarTitle: ev.calendarTitle,
                         webURL: webURL)!
        }

        return DayTimeline.make(date: dayStart, rawEvents: enriched,
                                allDayFlags: allDayFlags, calendar: calendar)
    }

    private func enrichWithHTMLLinks(rawEvents: [Event]) async {
        guard let api = googleAPI else { return }
        let googleUIDs = rawEvents.compactMap { ev -> String? in
            guard let ext = ev.externalIdentifier, ext.contains("@google.com") else { return nil }
            return htmlLinkCache[ext] == nil ? ext : nil
        }
        guard !googleUIDs.isEmpty else { return }
        do {
            let fetched = try await api.fetchHTMLLinks(forICalUIDs: googleUIDs)
            for (uid, url) in fetched { htmlLinkCache[uid] = url }
        } catch {
            // silent fail：log のみ
            print("Google Calendar API fetch failed: \(error)")
        }
    }

    private func reload() async {
        let timeline = await fetchTodayTimeline()
        subject.send(timeline)
    }

    private static func convert(_ ek: EKEvent) -> Event? {
        // 既存実装：webURL は nil で初期化、enrichment は後段
        let baseId = ek.eventIdentifier ?? UUID().uuidString
        let id = "\(baseId)#\(ek.startDate.timeIntervalSince1970)"
        return Event(
            id: id,
            title: ek.title ?? "(無題)",
            start: ek.startDate,
            end: ek.endDate,
            calendarColor: ek.calendar.cgColor,
            externalIdentifier: ek.calendarItemExternalIdentifier,
            calendarTitle: ek.calendar.title
        )
    }
}
```

**完了条件**:
- [ ] `grep -n "googleAPI" Sources/Toki/Infrastructure/EventKitGateway.swift` で複数件マッチ（プロパティ / init / enrich メソッド）
- [ ] `grep -n "htmlLinkCache" Sources/Toki/Infrastructure/EventKitGateway.swift` が複数件
- [ ] `grep -n "enrichWithHTMLLinks" Sources/Toki/Infrastructure/EventKitGateway.swift` が 2 件以上（定義 + 呼び出し）
- [ ] `grep -n "htmlLinkCache.removeAll" Sources/Toki/Infrastructure/EventKitGateway.swift` が 1 件マッチ
- [ ] `swift build` 成功
- [ ] `swift test` 36 ケース全 pass
- [ ] `./scripts/build-app.sh` 成功

**コミット**:
```bash
git add Sources/Toki/Infrastructure/EventKitGateway.swift
git commit -m "feat(infra): EventKitGateway に Google Calendar API 連携を組み込み"
```

**依存**: Task 6

---

## Task 8: RenderableEvent に webURL を追加

**Commit**: `feat(ui): RenderableEvent に webURL を追加`

**目的**: UI 層 `RenderableEvent` に `webURL: URL?` を追加。`ClockViewModel.canvasEvents` で `Event.webURL` を伝播。

**コンテキスト**:
- 参照: plan §6.1, §8.1
- 前提: spec 003 で `start: Date` 追加、spec 004 で `calendarTitle` 追加と同じパターン
- `Equatable` は id ベース維持

**実装内容**:

### ファイル 1: `Sources/Toki/UI/RenderableEvent.swift`（編集）

`calendarTitle` の直後に `webURL: URL?` を追加：

```swift
struct RenderableEvent: Identifiable {
    let id: String
    let title: String
    let startAngle: Double
    let endAngle: Double
    let color: CGColor
    let status: EventStatus
    let externalIdentifier: String?
    let start: Date
    let end: Date
    let calendarTitle: String
    /// Google Calendar API で取得した event detail URL。
    /// 非 Google event / API 取得失敗の場合は nil（クリック時は今日のビュー fallback）。
    let webURL: URL?
}
```

### ファイル 2: `Sources/Toki/Composition/ClockViewModel.swift`（編集）

`canvasEvents` の `RenderableEvent` 初期化に `webURL: ev.webURL` を追加：

```swift
RenderableEvent(
    // 既存
    calendarTitle: ev.calendarTitle,
    webURL: ev.webURL   // 新規
)
```

**完了条件**:
- [ ] `grep -n "let webURL: URL?" Sources/Toki/UI/RenderableEvent.swift` が 1 件マッチ
- [ ] `grep -n "webURL: ev.webURL" Sources/Toki/Composition/ClockViewModel.swift` が 1 件マッチ
- [ ] `swift build` 成功
- [ ] `swift test` 36 ケース全 pass

**コミット**:
```bash
git add Sources/Toki/UI/RenderableEvent.swift Sources/Toki/Composition/ClockViewModel.swift
git commit -m "feat(ui): RenderableEvent に webURL を追加"
```

**依存**: Task 1（実質的には Task 7 後でも OK だが順序を保つ）

---

## Task 9: spec 004 helper 削除 + handleArcTap を webURL ベースに書き換え

**Commit**: `refactor(composition): spec 004 の eid helper を削除し handleArcTap を webURL ベースに書き換え`

**目的**: spec 004 で reverse-engineered eid を組み立てていた helper 群を削除し、`handleArcTap` を `event.webURL` 優先、nil なら今日のビュー fallback の単純な分岐に書き換える。

**コンテキスト**:
- 参照: plan §8.2, §8.3
- 削除対象：`calendarURL(for:calendar:)` / `googleEventDetailURL(for:)` / `normalizeGoogleUID(_:)` / `utcOccurrenceDateString(_:)`
- 維持：`googleCalendarDayURL(for:calendar:)`（fallback として継続）

**実装内容**:

ファイル: `Sources/Toki/Composition/ClockViewModel.swift`（編集）

### `handleArcTap` を書き換え

```swift
/// イベント円弧のクリックを処理する。
/// Google Calendar API 経由で取得した webURL があればそれを開く（spec 005 で導入）。
/// なければ今日のビュー fallback（spec 003 から継続）。
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

### 削除対象の helper

`// MARK: - クリックハンドラ` セクション内の以下メソッドを削除：
- `calendarURL(for:calendar:)`（spec 004 で導入したディスパッチャ）
- `googleEventDetailURL(for:)`（spec 004 で導入した eid 組み立て）
- `normalizeGoogleUID(_:)`（spec 004 で導入した UID 正規化）
- `utcOccurrenceDateString(_:)`（spec 004 で導入した UTC 日時整形）

### 維持

`googleCalendarDayURL(for:calendar:)` は fallback として引き続き使う、無変更。

**完了条件**:
- [ ] `grep -n "func calendarURL\|func googleEventDetailURL\|func normalizeGoogleUID\|func utcOccurrenceDateString" Sources/Toki/Composition/ClockViewModel.swift` が **0 件**
- [ ] `grep -n "func googleCalendarDayURL" Sources/Toki/Composition/ClockViewModel.swift` が 1 件マッチ（維持確認）
- [ ] `grep -nE "if let webURL = event\.webURL" Sources/Toki/Composition/ClockViewModel.swift` が 1 件マッチ
- [ ] `swift build` 成功（警告なし）
- [ ] `swift test` 36 ケース全 pass
- [ ] `./scripts/build-app.sh` 成功

**コミット**:
```bash
git add Sources/Toki/Composition/ClockViewModel.swift
git commit -m "refactor(composition): spec 004 の eid helper を削除し handleArcTap を webURL ベースに書き換え"
```

**依存**: Task 7, 8

---

## Task 10: AppDelegate に Google Calendar 接続/切断メニュー追加

**Commit**: `feat(app): AppDelegate に Google Calendar 接続/切断メニュー追加`

**目的**: `AppDelegate` で OAuth 関連の依存を組み立て、右クリックメニューに「Google Calendar 接続/切断」を動的に表示。OAuth 設定ファイルが無ければメニュー項目を出さない。

**コンテキスト**:
- 参照: plan §9
- 前提: spec 001 / 003 で「Toki を終了」のみだった右クリックメニューに項目を追加
- `OAuthConfig.load()` が nil → `oauthClient = nil` → 接続メニュー非表示
- `isAuthorized` で「接続」/「切断」を切替

**実装内容**:

ファイル: `Sources/Toki/App/AppDelegate.swift`（編集）

### 依存組み立て

```swift
private var oauthClient: GoogleOAuthClient?

func applicationDidFinishLaunching(_ notification: Notification) {
    let oauth = OAuthConfig.load().map { config in
        GoogleOAuthClient(config: config,
                          keychain: KeychainStore(),
                          receiver: LoopbackOAuthReceiver())
    }
    let googleAPI = oauth.map { GoogleCalendarAPI(oauth: $0) }
    self.oauthClient = oauth

    let gw = EventKitGateway(googleAPI: googleAPI)
    let vm = ClockViewModel(gateway: gw)
    // 既存：window 設定 / vm.start() / status item
}
```

### 右クリックメニュー動的構築

`showContextMenu()`（spec 003 / 004 から名前未変更）を以下に書き換え：

```swift
private func showContextMenu() {
    let menu = NSMenu()

    if let oauth = oauthClient {
        if oauth.isAuthorized {
            menu.addItem(NSMenuItem(title: "Google Calendar 切断",
                                    action: #selector(handleDisconnect),
                                    keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(title: "Google Calendar 接続",
                                    action: #selector(handleConnect),
                                    keyEquivalent: ""))
        }
        menu.addItem(NSMenuItem.separator())
    }

    menu.addItem(NSMenuItem(title: "Toki を終了",
                            action: #selector(NSApplication.terminate(_:)),
                            keyEquivalent: "q"))
    statusItem?.menu = menu
    statusItem?.button?.performClick(nil)
    statusItem?.menu = nil
}

@objc private func handleConnect() {
    Task {
        do { try await oauthClient?.beginAuthorization() }
        catch { print("OAuth connect failed: \(error)") }
    }
}

@objc private func handleDisconnect() {
    Task {
        do { try await oauthClient?.revoke() }
        catch { print("OAuth revoke failed: \(error)") }
    }
}
```

**完了条件**:
- [ ] `grep -n "private var oauthClient" Sources/Toki/App/AppDelegate.swift` が 1 件マッチ
- [ ] `grep -n "OAuthConfig.load" Sources/Toki/App/AppDelegate.swift` が 1 件マッチ
- [ ] `grep -nE "Google Calendar 接続|Google Calendar 切断" Sources/Toki/App/AppDelegate.swift` が 2 件マッチ
- [ ] `grep -n "handleConnect\|handleDisconnect" Sources/Toki/App/AppDelegate.swift` が複数件
- [ ] `swift build` 成功
- [ ] `swift test` 36 ケース全 pass
- [ ] `./scripts/build-app.sh` 成功
- [ ] **実機目視確認**（必須）：
  - `~/.config/toki/oauth.json` 未配置 → 右クリックメニューに接続項目なし、終了のみ
  - `~/.config/toki/oauth.json` 配置済・未接続 → 「Google Calendar 接続」項目表示
  - 接続クリック → ブラウザで consent → loopback 受領 → Keychain 保存
  - 接続後 → 「Google Calendar 切断」に変わる
  - Google event クリック → ブラウザで該当 event detail に到達（ENEOS でも OK）
  - 非 Google event クリック → 今日のビュー fallback
  - 切断クリック → Keychain クリア、次は fallback
  - アプリ再起動後も接続維持
  - 既存挙動（時計 / ツールチップ / 中央 3 行 / 次の予定 / 終了 / wake / タイマー）に影響なし

**コミット**:
```bash
git add Sources/Toki/App/AppDelegate.swift
git commit -m "feat(app): AppDelegate に Google Calendar 接続/切断メニュー追加"
```

**依存**: Task 7, 9

---

## Task 11: SPEC.md を spec 005 整合に更新

**Commit**: `docs(spec): SPEC.md を spec 005 整合に更新`

**目的**: spec 005 で追加された「Google Calendar API 連携」「OAuth 接続フロー」を `SPEC.md` に反映、docs の整合性を保つ。

**コンテキスト**:
- 参照: spec 005 §AC「既存挙動の維持」
- 前提: spec 003 / 004 で SPEC.md は「クリック → Google Calendar 今日ビュー」「event detail URL」と段階更新されている

**実装内容**:

ファイル: `SPEC.md`（編集）

該当箇所を Read で確認し、spec 005 反映版に更新：

- §2「インタラクション」左クリック記述：「Google Calendar API 経由で取得した event detail URL を開く」を主、未接続時は今日のビュー fallback と明記
- §7「イベント円弧クリック時の挙動」セクション：spec 005 の仕組み（API 取得 → webURL → fallback）を反映、reverse-engineered eid の記述を削除
- 「右クリックメニュー」関連の記述があれば「Google Calendar 接続/切断」項目を追記

**完了条件**:
- [ ] `grep -nE "spec 005" SPEC.md` が 1 件以上マッチ
- [ ] `grep -nE "Google Calendar API|htmlLink" SPEC.md` が 1 件以上マッチ
- [ ] `grep -nE "OAuth|接続/切断|接続 / 切断" SPEC.md` が 1 件以上マッチ
- [ ] `grep -nE "ical://ekevent" SPEC.md` が 0 件（spec 003 で削除済み確認）
- [ ] `swift build` / `swift test` への影響なし（docs のみ）

**コミット**:
```bash
git add SPEC.md
git commit -m "docs(spec): SPEC.md を spec 005 整合に更新"
```

**依存**: Task 10

---

## 全 task 完了後

### 回帰確認

- [ ] `swift test`：Domain 36 ケース全 pass
- [ ] `./scripts/build-app.sh && open .build/Toki.app`：実機目視で spec 005 §AC の項目を walkthrough

### コードベース確認

- [ ] `grep -rn "googleEventDetailURL\|normalizeGoogleUID\|utcOccurrenceDateString" Sources/` → 0 件
- [ ] `grep -rn "ical://" Sources/` → 0 件
- [ ] `grep -rn "stripRecurrenceSuffix" Sources/` → 0 件（spec 004 helper 全消去確認）

### コードレビュー

- `code-reviewer` agent で全体レビュー：
  - 依存方向：Domain / Infrastructure / Composition / UI / App 各層の責務逸脱なし
  - Infrastructure 5 新規ファイルの責務分離
  - OAuth フロー / Keychain 連携の安全性（state 検証、token 漏洩）
  - エラーハンドリングの一貫性（silent fail）
  - ファイル長 < 400 行 / 関数長 < 50 行
  - 不要な protocol 切り出しなし
