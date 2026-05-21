# 006 — google-only: Tasks

参照: `specs/006-google-only.md` / `specs/006-google-only-plan.md`

合計: **8 tasks**

実装順序：上から順に。各 task は fresh subagent に渡して 1 commit ずつ。

EventKit 撤去 + Google API 単独運用への refactor。Domain 無変更、UI 影響最小、Composition / App / Infrastructure を入れ替え。

---

## Task 1: GoogleCalendarAPI に fetchTodayEvents を追加

**Commit**: `feat(infra): GoogleCalendarAPI に fetchTodayEvents を追加`

**目的**: `events.list` で今日の event を全 calendar 横断で取得し、`GoogleAPIEvent` 配列で返す。spec 005 の `fetchHTMLLinks` は **まだ削除しない**（並存させて Task 4/5 で削除）。

**コンテキスト**:
- 参照: plan §5
- 前提: `getValidAccessToken` / `fetchCalendarIds` は既存（spec 005）
- 中間型 `GoogleAPIEvent` / `GoogleAPIEventDate` / `GoogleAPICalendar` を新規導入
- `fetchCalendarIds` を `fetchCalendars`（id + summary + backgroundColor を返す）にリネーム + 拡張
- 既存 `fetchHTMLLinks` から使われる `findHTMLLink` / `fetchHTMLLink` の依存を切らないよう注意

**実装内容**:

ファイル: `Sources/Toki/Infrastructure/GoogleCalendarAPI.swift`（編集）

### 中間型を追加（同ファイル内 or 末尾）

```swift
/// API レスポンスから組み立てる中間型。Domain 層には漏らさない。
struct GoogleAPIEvent {
    let id: String
    let iCalUID: String
    let summary: String
    let start: GoogleAPIEventDate
    let end: GoogleAPIEventDate
    let htmlLink: URL?
    let calendarSummary: String
    let calendarColor: CGColor
}

struct GoogleAPIEventDate {
    /// dateTime 形式（time 付き）。all-day event の場合は nil。
    let dateTime: Date?
    /// date 形式（YYYY-MM-DD）。time 付き event の場合は nil。
    let date: Date?
}

struct GoogleAPICalendar {
    let id: String
    let summary: String
    let backgroundColor: CGColor
}
```

### `fetchCalendarIds` を `fetchCalendars` にリネーム + 拡張

```swift
private func fetchCalendars(token: String) async throws -> [GoogleAPICalendar] {
    guard let url = URL(string: "\(Self.baseURL)/users/me/calendarList") else {
        throw APIError.invalidURL
    }
    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let (data, _) = try await session.data(for: request)
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let items = json["items"] as? [[String: Any]] else {
        throw APIError.invalidResponse
    }
    return items.compactMap { item -> GoogleAPICalendar? in
        guard let id = item["id"] as? String else { return nil }
        let summary = (item["summary"] as? String) ?? id
        let bgHex = (item["backgroundColor"] as? String) ?? "#808080"
        return GoogleAPICalendar(id: id, summary: summary,
                                 backgroundColor: Self.cgColor(fromHex: bgHex))
    }
}
```

**注意**：既存の `fetchHTMLLinks` 内で `fetchCalendarIds` を呼んでいる箇所を `fetchCalendars` 戻り値の `.map { $0.id }` に変えて互換維持。

### 新規メソッド `fetchTodayEvents` 追加

```swift
/// 今日の event を全 calendar 横断で並列取得する。
/// 各 calendar の `events.list?timeMin=...&timeMax=...&singleEvents=true&orderBy=startTime` を並列実行し、
/// 親 calendar の summary / color を詰めて GoogleAPIEvent 配列で返す。
/// 個別 calendar 失敗は空配列で扱う（silent fail）。
func fetchTodayEvents(timeMin: Date, timeMax: Date) async throws -> [GoogleAPIEvent] {
    let token = try await oauth.getValidAccessToken()
    let calendars = try await fetchCalendars(token: token)
    guard !calendars.isEmpty else { return [] }

    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime]
    let minStr = isoFormatter.string(from: timeMin)
    let maxStr = isoFormatter.string(from: timeMax)

    return await withTaskGroup(of: [GoogleAPIEvent].self) { group in
        for cal in calendars {
            group.addTask {
                await self.fetchEvents(in: cal, timeMin: minStr,
                                       timeMax: maxStr, token: token)
            }
        }
        var result: [GoogleAPIEvent] = []
        for await events in group { result.append(contentsOf: events) }
        return result
    }
}

/// 1 つの calendar から event を取得する。失敗は空配列。
private func fetchEvents(in cal: GoogleAPICalendar,
                        timeMin: String, timeMax: String,
                        token: String) async -> [GoogleAPIEvent] {
    let encodedId = cal.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cal.id
    let urlStr = "\(Self.baseURL)/calendars/\(encodedId)/events?timeMin=\(timeMin)&timeMax=\(timeMax)&singleEvents=true&orderBy=startTime&maxResults=250"
    guard let url = URL(string: urlStr) else { return [] }
    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    do {
        let (data, _) = try await session.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { Self.parseEvent($0, calendar: cal) }
    } catch {
        return []
    }
}

/// 1 つの event JSON を GoogleAPIEvent に変換する。
private static func parseEvent(_ item: [String: Any],
                              calendar cal: GoogleAPICalendar) -> GoogleAPIEvent? {
    guard let id = item["id"] as? String,
          let iCalUID = item["iCalUID"] as? String,
          let summary = item["summary"] as? String,
          let startDict = item["start"] as? [String: Any],
          let endDict = item["end"] as? [String: Any] else { return nil }
    let htmlLink = (item["htmlLink"] as? String).flatMap { URL(string: $0) }
    return GoogleAPIEvent(
        id: id,
        iCalUID: iCalUID,
        summary: summary,
        start: parseEventDate(startDict),
        end: parseEventDate(endDict),
        htmlLink: htmlLink,
        calendarSummary: cal.summary,
        calendarColor: cal.backgroundColor
    )
}

/// `{ "dateTime": "2026-05-21T10:00:00+09:00" }` または `{ "date": "2026-05-21" }` を変換。
private static func parseEventDate(_ dict: [String: Any]) -> GoogleAPIEventDate {
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime]
    let dateTime = (dict["dateTime"] as? String).flatMap { isoFormatter.date(from: $0) }

    let dateOnlyFormatter = DateFormatter()
    dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateOnlyFormatter.timeZone = TimeZone.current
    dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
    let date = (dict["date"] as? String).flatMap { dateOnlyFormatter.date(from: $0) }

    return GoogleAPIEventDate(dateTime: dateTime, date: date)
}

/// HEX 文字列（`#RRGGBB`）を CGColor に変換。失敗時は gray。
private static func cgColor(fromHex hex: String) -> CGColor {
    let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard s.count == 6, let v = UInt32(s, radix: 16) else {
        return CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
    }
    let r = CGFloat((v >> 16) & 0xFF) / 255
    let g = CGFloat((v >> 8) & 0xFF) / 255
    let b = CGFloat(v & 0xFF) / 255
    return CGColor(red: r, green: g, blue: b, alpha: 1)
}
```

**注意**: `import CoreGraphics` を追加（CGColor 用）。

**完了条件**:
- [ ] `grep -n "func fetchTodayEvents" Sources/Toki/Infrastructure/GoogleCalendarAPI.swift` が 1 件
- [ ] `grep -n "struct GoogleAPIEvent" Sources/Toki/Infrastructure/GoogleCalendarAPI.swift` が 1 件
- [ ] `grep -n "func fetchCalendars" Sources/Toki/Infrastructure/GoogleCalendarAPI.swift` が 1 件
- [ ] 既存の `fetchHTMLLinks` が引き続きビルド成功（並存確認）
- [ ] `swift build` 成功
- [ ] `swift test` 36 ケース全 pass

**コミット**:
```bash
git add Sources/Toki/Infrastructure/GoogleCalendarAPI.swift
git commit -m "feat(infra): GoogleCalendarAPI に fetchTodayEvents を追加"
```

**依存**: なし

---

## Task 2: GoogleCalendarGateway 新規作成

**Commit**: `feat(infra): GoogleCalendarGateway を新規作成`

**目的**: `events.list` 経由で今日の event を取得 → Domain Event 生成 → `CurrentValueSubject` 経由で publish。5 分間隔の自動 reload + 接続/切断時の手動 reload に対応。

**コンテキスト**:
- 参照: plan §4
- 前提: Task 1 で `fetchTodayEvents` 利用可能
- まだ AppDelegate からは注入しない（Task 3 で）
- `@MainActor` を class 全体に付ける（既存 ClockViewModel と同じスタイル）

**実装内容**:

ファイル: `Sources/Toki/Infrastructure/GoogleCalendarGateway.swift`（新規）

```swift
import Foundation
import Combine

/// Google Calendar API 経由で今日の event を取得して Domain `DayTimeline` を公開する Gateway。
/// EventKit を使わず、`events.list` で event 一覧を直接取得する。
/// 5 分間隔の自動 reload + 接続/切断時の手動 reload に対応。
/// API 失敗時は last-known timeline を維持（clock 表示を止めない）。
@MainActor
final class GoogleCalendarGateway {
    private let oauthClient: GoogleOAuthClient
    private let api: GoogleCalendarAPI
    private let calendar: Calendar
    private let subject: CurrentValueSubject<DayTimeline, Never>
    private var reloadTimerCancellable: AnyCancellable?

    init(oauthClient: GoogleOAuthClient,
         api: GoogleCalendarAPI,
         calendar: Calendar = .current) {
        self.oauthClient = oauthClient
        self.api = api
        self.calendar = calendar
        let initialDate = calendar.startOfDay(for: Date())
        self.subject = CurrentValueSubject(DayTimeline(date: initialDate, events: []))
    }

    var timelineUpdates: AnyPublisher<DayTimeline, Never> {
        subject.eraseToAnyPublisher()
    }

    /// OAuth 接続状態を直接公開する（ViewModel の accessGranted を更新するため）。
    var isAuthorized: Bool {
        oauthClient.isAuthorized
    }

    /// 初回 reload + 5 分間隔の自動 reload を開始する。
    func start() {
        reloadTimerCancellable?.cancel()
        Task { await reload() }
        reloadTimerCancellable = Timer.publish(every: 300, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.reload() }
            }
    }

    /// 自動 reload タイマーを停止する。
    func stop() {
        reloadTimerCancellable?.cancel()
    }

    /// 今すぐ event を再取得して subject に流す。
    /// 接続/切断時に AppDelegate から呼ぶ。
    func reload() async {
        let timeline = await fetchTodayTimeline()
        subject.send(timeline)
    }

    /// 今日の DayTimeline を Google Calendar API 経由で取得する。
    /// 未接続時は空 timeline、API 失敗時は last-known timeline 維持。
    private func fetchTodayTimeline() async -> DayTimeline {
        let dayStart = calendar.startOfDay(for: Date())
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return DayTimeline(date: dayStart, events: [])
        }
        guard oauthClient.isAuthorized else {
            return DayTimeline(date: dayStart, events: [])
        }
        do {
            let apiEvents = try await api.fetchTodayEvents(timeMin: dayStart, timeMax: dayEnd)
            var rawEvents: [Event] = []
            var allDayFlags: [Bool] = []
            for ge in apiEvents {
                guard let (event, isAllDay) = Self.convert(ge) else { continue }
                rawEvents.append(event)
                allDayFlags.append(isAllDay)
            }
            return DayTimeline.make(date: dayStart,
                                    rawEvents: rawEvents,
                                    allDayFlags: allDayFlags,
                                    calendar: calendar)
        } catch {
            print("Google Calendar API fetch failed: \(error)")
            return subject.value
        }
    }

    /// API レスポンスを Domain `Event` に変換し、(Event, isAllDay) を返す。
    /// 失敗時 / 必須フィールド欠落時は nil。
    private static func convert(_ ge: GoogleAPIEvent) -> (Event, Bool)? {
        let isAllDay = ge.start.dateTime == nil
        guard let start = ge.start.dateTime ?? ge.start.date,
              let end = ge.end.dateTime ?? ge.end.date else { return nil }
        let id = "\(ge.id)#\(start.timeIntervalSince1970)"
        guard let event = Event(id: id,
                                title: ge.summary,
                                start: start, end: end,
                                calendarColor: ge.calendarColor,
                                externalIdentifier: ge.iCalUID,
                                calendarTitle: ge.calendarSummary,
                                webURL: ge.htmlLink) else { return nil }
        return (event, isAllDay)
    }
}
```

**完了条件**:
- [ ] `grep -n "final class GoogleCalendarGateway" Sources/Toki/Infrastructure/GoogleCalendarGateway.swift` が 1 件
- [ ] `import Combine` が含まれる
- [ ] `@MainActor` で class 修飾されている
- [ ] 公開 API: `timelineUpdates` / `isAuthorized` / `start` / `stop` / `reload` の 5 つ
- [ ] `swift build` 成功（誰も注入してない宙ぶらり状態）
- [ ] `swift test` 36 ケース全 pass
- [ ] ファイル長 < 200 行

**コミット**:
```bash
git add Sources/Toki/Infrastructure/GoogleCalendarGateway.swift
git commit -m "feat(infra): GoogleCalendarGateway を新規作成"
```

**依存**: Task 1

---

## Task 3: ClockViewModel と AppDelegate を GoogleCalendarGateway 経由に切替 + 未接続 UX

**Commit**: `feat(composition+app): ClockViewModel と AppDelegate を GoogleCalendarGateway 経由に切替`

**目的**: ViewModel の `gateway` 型を `GoogleCalendarGateway?` に差替、`accessGranted` の意味を「OAuth 接続済み」に再定義、未接続時の `centerState` 文言を「右クリックで接続」に。AppDelegate の依存組み立てを EventKit から Google API に切替、接続/切断時の `reload()` を await。Task 3+4+5 を統合した 1 commit。

**コンテキスト**:
- 参照: plan §6, §7
- 前提: Task 2 で `GoogleCalendarGateway` 利用可能
- ビルド可能を維持するため統合 commit
- 既存 `requestAccess()` 呼び出し（EventKit 用）を撤去
- `accessGranted` の型・public シグネチャは変えない（意味だけ再定義）

**実装内容**:

### ファイル 1: `Sources/Toki/Composition/ClockViewModel.swift`（編集）

#### init signature 変更

```swift
private let gateway: GoogleCalendarGateway?

init(gateway: GoogleCalendarGateway?, calendar: Calendar = .current) {
    self.gateway = gateway
    self.calendar = calendar
}
```

#### `start()` 変更

```swift
func start() async {
    accessGranted = gateway?.isAuthorized ?? false

    gateway?.start()
    gateway?.timelineUpdates
        .receive(on: DispatchQueue.main)
        .sink { [weak self] tl in self?.timeline = tl }
        .store(in: &cancellables)

    now = Date()
    scheduleMinuteTimer()

    NSWorkspace.shared.notificationCenter
        .publisher(for: NSWorkspace.didWakeNotification)
        .sink { [weak self] _ in
            guard let self else { return }
            self.now = Date()
            self.scheduleMinuteTimer()
            self.accessGranted = self.gateway?.isAuthorized ?? false
            Task { await self.gateway?.reload() }
        }
        .store(in: &cancellables)
}
```

EventKit 用 `requestAccess()` の呼び出しを撤去。

#### 新規メソッド

```swift
/// OAuth 接続状態を最新に同期する。
/// AppDelegate が beginAuthorization / revoke 完了後に呼び出す。
func refreshAuthorizationState() {
    accessGranted = gateway?.isAuthorized ?? false
}
```

#### `centerState` の subtitle 変更

```swift
var centerState: CenterState {
    let timeStr = Self.formatHHMM(now, calendar: calendar)
    if !accessGranted {
        return .freeTime(time: timeStr, subtitle: "右クリックで接続")
    }
    // 以降は無変更
}
```

#### `AccessResult` への参照削除

`AccessResult` 型は EventKit Gateway のみで使われていた。`ClockViewModel` から参照していた箇所（`if case .granted = result`）を削除。

### ファイル 2: `Sources/Toki/App/AppDelegate.swift`（編集）

#### プロパティ変更

```swift
private var gateway: GoogleCalendarGateway?  // EventKitGateway? を置換
```

#### `applicationDidFinishLaunching` 変更

既存の `EventKitGateway()` 注入箇所を以下に書き換え：

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    let oauth = OAuthConfig.load().map { config in
        GoogleOAuthClient(config: config,
                          keychain: KeychainStore(),
                          receiver: LoopbackOAuthReceiver())
    }
    self.oauthClient = oauth

    let gateway: GoogleCalendarGateway? = oauth.map { client in
        GoogleCalendarGateway(oauthClient: client,
                              api: GoogleCalendarAPI(oauth: client))
    }
    self.gateway = gateway

    let vm = ClockViewModel(gateway: gateway)
    viewModel = vm
    // 既存：window 設定 / vm.start() / status item 設定
}
```

#### `handleConnect` / `handleDisconnect` 変更

```swift
@objc private func handleConnect() {
    Task {
        do {
            try await oauthClient?.beginAuthorization()
            viewModel?.refreshAuthorizationState()
            await gateway?.reload()
        } catch {
            print("OAuth connect failed: \(error)")
        }
    }
}

@objc private func handleDisconnect() {
    Task {
        do {
            try await oauthClient?.revoke()
            viewModel?.refreshAuthorizationState()
            await gateway?.reload()
        } catch {
            print("OAuth disconnect failed: \(error)")
        }
    }
}
```

**完了条件**:
- [ ] `grep -n "GoogleCalendarGateway?" Sources/Toki/Composition/ClockViewModel.swift` で複数件
- [ ] `grep -n "func refreshAuthorizationState" Sources/Toki/Composition/ClockViewModel.swift` が 1 件
- [ ] `grep -n "右クリックで接続" Sources/Toki/Composition/ClockViewModel.swift` が 1 件
- [ ] `grep -nE "requestAccess|AccessResult" Sources/Toki/Composition/ClockViewModel.swift` が 0 件
- [ ] `grep -n "private var gateway: GoogleCalendarGateway?" Sources/Toki/App/AppDelegate.swift` が 1 件
- [ ] `grep -n "EventKitGateway" Sources/Toki/App/AppDelegate.swift` が 0 件
- [ ] `grep -n "gateway?.reload()" Sources/Toki/App/AppDelegate.swift` が複数件（connect + disconnect）
- [ ] `swift build` 成功
- [ ] `swift test` 36 ケース全 pass
- [ ] `./scripts/build-app.sh` 成功

**コミット**:
```bash
git add Sources/Toki/Composition/ClockViewModel.swift Sources/Toki/App/AppDelegate.swift
git commit -m "feat(composition+app): ClockViewModel と AppDelegate を GoogleCalendarGateway 経由に切替"
```

**依存**: Task 2

---

## Task 4: EventKitGateway を削除

**Commit**: `refactor(infra): EventKitGateway を削除`

**目的**: `Sources/Toki/Infrastructure/EventKitGateway.swift` を削除。Task 3 で参照は全て切れているはず。`AccessResult` enum も EventKit 専用なので削除。

**コンテキスト**:
- 参照: plan §8 Phase 4
- 前提: Task 3 で参照を全て切り終えている
- 削除前に grep で参照ゼロを確認

**実装内容**:

```bash
# 参照確認
grep -rn "EventKitGateway\|AccessResult" Sources/ | grep -v "EventKitGateway.swift"
# → 何もマッチしないことを確認

# 削除
git rm Sources/Toki/Infrastructure/EventKitGateway.swift
```

**完了条件**:
- [ ] `Sources/Toki/Infrastructure/EventKitGateway.swift` が **存在しない**
- [ ] `grep -rn "import EventKit" Sources/` が 0 件
- [ ] `grep -rn "EventKitGateway\|AccessResult" Sources/` が 0 件
- [ ] `swift build` 成功
- [ ] `swift test` 36 ケース全 pass
- [ ] `./scripts/build-app.sh` 成功

**コミット**:
```bash
git rm Sources/Toki/Infrastructure/EventKitGateway.swift
git commit -m "refactor(infra): EventKitGateway を削除"
```

**依存**: Task 3

---

## Task 5: GoogleCalendarAPI から fetchHTMLLinks 系を削除

**Commit**: `refactor(infra): GoogleCalendarAPI から fetchHTMLLinks 系を削除`

**目的**: spec 005 で導入したが spec 006 では不要になった `fetchHTMLLinks(forICalUIDs:)` 公開メソッドと、private helper `findHTMLLink` / `fetchHTMLLink`（単数）を削除。

**コンテキスト**:
- 参照: plan §5 削除箇所
- 前提: Task 4 で EventKitGateway 削除済み（fetchHTMLLinks を呼んでいた箇所）
- `fetchCalendars` は Task 1 で導入済み、これを通じて `fetchTodayEvents` から呼ばれる

**実装内容**:

ファイル: `Sources/Toki/Infrastructure/GoogleCalendarAPI.swift`（編集）

削除する 3 つのメソッド：
1. `func fetchHTMLLinks(forICalUIDs uids: [String]) async throws -> [String: URL]`
2. `private func findHTMLLink(uid: String, calendars: [String], token: String) async -> URL?`
3. `private func fetchHTMLLink(uid: String, calendarId: String, token: String) async -> URL?`

なお、Task 1 で `fetchCalendarIds` を `fetchCalendars` にリネーム済みなので、それは維持する。

**完了条件**:
- [ ] `grep -n "func fetchHTMLLinks\|func findHTMLLink\|func fetchHTMLLink(" Sources/Toki/Infrastructure/GoogleCalendarAPI.swift` が 0 件
- [ ] `grep -n "func fetchTodayEvents\|func fetchCalendars" Sources/Toki/Infrastructure/GoogleCalendarAPI.swift` が各 1 件（維持確認）
- [ ] `swift build` 成功
- [ ] `swift test` 36 ケース全 pass
- [ ] `./scripts/build-app.sh` 成功

**コミット**:
```bash
git add Sources/Toki/Infrastructure/GoogleCalendarAPI.swift
git commit -m "refactor(infra): GoogleCalendarAPI から fetchHTMLLinks 系を削除"
```

**依存**: Task 4

---

## Task 6: Info.plist から NSCalendarsUsageDescription を削除

**Commit**: `chore: Info.plist から NSCalendarsUsageDescription を削除`

**目的**: EventKit を使わなくなったため、macOS Calendar 権限ダイアログをユーザーに見せる必要がなくなる。

**コンテキスト**:
- 参照: plan §3
- 前提: Task 4 で EventKit 撤去済み

**実装内容**:

ファイル: `Resources/Info.plist`（編集）

`NSCalendarsUsageDescription` キーと value を削除。

```bash
# 削除前に念のため確認
grep -n "NSCalendarsUsageDescription" Resources/Info.plist
```

Edit で当該行を削除（XML フォーマット維持）：

```xml
	<key>NSCalendarsUsageDescription</key>
	<string>カレンダーの予定を時計上に表示するために使用します</string>
```

の 2 行を削除。

**完了条件**:
- [ ] `grep -n "NSCalendarsUsageDescription" Resources/Info.plist` が 0 件
- [ ] `plutil -lint Resources/Info.plist` が `OK` を返す
- [ ] `swift build` 成功
- [ ] `swift test` 36 ケース全 pass
- [ ] `./scripts/build-app.sh` 成功し `.build/Toki.app` が再生成される

**コミット**:
```bash
git add Resources/Info.plist
git commit -m "chore: Info.plist から NSCalendarsUsageDescription を削除"
```

**依存**: Task 4

---

## Task 7: SPEC.md を spec 006 整合に更新

**Commit**: `docs(spec): SPEC.md を spec 006 整合に更新`

**目的**: SPEC.md の EventKit 言及を Google Calendar API 単独運用に書き換え、docs の整合性を保つ。

**コンテキスト**:
- 参照: spec 006 §AC「既存挙動の維持」
- 前提: spec 005 までで段階的に更新されている
- spec 006 で EventKit 撤去された旨を明記、Google API 経由の event 取得を主軸に

**実装内容**:

ファイル: `SPEC.md`（編集）

Read で現状確認、以下の方向で更新：

### §3「技術スタック」相当

- `EventKit（カレンダーデータ）` を削除
- 新しい記述：`Google Calendar API（OAuth 2.0 + REST、event 取得）`

### §4「アーキテクチャ」相当

- `Infrastructure` 配下の記述から `EventKitGateway` を削除
- 追加：`GoogleCalendarGateway`、`GoogleCalendarAPI`、`GoogleOAuthClient`、`KeychainStore`、`OAuthConfig`、`LoopbackOAuthReceiver`

### §7「実装メモ・落とし穴」相当

- `EventKit 権限要求` セクションを削除
- 追加：`OAuth 2.0 (Loopback IP) フロー` 概要

### Phase 言及

- Phase 2 で「再読込メニュー」を追加予定の旨を追記

### 注意事項

- §2「ウィンドウ」/「時計」/「イベント円弧」など描画系は無変更
- §10「Claude Code への指示」など Phase 2 / 3 言及はそのまま
- spec 003 / 004 / 005 で更新済みの記述（クリック挙動など）は spec 005 で `htmlLink` ベース、spec 006 で「常に Google API 経由」に統一

**完了条件**:
- [ ] `grep -nE "spec 006|Google Calendar API|GoogleCalendarGateway" SPEC.md` が複数件マッチ
- [ ] `grep -nE "EventKit|NSCalendarsUsageDescription" SPEC.md` が 0 件（or 歴史的経緯のみ）
- [ ] `grep -nE "/r/event\?eid=" SPEC.md` が 1 件以上マッチ（detail URL 形式）
- [ ] `swift build` / `swift test` への影響なし

**コミット**:
```bash
git add SPEC.md
git commit -m "docs(spec): SPEC.md を spec 006 整合に更新"
```

**依存**: Task 6

---

## Task 8: CLAUDE.md の Infrastructure 記述を spec 006 整合に更新

**Commit**: `docs(claude): CLAUDE.md の Infrastructure 記述を spec 006 整合に更新`

**目的**: CLAUDE.md のディレクトリ構造表で「Infrastructure: EventKit ↔ Domain の変換」と書かれている箇所を Google Calendar API ベースに更新。

**コンテキスト**:
- 参照: plan §8 Phase 6
- 前提: Task 7 で SPEC.md 更新済み
- CLAUDE.md は project root にあり、グローバル規約を定義

**実装内容**:

ファイル: `CLAUDE.md`（編集）

Read で現状確認、`Infrastructure/` のコメント部分を更新：

旧：
```
├── Infrastructure/  # EventKit ↔ Domain の変換
```

新：
```
├── Infrastructure/  # Google Calendar API / OAuth クライアント、Domain への変換
```

その他、`EventKit` 言及があれば spec 006 整合に置き換え（grep で全数チェック）。

**完了条件**:
- [ ] `grep -nE "EventKit" CLAUDE.md` が 0 件（or 歴史的経緯のみ）
- [ ] `grep -nE "Google Calendar API|OAuth" CLAUDE.md` が 1 件以上マッチ
- [ ] `swift build` / `swift test` への影響なし

**コミット**:
```bash
git add CLAUDE.md
git commit -m "docs(claude): CLAUDE.md の Infrastructure 記述を spec 006 整合に更新"
```

**依存**: Task 7

---

## 全 task 完了後

### 回帰確認

- [ ] `swift test`：Domain 36 ケース全 pass
- [ ] `./scripts/build-app.sh && open .build/Toki.app`：実機目視で spec 006 §AC の項目を walkthrough

### 手動チェックリスト

| # | 項目 | 期待挙動 |
|---|---|---|
| M1 | oauth.json なしで起動 | 中央「右クリックで接続」、円弧 0、針動く、メニューに「接続」項目なし |
| M2 | oauth.json あり・未接続 | 中央「右クリックで接続」、メニューに「接続」表示 |
| M3 | 接続フロー | consent → loopback → 「切断」メニュー切替 → 数秒で円弧表示 |
| M4 | 接続後即時表示 | handleConnect 完了直後に event 描画 |
| M5 | 円弧クリック | ブラウザで htmlLink（ENEOS / Workspace event 含む全て） |
| M6 | ホバーツールチップ | spec 003 通り |
| M7 | 5 分後 reload | event 一覧再 fetch |
| M8 | 切断 | 中央「右クリックで接続」、円弧消失 |
| M9 | wake 復帰 | now 更新 + reload + accessGranted 再判定 |
| M10 | 1 分タイマー | now 更新のみ、event reload なし |
| M11 | カレンダー権限ダイアログ | 出ない |
| M12 | アプリ再起動 | 接続状態維持 |
| M13 | ネット切断 | クラッシュなし、last-known 維持 |
| M14 | all-day event | 表示されない |

### コードベース確認

- [ ] `grep -rn "import EventKit" Sources/` → 0 件
- [ ] `grep -rn "EventKitGateway\|AccessResult" Sources/` → 0 件
- [ ] `grep -rn "fetchHTMLLinks\|findHTMLLink\|enrichWithHTMLLinks\|htmlLinkCache" Sources/` → 0 件
- [ ] `grep -rn "NSCalendarsUsageDescription" Resources/` → 0 件

### コードレビュー

- `code-reviewer` agent で全体レビュー：
  - 依存方向：Domain / Infrastructure / Composition / UI / App 各層の責務逸脱なし
  - GoogleCalendarGateway の責務分離（API client / OAuth client から独立）
  - エラーハンドリングの一貫性（silent fail、last-known 維持）
  - ファイル長 < 400 行 / 関数長 < 50 行
  - 不要な protocol 切り出しなし
