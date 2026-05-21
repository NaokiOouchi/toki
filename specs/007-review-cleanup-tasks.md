# 007 — review-cleanup: Tasks

参照: `specs/007-review-cleanup.md` / `specs/007-review-cleanup-plan.md`

合計: **4 tasks**

実装順序：上から順に。各 task は fresh subagent に渡して 1 commit ずつ。

spec 006 後のレビュー HIGH 5 件の片付け。Domain field 削除と Infrastructure の小修正。Domain テストは無変更で全 pass 維持。

---

## Task 1: Event から calendarTitle / externalIdentifier を削除（dead field 整理）

**Commit**: `refactor(domain+ui+infra+composition): Event から calendarTitle / externalIdentifier を削除`

**目的**: spec 004 で導入したが spec 006 で不要化した dead field を Domain / UI / Infrastructure / Composition / Tests から完全削除。8 ファイル統合 commit。

**コンテキスト**:
- 参照: spec 007 §AC「Event から dead field 削除（H2 + H3）」、plan §5
- 前提：reading 側がゼロ（grep 確認済み）、伝播のみ
- Event signature 変更は全レイヤーに同時に波及するため、中間 commit を切ると build error 不可避 → 1 commit にまとめる

**実装内容**:

### ファイル 1: `Sources/Toki/Domain/Event.swift`（編集）

`calendarTitle` / `externalIdentifier` を struct + init から削除：

```swift
import Foundation
import CoreGraphics

struct Event: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let calendarColor: CGColor
    /// Google Calendar API で取得した event detail URL（`htmlLink`）。
    /// 取得失敗の場合は nil。
    let webURL: URL?

    init?(id: String, title: String, start: Date, end: Date,
          calendarColor: CGColor, webURL: URL? = nil) {
        guard !id.isEmpty, start < end else { return nil }
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.calendarColor = calendarColor
        self.webURL = webURL
    }
}

extension Event: Equatable {
    static func == (lhs: Event, rhs: Event) -> Bool { lhs.id == rhs.id }
}
```

### ファイル 2: `Sources/Toki/Domain/DayTimeline.swift`（編集）

`clip(_:)` 内 `Event(...)` 呼び出しから `calendarTitle: event.calendarTitle` と `externalIdentifier: event.externalIdentifier` を削除。

### ファイル 3: `Sources/Toki/UI/RenderableEvent.swift`（編集）

`calendarTitle` / `externalIdentifier` を struct から削除：

```swift
import Foundation
import CoreGraphics

struct RenderableEvent: Identifiable {
    let id: String
    let title: String
    let startAngle: Double
    let endAngle: Double
    let color: CGColor
    let status: EventStatus
    let start: Date
    let end: Date
    let webURL: URL?
}

extension RenderableEvent: Equatable {
    static func == (lhs: RenderableEvent, rhs: RenderableEvent) -> Bool { lhs.id == rhs.id }
}
```

### ファイル 4: `Sources/Toki/Composition/ClockViewModel.swift`（編集）

`canvasEvents` の `RenderableEvent` 初期化から `calendarTitle: ev.calendarTitle` と `externalIdentifier: ev.externalIdentifier` を削除。

### ファイル 5: `Sources/Toki/Infrastructure/GoogleCalendarGateway.swift`（編集）

`convert(_:)` の `Event(...)` 呼び出しから `calendarTitle: ge.calendarSummary` と `externalIdentifier: ge.iCalUID` を削除：

```swift
private static func convert(_ ge: GoogleAPIEvent) -> (Event, Bool)? {
    let isAllDay = ge.start.dateTime == nil
    guard let start = ge.start.dateTime ?? ge.start.date,
          let end = ge.end.dateTime ?? ge.end.date else { return nil }
    let id = "\(ge.id)#\(start.timeIntervalSince1970)"
    guard let event = Event(id: id,
                            title: ge.summary,
                            start: start, end: end,
                            calendarColor: ge.calendarColor,
                            webURL: ge.htmlLink) else { return nil }
    return (event, isAllDay)
}
```

`GoogleAPIEvent.iCalUID` / `calendarSummary` 自体は Infrastructure 中間型として **残置**（API レスポンス読み出し用、Phase 3 で再活用余地）。

### ファイル 6: `Tests/TokiTests/EventTests.swift`（編集）

`makeEvent` ヘルパから `calendarTitle: String = ""` と `externalIdentifier: String? = nil` 引数を削除、`Event(...)` 呼び出しからも削除：

```swift
private func makeEvent(id: String = "id-1",
                       title: String = "テスト予定",
                       start: Date = Date(timeIntervalSince1970: 1_700_000_000),
                       end: Date = Date(timeIntervalSince1970: 1_700_003_600),
                       webURL: URL? = nil)
    -> Event? {
    Event(id: id, title: title, start: start, end: end,
          calendarColor: makeColor(),
          webURL: webURL)
}
```

`testInit_normal` の `XCTAssertEqual(e?.externalIdentifier, "ext-1")` 1 行を **削除**（field が消えたため不可避）。他のアサーションはそのまま。

### ファイル 7: `Tests/TokiTests/EventStatusTests.swift`（編集）

```swift
private func makeEvent(start: Date, end: Date, webURL: URL? = nil) -> Event {
    Event(id: "e1", title: "test", start: start, end: end,
          calendarColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
          webURL: webURL)!
}
```

### ファイル 8: `Tests/TokiTests/DayTimelineTests.swift`（編集）

```swift
private func makeEvent(id: String, start: Date, end: Date, webURL: URL? = nil) -> Event {
    Event(id: id, title: "ev-\(id)", start: start, end: end,
          calendarColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
          webURL: webURL)!
}
```

**完了条件**:

```bash
# Event から field 消去
grep -nE "let calendarTitle: String|let externalIdentifier: String\?" Sources/Toki/Domain/Event.swift
# → 0 件

# RenderableEvent から field 消去
grep -nE "let calendarTitle: String|let externalIdentifier: String\?" Sources/Toki/UI/RenderableEvent.swift
# → 0 件

# Sources/ 全体で calendarTitle / externalIdentifier 参照ゼロ（GoogleAPIEvent.iCalUID 等は Infrastructure 中間型として残るので別名）
grep -rn "calendarTitle\|externalIdentifier" Sources/
# → 0 件

# テストヘルパから引数消去
grep -rn "calendarTitle: String = \"\"|externalIdentifier: String? = nil" Tests/TokiTests/
# → 0 件

# ビルド・テスト
swift build
# → Build complete!

swift test
# → Executed 36 tests, with 0 failures
```

**コミット**:
```bash
git add Sources/Toki/Domain/Event.swift \
        Sources/Toki/Domain/DayTimeline.swift \
        Sources/Toki/UI/RenderableEvent.swift \
        Sources/Toki/Composition/ClockViewModel.swift \
        Sources/Toki/Infrastructure/GoogleCalendarGateway.swift \
        Tests/TokiTests/EventTests.swift \
        Tests/TokiTests/EventStatusTests.swift \
        Tests/TokiTests/DayTimelineTests.swift
git status   # 8 ファイルのみがステージ
git commit -m "refactor(domain+ui+infra+composition): Event から calendarTitle / externalIdentifier を削除"
```

**依存**: なし

---

## Task 2: GoogleCalendarGateway に @Published isAuthorized を追加し ViewModel が sink（H1）

**Commit**: `feat(infra+composition): GoogleCalendarGateway に @Published isAuthorized を追加し ViewModel が sink`

**目的**: refresh 失敗時の Keychain クリアを ViewModel に伝搬し、`accessGranted` を自動同期。spec 007 §AC「未接続 UX → 右クリックで接続」と spec 006 §AC「OAuth 失効時の UX 復旧」を満たす。

**コンテキスト**:
- 参照: spec 007 §AC「isAuthorized 同期」、plan §4
- 前提：Task 1 で Event field 削除済み
- 現状 `isAuthorized` は computed property（`oauthClient.isAuthorized` を透過）→ これを `@Published` に昇格
- `reload()` 末尾で再評価して `@Published` 更新 → ViewModel が Combine で sink

**実装内容**:

### ファイル 1: `Sources/Toki/Infrastructure/GoogleCalendarGateway.swift`（編集）

#### `ObservableObject` 適合追加 + `@Published` プロパティ

```swift
@MainActor
final class GoogleCalendarGateway: ObservableObject {
    private let oauthClient: GoogleOAuthClient
    private let api: GoogleCalendarAPI
    private let calendar: Calendar
    private let subject: CurrentValueSubject<DayTimeline, Never>
    private var reloadTimerCancellable: AnyCancellable?

    /// OAuth 接続状態。reload() 完了時に oauthClient.isAuthorized で再評価し、
    /// ViewModel は Combine で sink して accessGranted を同期する。
    @Published private(set) var isAuthorized: Bool = false

    init(oauthClient: GoogleOAuthClient,
         api: GoogleCalendarAPI,
         calendar: Calendar = .current) {
        self.oauthClient = oauthClient
        self.api = api
        self.calendar = calendar
        let initialDate = calendar.startOfDay(for: Date())
        self.subject = CurrentValueSubject(DayTimeline(date: initialDate, events: []))
        self.isAuthorized = oauthClient.isAuthorized  // init 時の初期評価
    }

    var timelineUpdates: AnyPublisher<DayTimeline, Never> {
        subject.eraseToAnyPublisher()
    }
```

**注意**：既存の `var isAuthorized: Bool { oauthClient.isAuthorized }` computed property は **削除**（`@Published` プロパティに置換）。同名のため呼び出し側は無変更。

#### `start()` で再評価

```swift
func start() {
    reloadTimerCancellable?.cancel()
    isAuthorized = oauthClient.isAuthorized  // 新規：start() 時の再評価
    Task { await reload() }
    reloadTimerCancellable = Timer.publish(every: 300, on: .main, in: .common)
        .autoconnect()
        .sink { [weak self] _ in Task { await self?.reload() } }
}
```

#### `reload()` 末尾で再評価

```swift
func reload() async {
    let timeline = await fetchTodayTimeline()
    // refresh 失敗で Keychain がクリアされていれば isAuthorized=false に転落
    isAuthorized = oauthClient.isAuthorized
    subject.send(timeline)
}
```

### ファイル 2: `Sources/Toki/Composition/ClockViewModel.swift`（編集）

`start()` 内に `gateway?.$isAuthorized` の sink を追加：

```swift
func start() async {
    accessGranted = gateway?.isAuthorized ?? false  // 既存：初期評価

    gateway?.start()

    // 新規：@Published isAuthorized を購読して accessGranted を自動同期
    gateway?.$isAuthorized
        .receive(on: DispatchQueue.main)
        .sink { [weak self] granted in self?.accessGranted = granted }
        .store(in: &cancellables)

    gateway?.timelineUpdates
        .receive(on: DispatchQueue.main)
        .sink { [weak self] tl in self?.timeline = tl }
        .store(in: &cancellables)

    now = Date()
    scheduleMinuteTimer()
    // 以下 wake notification 等は無変更
}
```

既存の `refreshAuthorizationState()` は保険として **維持**（AppDelegate から呼ばれる）。

**完了条件**:

```bash
# @Published isAuthorized 追加
grep -n "@Published private(set) var isAuthorized: Bool" Sources/Toki/Infrastructure/GoogleCalendarGateway.swift
# → 1 件マッチ

# ObservableObject 適合
grep -n "final class GoogleCalendarGateway: ObservableObject" Sources/Toki/Infrastructure/GoogleCalendarGateway.swift
# → 1 件マッチ

# reload() 末尾で再評価
grep -n "isAuthorized = oauthClient.isAuthorized" Sources/Toki/Infrastructure/GoogleCalendarGateway.swift
# → 3 件マッチ（init / start / reload）

# 既存 computed property 削除
grep -n "var isAuthorized: Bool {" Sources/Toki/Infrastructure/GoogleCalendarGateway.swift
# → 0 件

# ViewModel sink 追加
grep -n "gateway?.\$isAuthorized" Sources/Toki/Composition/ClockViewModel.swift
# → 1 件マッチ

# ビルド・テスト
swift build
# → Build complete!

swift test
# → 36 ケース全 pass

./scripts/build-app.sh
# → Built .build/Toki.app
```

**コミット**:
```bash
git add Sources/Toki/Infrastructure/GoogleCalendarGateway.swift Sources/Toki/Composition/ClockViewModel.swift
git commit -m "feat(infra+composition): GoogleCalendarGateway に @Published isAuthorized を追加し ViewModel が sink"
```

**依存**: Task 1

---

## Task 3: GoogleCalendarAPI に HTTP status 検査と 401 retry（H4）

**Commit**: `feat(infra): GoogleCalendarAPI に HTTP status 検査と 401 retry`

**目的**: API レスポンスの HTTP status を見て、401 のみ 1 回 retry、それ以外の non-2xx は log + 空配列。silent fail を log fail に改善し、デバッグ性向上 + token 失効時の堅牢性確保。

**コンテキスト**:
- 参照: spec 007 §AC「HTTP status 検査」、plan §6
- 前提：`oauth.getValidAccessToken()` は GoogleOAuthClient 側で refresh を 1 回試行する
- `for attempt in 0..<2` で 2 回上限を強制
- 401 以外（403, 5xx 等）は retry せず即 log + 空配列

**実装内容**:

ファイル: `Sources/Toki/Infrastructure/GoogleCalendarAPI.swift`（編集）

Read で現状の `fetchEvents(in:timeMin:timeMax:token:)` を確認、以下に書き換え：

```swift
private func fetchEvents(in cal: GoogleAPICalendar,
                         timeMin: String, timeMax: String,
                         token initialToken: String) async -> [GoogleAPIEvent] {
    let encodedId = cal.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cal.id
    let urlStr = "\(Self.baseURL)/calendars/\(encodedId)/events?timeMin=\(timeMin)&timeMax=\(timeMax)&singleEvents=true&orderBy=startTime&maxResults=250"
    guard let url = URL(string: urlStr) else { return [] }

    var token = initialToken
    // attempt=0: 初回, attempt=1: 401 直後の retry。
    for attempt in 0..<2 {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

            if statusCode == 401 && attempt == 0 {
                // token 失効: 新 token で 1 回だけ retry
                do {
                    token = try await oauth.getValidAccessToken()
                    continue
                } catch {
                    print("GoogleCalendarAPI fetchEvents: 401 refresh failed: \(error)")
                    return []
                }
            }
            if !(200...299).contains(statusCode) {
                print("GoogleCalendarAPI fetchEvents: status \(statusCode) for calendar \(cal.id)")
                return []
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else { return [] }
            return items.compactMap { Self.parseEvent($0, calendar: cal) }
        } catch {
            print("GoogleCalendarAPI fetchEvents network error: \(error)")
            return []
        }
    }
    return []
}
```

**完了条件**:

```bash
# for attempt in 0..<2 ループ
grep -n "for attempt in 0\.\.<2" Sources/Toki/Infrastructure/GoogleCalendarAPI.swift
# → 1 件マッチ

# 401 retry ロジック
grep -n "statusCode == 401 && attempt == 0" Sources/Toki/Infrastructure/GoogleCalendarAPI.swift
# → 1 件マッチ

# HTTP status check
grep -nE "!\(200\.\.\.299\)\.contains\(statusCode\)" Sources/Toki/Infrastructure/GoogleCalendarAPI.swift
# → 1 件マッチ

# token refresh 呼び出し
grep -n "oauth.getValidAccessToken" Sources/Toki/Infrastructure/GoogleCalendarAPI.swift
# → 2 件以上マッチ（既存の fetchTodayEvents 開始時 + 本 task の retry）

# ビルド・テスト
swift build
# → Build complete!

swift test
# → 36 ケース全 pass

./scripts/build-app.sh
# → Built .build/Toki.app
```

**コミット**:
```bash
git add Sources/Toki/Infrastructure/GoogleCalendarAPI.swift
git commit -m "feat(infra): GoogleCalendarAPI に HTTP status 検査と 401 retry"
```

**依存**: なし（Task 1/2 と独立、順序は決まっている）

---

## Task 4: GoogleOAuthClient.revoke の空 if 文を log に置換（H5）

**Commit**: `refactor(infra): GoogleOAuthClient.revoke の空 if 文を log に置換`

**目的**: 空 if 文を削除して log 1 行に置換。Keychain クリアを do/catch の外に移して network error 時にも確実に実行されるよう改善。

**コンテキスト**:
- 参照: spec 007 §AC「revoke 空 if 文整理」、plan §7
- 既存挙動：non-2xx 時に空 if 文（コメントだけ）、network error 時は throw が外まで突き抜けて Keychain クリアに到達しない軽微バグあり
- 修正後：non-2xx を log、network error も log、Keychain クリアは必ず実行（既存軽微バグ修正）

**実装内容**:

ファイル: `Sources/Toki/Infrastructure/GoogleOAuthClient.swift`（編集）

Read で現状の `revoke()` を確認、以下に書き換え：

```swift
/// token を revoke して Keychain 全エントリを削除する。
/// network 失敗 / non-2xx でも Keychain は必ずクリア（再認証で復旧可）。
func revoke() async throws {
    guard let refreshToken = keychain.get(Self.keyRefreshToken) else {
        throw OAuthClientError.noRefreshToken
    }
    let url = URL(string: "\(Self.revokeURL)?token=\(refreshToken)")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    do {
        let (_, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            print("GoogleOAuthClient.revoke: status \(http.statusCode), Keychain は引き続きクリア")
        }
    } catch {
        print("GoogleOAuthClient.revoke: network error: \(error), Keychain は引き続きクリア")
    }
    try? keychain.delete(Self.keyAccessToken)
    try? keychain.delete(Self.keyRefreshToken)
    try? keychain.delete(Self.keyExpiry)
}
```

差分の要点：
- 空 if 文を削除、non-2xx は `print` で 1 行 log
- network error の catch を追加、log を出す
- Keychain クリアは do/catch の外に移動 → 成功 / 失敗どちらでも確実実行

**完了条件**:

```bash
# 空 if 文消滅
grep -nA 1 "!\(200\.\.\.299\)\.contains\(http\.statusCode\)" Sources/Toki/Infrastructure/GoogleOAuthClient.swift
# → 直後の行に print がある（空ブロックではない）

# network error catch
grep -nE "print\(\"GoogleOAuthClient\.revoke: network error" Sources/Toki/Infrastructure/GoogleOAuthClient.swift
# → 1 件マッチ

# Keychain クリアが do/catch の外
# revoke() 内で keychain.delete が catch 直後（do の外側）にあることを目視確認

# ビルド・テスト
swift build
# → Build complete!

swift test
# → 36 ケース全 pass

./scripts/build-app.sh
# → Built .build/Toki.app
```

**コミット**:
```bash
git add Sources/Toki/Infrastructure/GoogleOAuthClient.swift
git commit -m "refactor(infra): GoogleOAuthClient.revoke の空 if 文を log に置換"
```

**依存**: なし

---

## 全 task 完了後

### 回帰確認

- [ ] `swift test`：Domain 36 ケース全 pass
- [ ] `./scripts/build-app.sh && open .build/Toki.app`：実機目視で挙動確認

### 手動チェックリスト

| # | 項目 | 期待 |
|---|---|---|
| M1 | 起動 → 接続済みなら event 表示、未接続なら「右クリックで接続」 | 既存挙動維持 |
| M2 | 接続 / 切断 → 中央テキスト即座に切替 | 既存挙動維持 |
| M3 | **H1 確認**：Keychain Access.app で refresh_token を破壊 → 5 分以内の reload で「右クリックで接続」に転落 | 新規動作 |
| M4 | **H4 確認**：Console.app で 401 retry の log 確認（任意） | 新規動作 |
| M5 | **H5 確認**：切断時に network 切断状態でも Keychain クリア成功（任意） | 新規動作 |
| M6 | 円弧クリック → ブラウザで Google Calendar event detail | 既存挙動維持 |

### コードベース確認

- [ ] `grep -rn "calendarTitle\|externalIdentifier" Sources/Toki/Domain/ Sources/Toki/UI/ Sources/Toki/Composition/ Sources/Toki/Infrastructure/GoogleCalendarGateway.swift` → 0 件
- [ ] `grep -rn "import EventKit" Sources/` → 0 件
- [ ] `grep -rn "@Published.*isAuthorized" Sources/` → 1 件

### コードレビュー（任意）

- `code-reviewer` agent で全体レビューを再度実行（spec 007 で導入した変更の確認）
- 特にチェック：dead field 完全除去、`@Published isAuthorized` の sync 経路、401 retry の上限、`revoke` の Keychain クリア確実性
