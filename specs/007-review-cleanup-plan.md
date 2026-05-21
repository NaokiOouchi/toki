# 007 — レビュー後片付け 技術プラン

`specs/007-review-cleanup.md` を技術プランに展開したもの。`/tasks` で atomic task に分解する元となる。

## 0. 確定済み設計判断

ユーザーとの合意事項：

1. **H1 対応方式**：`GoogleCalendarGateway` に `@Published private(set) var isAuthorized: Bool` を新設、ViewModel が `gateway?.$isAuthorized` を sink して `accessGranted` を自動同期
2. **同期トリガー**：`reload()` 完了時に `oauthClient.isAuthorized` で再評価 + `@Published` 更新（Timer ポーリング不採用）
3. **AppDelegate の `refreshAuthorizationState()` 呼び出し**：保険として残す
4. **dead field 削除**：`Event` から `calendarTitle` / `externalIdentifier` を完全撤去（reading なし）。`GoogleAPIEvent` の `iCalUID` / `calendarSummary` は Infrastructure 中間型として残置
5. **HTTP status 検査**：`for attempt in 0..<2` で 401 のみ 1 回 retry、それ以外の non-2xx は log + 空配列
6. **revoke 整理**：空 if を log 化 + Keychain クリアを do/catch の外に移して network error 時も確実実行
7. **SPEC.md §5 は既に整合済み**（`calendarTitle` 不在、`webURL` 既載）→ Task 5（SPEC.md commit）は不要、satisfied by inspection
8. **`testInit_normal` のアサーション削除**：`XCTAssertEqual(e?.externalIdentifier, "ext-1")` 1 行削除のみ（ケース数 36 維持）
9. **`fetchCalendars` 側の retry は実装しない**（複雑化回避、確率も低い）

## 1. Requirements restatement

spec 006 後の code-reviewer agent レビューで指摘された HIGH 5 件 + SPEC.md 整合を 1 iteration で片付ける。H1（refresh 失敗時の UI 復旧経路）、H2/H3（dead field 削除）、H4（HTTP status + 401 retry）、H5（revoke 空 if 整理）を順に対応。Domain テスト 36 ケースは無変更で全 pass を維持（`testInit_normal` の 1 アサーションのみ削除、ケース数は維持）。

## 2. Open Questions — 解決済み

spec 007 の 7 項目すべて [CONFIDENT]：

| # | 論点 | 判断 |
|---|---|---|
| 1 | `isAuthorized` 公開方式 | `@Published private(set) var` を Gateway に新設 |
| 2 | 同期トリガー | `reload()` 完了時に再評価 |
| 3 | `refreshAuthorizationState()` 残す | 保険として残す（明示性向上） |
| 4 | SPEC.md 更新範囲 | §5 は既に整合済み、Task 5 省略 |
| 5 | `calendarTitle` の将来用途 | Phase 3 で再導入で OK |
| 6 | 401 retry 回数 | 1 回まで（`for attempt in 0..<2`） |
| 7 | 並列他 calendar への影響 | 個別 1 回 retry のみ |

[NEEDS INPUT] = 0 件。

## 3. ファイル別変更計画

### Task 1（dead field 削除、8 ファイル）

| パス | 変更 | 想定差分 |
|---|---|---|
| `Sources/Toki/Domain/Event.swift` | struct から `calendarTitle` / `externalIdentifier` 削除、init 引数からも削除 | -10/+0 |
| `Sources/Toki/Domain/DayTimeline.swift` | `clip(_:)` 内 `Event(...)` から該当引数削除 | -2/+0 |
| `Sources/Toki/UI/RenderableEvent.swift` | struct から該当 field 削除 | -6/+0 |
| `Sources/Toki/Composition/ClockViewModel.swift` | `canvasEvents` で RenderableEvent init 引数削除 | -2/+0 |
| `Sources/Toki/Infrastructure/GoogleCalendarGateway.swift` | `convert(_:)` で Event init 引数削除 | -2/+0 |
| `Tests/TokiTests/EventTests.swift` | ヘルパ引数削除 + `testInit_normal` のアサーション 1 行削除 | -5/+1 |
| `Tests/TokiTests/EventStatusTests.swift` | ヘルパ引数削除 | -3/+1 |
| `Tests/TokiTests/DayTimelineTests.swift` | ヘルパ引数削除 | -3/+1 |

### Task 2（isAuthorized sync、2 ファイル）

| パス | 変更 | 想定差分 |
|---|---|---|
| `Sources/Toki/Infrastructure/GoogleCalendarGateway.swift` | `@Published isAuthorized` 新設、`ObservableObject` 適合、init/start/reload で再評価 | +8/-2 |
| `Sources/Toki/Composition/ClockViewModel.swift` | `start()` で `gateway?.$isAuthorized` sink 追加 | +5/-0 |

### Task 3（HTTP status + 401 retry、1 ファイル）

| パス | 変更 | 想定差分 |
|---|---|---|
| `Sources/Toki/Infrastructure/GoogleCalendarAPI.swift` | `fetchEvents` を `for attempt in 0..<2` の retry 構造に書き換え | +25/-8 |

### Task 4（revoke 整理、1 ファイル）

| パス | 変更 | 想定差分 |
|---|---|---|
| `Sources/Toki/Infrastructure/GoogleOAuthClient.swift` | `revoke()` の空 if を log 化、Keychain クリアを do/catch の外に | +10/-3 |

## 4. H1 isAuthorized Sync 詳細

### `GoogleCalendarGateway` 変更

現在 computed property の `isAuthorized` を `@Published` に昇格。`ObservableObject` 適合を明示。

```swift
@MainActor
final class GoogleCalendarGateway: ObservableObject {
    @Published private(set) var isAuthorized: Bool = false

    init(...) {
        // 既存初期化
        self.isAuthorized = oauthClient.isAuthorized
    }

    func start() {
        reloadTimerCancellable?.cancel()
        isAuthorized = oauthClient.isAuthorized
        Task { await reload() }
        // 5 分間隔タイマー（既存）
    }

    func reload() async {
        let timeline = await fetchTodayTimeline()
        // refresh 失敗で Keychain クリアされていれば isAuthorized=false に転落
        isAuthorized = oauthClient.isAuthorized
        subject.send(timeline)
    }
}
```

### `ClockViewModel.start()` 変更

既存初期評価 + `@Published` sink を追加：

```swift
func start() async {
    accessGranted = gateway?.isAuthorized ?? false  // 既存

    gateway?.start()

    // 新規：isAuthorized 変化を自動同期
    gateway?.$isAuthorized
        .receive(on: DispatchQueue.main)
        .sink { [weak self] granted in self?.accessGranted = granted }
        .store(in: &cancellables)

    gateway?.timelineUpdates
        .receive(on: DispatchQueue.main)
        .sink { [weak self] tl in self?.timeline = tl }
        .store(in: &cancellables)

    // 以下既存（minute timer / wake notification）
}
```

`refreshAuthorizationState()` は保険として維持（AppDelegate.handleConnect/Disconnect から呼ばれる）。

## 5. H2 + H3 dead field 削除詳細

### Domain `Event`

```swift
struct Event: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let calendarColor: CGColor
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

### `DayTimeline.clip(_:)`

```swift
return Event(id: event.id, title: event.title,
             start: newStart, end: newEnd,
             calendarColor: event.calendarColor,
             webURL: event.webURL)
```

### `RenderableEvent`

```swift
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
```

### `ClockViewModel.canvasEvents`

```swift
RenderableEvent(
    id: ev.id, title: ev.title,
    startAngle: ..., endAngle: ...,
    color: ev.calendarColor,
    status: ev.status(at: now),
    start: ev.start, end: ev.end,
    webURL: ev.webURL
)
```

### `GoogleCalendarGateway.convert(_:)`

```swift
private static func convert(_ ge: GoogleAPIEvent) -> (Event, Bool)? {
    let isAllDay = ge.start.dateTime == nil
    guard let start = ge.start.dateTime ?? ge.start.date,
          let end = ge.end.dateTime ?? ge.end.date else { return nil }
    let id = "\(ge.id)#\(start.timeIntervalSince1970)"
    guard let event = Event(id: id, title: ge.summary,
                            start: start, end: end,
                            calendarColor: ge.calendarColor,
                            webURL: ge.htmlLink) else { return nil }
    return (event, isAllDay)
}
```

`GoogleAPIEvent.iCalUID` / `calendarSummary` は Infrastructure 中間型として残置（API レスポンスから読むだけで Domain には流さない、Phase 3 で再活用余地）。

### テストヘルパ

各 `makeEvent` から `calendarTitle: String = ""` / `externalIdentifier: String? = nil` 引数を削除。`testInit_normal` の `XCTAssertEqual(e?.externalIdentifier, "ext-1")` 1 行も削除（field 削除に伴う不可避の変更）。

## 6. H4 HTTP status + 401 retry 詳細

`GoogleCalendarAPI.fetchEvents` を書き換え：

```swift
private func fetchEvents(in cal: GoogleAPICalendar,
                         timeMin: String, timeMax: String,
                         token initialToken: String) async -> [GoogleAPIEvent] {
    let encodedId = cal.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cal.id
    let urlStr = "\(Self.baseURL)/calendars/\(encodedId)/events?timeMin=\(timeMin)&timeMax=\(timeMax)&singleEvents=true&orderBy=startTime&maxResults=250"
    guard let url = URL(string: urlStr) else { return [] }

    var token = initialToken
    for attempt in 0..<2 {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

            if statusCode == 401 && attempt == 0 {
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

特徴：
- `for attempt in 0..<2` で 2 回上限を強制
- 401 のみ retry、それ以外の non-2xx は log + 空配列
- network error は log + 空配列（既存挙動と同じ）

## 7. H5 revoke 整理詳細

`GoogleOAuthClient.revoke()` を書き換え：

```swift
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
- 空 if 文を削除、non-2xx は log 1 行
- network error も log（既存は throw が外まで突き抜けていた）
- Keychain クリアを do/catch の外に出して network error 時も確実実行（**既存軽微バグの修正**）

## 8. SPEC.md 整合詳細

planner が SPEC.md §5 を確認した結果、Event 定義は：
```swift
struct Event: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let calendarColor: CGColor
    let webURL: URL?
}
```
となっており、`calendarTitle` / `externalIdentifier` は元から記載なし。`webURL: URL?` も既に記載済み。**SPEC.md 側は実質変更不要**。spec 007 §AC「SPEC.md §5 を整合」は satisfied by inspection として扱い、commit を作らない。

## 9. 実装フェーズ順序

**4 commits**：

### Task 1: dead field 削除（8 ファイル統合 commit）
`refactor(domain+ui+infra+composition): Event から calendarTitle / externalIdentifier を削除`

Event signature 変更は全レイヤーに同時に波及するため、中間 commit を切ると build error 不可避。1 commit にまとめる（spec 006 Task 3 統合と同じ判断）。

- 検証：`swift build && swift test` 成功、Domain 36 ケース pass
- 依存：なし（最初に実施）
- リスク：低（reading 側ゼロを grep 済み、コンパイル時の型エラーで全箇所検出可能）

### Task 2: isAuthorized sync（2 ファイル統合 commit）
`feat(infra+composition): GoogleCalendarGateway に @Published isAuthorized を追加し ViewModel が sink`

- 検証：実機で refresh 失効時に「右クリックで接続」へ自動切替
- 依存：Task 1（GoogleCalendarGateway 同ファイルを触るため conflict 回避目的で順序固定）
- リスク：中（`@Published` 発火タイミングと `@MainActor` の絡み、`receive(on: .main)` で安全側に倒す）

### Task 3: HTTP status + 401 retry
`feat(infra): GoogleCalendarAPI に HTTP status 検査と 401 retry`

- 検証：手動。`print` 出力で 401 retry 動作確認
- 依存：なし
- リスク：低（既存挙動の延長、silent fail を log fail に）

### Task 4: revoke 整理
`refactor(infra): GoogleOAuthClient.revoke の空 if 文を log に置換`

- 検証：手動。切断時の挙動と Task 2 sink 経路で `accessGranted` 同期
- 依存：なし
- リスク：低（既存挙動の改善）

### Task 5（不要）：SPEC.md
SPEC.md §5 は既に整合済みのため commit 作成不要。

## 10. リスク

| リスク | 評価 | 緩和策 |
|---|---|---|
| Domain テスト 36 ケース影響 | 中 | ヘルパ引数削除 + `testInit_normal` の 1 アサーション削除、ケース数 36 維持 |
| `@Published isAuthorized` Combine sink で再描画頻度増 | 低 | `reload()` 完了時のみ更新（5 分間隔）、Bool 値変化点少 |
| 401 retry 無限ループ | 低 | `for attempt in 0..<2` で 2 回上限 |
| `ObservableObject` 適合追加の連鎖 | 低 | AppDelegate は `gateway` を `private var` で保持のみ、UI 連鎖なし |
| `gateway?.$isAuthorized` の nil-coalescing | 低 | gateway が nil ならそもそも sink しない、`accessGranted = false` 維持で「右クリックで接続」表示 |
| ファイル長 / 関数長 | 低 | Event -10 行、API +15 行程度、全制約クリア |

## 11. テスト方針

### 自動
- Domain 36 ケース全 pass（`swift test`）
- 新規ケース追加なし（spec 007 §Non-goals）
- `testInit_normal` の `externalIdentifier` アサーション 1 行削除

### 手動チェックリスト
| # | 項目 | 期待 |
|---|---|---|
| M1 | 起動 → 接続済みなら event 表示、未接続なら「右クリックで接続」 | OK |
| M2 | 接続 / 切断 → 中央テキスト即座に切替 | OK |
| M3 | **H1 確認**：Keychain Access.app で refresh_token を破壊 → 5 分以内の reload で「右クリックで接続」に転落 | OK |
| M4 | **H4 確認**：Console.app で 401 retry の log 確認（任意） | OK |
| M5 | **H5 確認**：切断時に network 切断状態でも Keychain クリア成功（任意） | OK |

## 12. Out of scope

spec 007 §Non-goals 再掲：
- Phase 2 機能（右クリック「再読込」、ウィンドウ位置記憶、接続中スピナー）
- 新規 protocol 切り出し
- 新規外部ライブラリ追加
- 追加 UI 変更
- OAuth フロー全体の見直し
- 指数バックオフ等高度化
- 新規 Domain テスト追加
- `print` → `os_log` 置換（M1）
- コードレビュー M2〜M6 / LOW 全件
- `GoogleAPIEvent.iCalUID` / `calendarSummary` 削除
- `fetchCalendars` 側の 401 retry

## 参考ファイル

- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/specs/007-review-cleanup.md`
- spec 006 plan：`/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/specs/006-google-only-plan.md`

次のステップ：`/tasks 007-review-cleanup` で 4 atomic task ファイル化 → fresh subagent で 1 commit ずつ実装。
