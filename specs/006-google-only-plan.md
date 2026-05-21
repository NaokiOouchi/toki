# 006 — Google Calendar API 単独運用 技術プラン

`specs/006-google-only.md` を技術プランに展開したもの。`/tasks` で atomic task に分解する元となる。

## 0. 確定済み設計判断

ユーザーとの合意事項：

1. **EventKit 完全撤去**：`EventKitGateway` / `import EventKit` / `NSCalendarsUsageDescription` を削除
2. **Google Calendar API 単独運用**：`events.list` で今日の event を取得 → Domain `Event` 生成
3. **graceful 未接続 state UX**：時計の針は通常通り、円弧 0 件、中央「右クリックで接続」、次の予定非表示
4. **既存 OAuth コンポーネントは流用**：`KeychainStore` / `OAuthConfig` / `LoopbackOAuthReceiver` / `GoogleOAuthClient`
5. **`GoogleCalendarAPI` 拡張**：`fetchTodayEvents(timeMin:timeMax:)` 追加、`fetchHTMLLinks` 系削除、`fetchCalendarIds` → `fetchCalendars`（id + summary + backgroundColor）
6. **`htmlLinkCache` / `enrichWithHTMLLinks` 削除**：fetchTodayEvents が `htmlLink` 込みで返すため不要
7. **Domain 無変更**：`webURL` 等は spec 005 で導入済み
8. **`ClockViewModel.accessGranted` の意味を「OAuth 接続済み」に再定義**：型名は変えず、意味だけ差替（最小変更）
9. **1 分タイマーは now 更新のみ**、event reload は Gateway 内 5 分間隔 + 接続/切断時に手動
10. **iCloud / Outlook / 非 Google CalDAV event は失う**：機能損失として受容
11. **Task 3+4+5（VM/App/UX 文言）は 1 commit に統合**：途中で動かない commit を避ける

## 1. Requirements restatement

spec 005 で導入した Hybrid 構成（EventKit + Google API）を完全撤去し、Google Calendar API 単独運用へ移行。`EventKitGateway` を削除し、新規 `GoogleCalendarGateway` が `events.list` で今日の event を取得 → Domain `Event` に変換 → `DayTimeline` を公開する。setup は 5 → 3 ステップに削減、display 退行（enrichWithHTMLLinks の await 遅延）も解消。OAuth 未接続時は「右クリックで接続」を中央 3 行に表示し時計の針は維持。Domain 36 ケース無変更で全 pass。

## 2. Open Questions — 解決済み

spec 006 の 13 項目すべて [CONFIDENT]：

### Gateway 設計
1. **Gateway 名** → `GoogleCalendarGateway`（特化、protocol 切らず）
2. **all-day 除外場所** → Gateway で `allDayFlags` 構築 → `DayTimeline.make` に渡す
3. **timeMin/Max** → ISO8601 with timezone offset（ローカル）
4. **events.list params** → `singleEvents=true&orderBy=startTime&maxResults=250`

### EventKit 撤去
5. **撤去段取り** → 参照を切り終えた後の独立 commit
6. **EKEventStoreChanged 代替** → MVP は何もしない（Phase 2 で再読込メニュー）
7. **Info.plist** → `NSCalendarsUsageDescription` 削除のみ

### 未接続 UX
8. **CenterState 拡張** → 既存 `.freeTime(time:subtitle:)` を流用
9. **文言** → 「右クリックで接続」

### Refresh
10. **接続/切断時の reload** → AppDelegate から `gateway.reload()` を await
11. **1 分タイマー** → now のみ更新、event reload は Gateway 内 5 分間隔 + 手動

### Domain / 既存
12. **calendarTitle** → API `calendars.list` の `summary`
13. **dryrun** → `oauthClient == nil` 時は gateway も nil、ViewModel は Optional 受け

## 3. ファイル別変更計画

### 新規（1 ファイル）
| パス | 概要 | 想定行数 |
|---|---|---|
| `Sources/Toki/Infrastructure/GoogleCalendarGateway.swift` | events.list で event 取得 → Domain Event 生成 → Publisher 公開、5 分間隔タイマー | 180 |

### 編集
| パス | 変更概要 | 想定差分 |
|---|---|---|
| `Sources/Toki/Infrastructure/GoogleCalendarAPI.swift` | `fetchTodayEvents` 追加、中間型導入、`fetchCalendars` 拡張、`fetchHTMLLinks` 系削除 | +130/-60 |
| `Sources/Toki/Composition/ClockViewModel.swift` | `gateway` 型を `GoogleCalendarGateway?` に、`accessGranted` 意味再定義、`requestAccess` 撤去、`centerState` subtitle 変更、`refreshAuthorizationState` 追加 | +15/-20 |
| `Sources/Toki/App/AppDelegate.swift` | Gateway 注入を `GoogleCalendarGateway` に、接続/切断時の `reload()` await | +20/-10 |
| `Resources/Info.plist` | `NSCalendarsUsageDescription` 削除 | -2 |
| `SPEC.md` | EventKit 言及を Google 単独運用に書き換え | +15/-30 |
| `CLAUDE.md` | Infrastructure の `EventKit` 言及を Google API に更新 | +2/-2 |

### 削除
| パス | 理由 |
|---|---|
| `Sources/Toki/Infrastructure/EventKitGateway.swift` | spec 006 で完全撤去 |

### 影響なし
- `Sources/Toki/Domain/` 全ファイル
- `Sources/Toki/UI/` 全ファイル
- `Sources/Toki/Infrastructure/{KeychainStore,OAuthConfig,LoopbackOAuthReceiver,GoogleOAuthClient}.swift`
- `Sources/Toki/Window/` / `Sources/Toki/App/TokiApp.swift`
- `Tests/TokiTests/` 全 36 ケース

## 4. GoogleCalendarGateway 詳細（新規）

### 構造
```swift
@MainActor
final class GoogleCalendarGateway {
    private let oauthClient: GoogleOAuthClient
    private let api: GoogleCalendarAPI
    private let calendar: Calendar
    private let subject: CurrentValueSubject<DayTimeline, Never>
    private var reloadTimerCancellable: AnyCancellable?

    init(oauthClient:api:calendar:)
    var timelineUpdates: AnyPublisher<DayTimeline, Never>
    var isAuthorized: Bool  // oauthClient.isAuthorized に委譲
    func start()
    func stop()
    func reload() async
    private func fetchTodayTimeline() async -> DayTimeline
    private static func convert(_:) -> (Event, Bool)?  // (Event, isAllDay)
}
```

### `fetchTodayTimeline()` ロジック
```swift
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
        return DayTimeline.make(date: dayStart, rawEvents: rawEvents,
                                allDayFlags: allDayFlags, calendar: calendar)
    } catch {
        print("Google Calendar API fetch failed: \(error)")
        return subject.value  // last-known timeline 維持
    }
}
```

### `convert(_:)`
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
                            externalIdentifier: ge.iCalUID,
                            calendarTitle: ge.calendarSummary,
                            webURL: ge.htmlLink) else { return nil }
    return (event, isAllDay)
}
```

## 5. GoogleCalendarAPI 拡張詳細

### 新規メソッド
```swift
func fetchTodayEvents(timeMin: Date, timeMax: Date) async throws -> [GoogleAPIEvent]
```

フロー：
1. `getValidAccessToken()`
2. `fetchCalendars(token:)` で `[GoogleAPICalendar]` 取得（id + summary + backgroundColor）
3. `withTaskGroup` で各 calendar に `events.list` 並列実行
4. レスポンスを `GoogleAPIEvent` に decode + 親 calendar の summary / color を詰める

### URL
```
GET https://www.googleapis.com/calendar/v3/calendars/<encodedCalendarId>/events
    ?timeMin=<ISO8601>&timeMax=<ISO8601>
    &singleEvents=true&orderBy=startTime&maxResults=250
```

### 中間型（Infrastructure 内）
```swift
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
    let dateTime: Date?  // dateTime あり = time 付き
    let date: Date?      // date のみ = all-day
}

struct GoogleAPICalendar {
    let id: String
    let summary: String
    let backgroundColor: CGColor
}
```

### HEX → CGColor 変換
```swift
private static func cgColor(fromHex hex: String) -> CGColor {
    var s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard s.count == 6, let v = UInt32(s, radix: 16) else {
        return CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
    }
    let r = CGFloat((v >> 16) & 0xFF) / 255
    let g = CGFloat((v >> 8) & 0xFF) / 255
    let b = CGFloat(v & 0xFF) / 255
    return CGColor(red: r, green: g, blue: b, alpha: 1)
}
```

### 削除
- `fetchHTMLLinks(forICalUIDs:)` public
- `findHTMLLink(uid:calendars:token:)` private
- `fetchHTMLLink(uid:calendarId:token:)` private
- `fetchCalendarIds(token:)` private → `fetchCalendars(token:)` にリネーム + 戻り値拡張

## 6. ClockViewModel 詳細

### init signature
```swift
init(gateway: GoogleCalendarGateway?, calendar: Calendar = .current)
```
`gateway` を Optional に。OAuth 未設定（oauth.json なし）の挙動を吸収。

### `start()` 変更
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

`requestAccess()` 呼び出しは撤去（EventKit 専用だった）。

### 追加メソッド
```swift
func refreshAuthorizationState() {
    accessGranted = gateway?.isAuthorized ?? false
}
```
AppDelegate の connect/disconnect 完了後に呼ぶ。

### `centerState` 変更
```swift
if !accessGranted {
    return .freeTime(time: timeStr, subtitle: "右クリックで接続")
}
```

### 無変更
`handleArcTap` / `handleHover` / `canvasEvents` / `nextLineState` / `nowAngle`。`AccessResult` 型への参照は削除。

## 7. AppDelegate 詳細

### 依存組み立て
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
    // 既存：window / status item / Task { await vm.start() }
}
```

### `handleConnect`
```swift
@objc private func handleConnect() {
    Task {
        do {
            try await oauthClient?.beginAuthorization()
            viewModel?.refreshAuthorizationState()
            await gateway?.reload()
        } catch { print("OAuth connect failed: \(error)") }
    }
}
```

### `handleDisconnect`
```swift
@objc private func handleDisconnect() {
    Task {
        do {
            try await oauthClient?.revoke()
            viewModel?.refreshAuthorizationState()
            await gateway?.reload()  // 空 DayTimeline を流す
        } catch { print("OAuth disconnect failed: \(error)") }
    }
}
```

### プロパティ
```swift
private var gateway: GoogleCalendarGateway?  // EventKitGateway? を置換
```

## 8. 実装フェーズ順序

**8 タスク**（Task 3+4+5 統合）：

### Phase 1: API 拡張
1. **`feat(infra): GoogleCalendarAPI に fetchTodayEvents を追加`**
   - 完了条件：`swift build` + 36 ケース pass、既存 `fetchHTMLLinks` は未削除（並存）
   - 依存：なし
   - 想定差分：+130/-0
   - リスク：低

### Phase 2: Gateway 新規作成
2. **`feat(infra): GoogleCalendarGateway を新規作成`**
   - 完了条件：`swift build` + 36 ケース pass（誰も注入してない宙ぶらり状態）
   - 依存：Task 1
   - 想定差分：+180/-0
   - リスク：中（中核ロジック、手動検証で精度確認）

### Phase 3: VM/App/UX 統合切替
3. **`feat(composition+app): ClockViewModel と AppDelegate を GoogleCalendarGateway 経由に切替 + 未接続 UX 文言`**
   - 完了条件：`swift build` + 36 ケース pass、実機で接続/未接続両方の挙動確認
   - 依存：Task 2
   - 想定差分：+35/-30
   - リスク：中（DI 切替、accessGranted セマンティクス変更、UX 文言）

### Phase 4: EventKit 撤去
4. **`refactor(infra): EventKitGateway を削除`**
   - 完了条件：`swift build` + 36 ケース pass、`import EventKit` 0 件
   - 依存：Task 3
   - 想定差分：-150
   - リスク：低（参照先がすべて切れていることを grep で確認）

5. **`refactor(infra): GoogleCalendarAPI から fetchHTMLLinks 系を削除`**
   - 完了条件：`swift build` + 36 ケース pass
   - 依存：Task 4
   - 想定差分：-60
   - リスク：低

### Phase 5: Info.plist
6. **`chore: Info.plist から NSCalendarsUsageDescription を削除`**
   - 完了条件：`swift build` 成功、`./scripts/build-app.sh` 成功
   - 依存：Task 4
   - 想定差分：-2
   - リスク：低

### Phase 6: ドキュメント
7. **`docs(spec): SPEC.md を spec 006 整合に更新`**
   - 完了条件：EventKit 言及削除、Google 単独運用に書き換え
   - 依存：Task 6
   - 想定差分：+15/-30
   - リスク：低

8. **`docs(claude): CLAUDE.md の Infrastructure 記述を spec 006 整合に更新`**
   - 完了条件：CLAUDE.md L23 の「EventKit ↔ Domain」記述を Google Calendar API に更新
   - 依存：Task 7
   - 想定差分：+2/-2
   - リスク：低

## 9. リスク

| # | リスク | 重大度 | 緩和策 |
|---|---|---|---|
| R1 | events.list レスポンスフォーマット差異 | MED | 防御的 decoding、必須欠落は event 単位 skip |
| R2 | calendar HEX → CGColor 変換 | LOW | 6 桁 hex パーサ + gray fallback |
| R3 | 5 分間隔のレート制限 | LOW | 個人利用なら余裕 |
| R4 | 接続直後の fetch 遅延 | LOW | `handleConnect` 内で `await reload()` |
| R5 | Domain テスト 36 影響 | NONE | Domain 無変更 |
| R6 | ファイル長 < 400 行 | LOW | Gateway 180 / API 200 |
| R7 | 関数長 < 50 行 | LOW | helper 分割 |
| R8 | last-known timeline で古いデータ | LOW | API 失敗時のみ |
| R9 | 切断後の timeline 残留 | LOW | `handleDisconnect` で reload → 空 |
| R10 | wake 復帰時の token 期限切れ | LOW | 60 秒マージンで refresh |
| R11 | 多 calendar 並列の例外伝播 | LOW | TaskGroup 内 silent fail |
| R12 | timezone DST 切替 | LOW | ISO8601DateFormatter + startOfDay |
| R13 | recurring occurrence 重複 ID | LOW | `id#timeIntervalSince1970` |
| R14 | iCloud / Outlook event の喪失 | EXPECTED | 受容 |

## 10. テスト方針

### 自動テスト
- Domain 36 ケース全 pass 維持
- 各 commit 後 `swift build` + `swift test`
- 新規自動テスト：なし（CLAUDE.md 規約）

### 手動チェックリスト
| # | 項目 | 期待挙動 |
|---|---|---|
| M1 | oauth.json なしで起動 | 中央「右クリックで接続」、円弧 0、針動く、メニューに「接続」項目なし |
| M2 | oauth.json あり・未接続 | 中央「右クリックで接続」、メニューに「接続」表示 |
| M3 | 接続フロー | consent → loopback → 「切断」メニュー切替 → 数秒で円弧表示 |
| M4 | 接続後即時表示 | handleConnect 完了直後に event 描画 |
| M5 | 円弧クリック | ブラウザで htmlLink |
| M6 | ホバーツールチップ | spec 003 通り |
| M7 | 5 分後 reload | event 一覧再 fetch |
| M8 | 切断 | 中央「右クリックで接続」、円弧消失 |
| M9 | wake 復帰 | now 更新 + reload + accessGranted 再判定 |
| M10 | 1 分タイマー | now 更新のみ、event reload なし |
| M11 | カレンダー権限ダイアログ | 出ない |
| M12 | アプリ再起動 | 接続状態維持 |
| M13 | ネット切断 | クラッシュなし、last-known 維持 |
| M14 | all-day event | 表示されない |

## 11. Out of scope

spec 006 §Non-goals 再掲：
- iCloud / 非 Google CalDAV
- 複数アカウント並列
- 永続キャッシュ
- 完全な設定 UI
- 編集機能 / Meet 参加 / アクションボタン
- `calendar.events` write scope
- アニメーション
- push 通知系自動 reload
- 指数バックオフ
- 外部ライブラリ追加

## 参考ファイル

- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/specs/006-google-only.md`
- 既存 `specs/005-google-calendar-api-plan.md`

次のステップ：`/tasks 006-google-only` で 8 atomic task ファイル化 → fresh subagent で 1 commit ずつ実装。
