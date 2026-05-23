# 012 — next-future-event 技術プラン

`specs/012-next-future-event.md` を技術プランに展開したもの。`/tasks` で atomic task に分解する元となる。

## 0. 確定済み設計判断（10 項目すべて [CONFIDENT]）

| # | 論点 | 判断 |
|---|---|---|
| 1 | fetch 範囲 | 7 日先まで |
| 2 | fetch シグネチャ rename | `fetchTodayEvents` → `fetchEventsAhead(timeMin:timeMax:)` |
| 3 | 「今週内」定義 | 3〜6 日後、曜日名 |
| 4 | 曜日名フォーマット | `日曜` / `月曜` 等、日本語ハードコード（ロケール非依存） |
| 5 | 7 日先（境界）表示 | `5/26 (月) HH:MM タイトル` |
| 6 | タイムゾーン | localTimeZone |
| 7 | `nextLineState` 選択ロジック配置 | ClockViewModel computed property 内 |
| 8 | `nextFutureEvent` Equatable | id ベース（Event 自動合成） |
| 9 | 日付ラベル表示位置 | 時刻の前、1 行 |
| 10 | テストヘルパ拡張 | `NextLineState.init` に `dateLabel: String? = nil` |

## 1. Requirements restatement

今日の予定が空 / 全終了で NextEventLine が空になる pain を解消。Google Calendar API fetch 範囲を「今日 → 7 日先まで」に拡張し、明日以降の最初の未来 event を「次 明日 14:00 タイトル」のように日付ラベル付きで NextEventLine に表示する。今日の予定がある間は既存挙動を完全維持。Domain 層は無変更、Composition / Infrastructure / UI のみで完結。

## 2. ファイル別変更計画

新規 0 ファイル + 編集 5 ファイル：

| パス | 編集内容 | 想定差分 |
|---|---|---|
| `Sources/Toki/Infrastructure/GoogleCalendarAPI.swift` | `fetchTodayEvents` → `fetchEventsAhead` rename + doc コメント | +2 / -2 |
| `Sources/Toki/Infrastructure/GoogleCalendarGateway.swift` | 7 日 fetch + `@Published nextFutureEvent` + 今日/未来分離 + all-day 除外 | +25 |
| `Sources/Toki/UI/NextEventLine.swift` | `NextLineState.dateLabel` 追加 + `displayText` helper | +10 |
| `Sources/Toki/Composition/ClockViewModel.swift` | `nextFutureEvent` sink + `nextLineState` 拡張 + `formatDateLabel` helpers | +50 |
| `SPEC.md`（任意） | spec 012 完了反映 | +2 |

合計：**編集 5 ファイル**

## 3. Infrastructure 詳細

### 3.1 API rename
```swift
// 変更：func fetchTodayEvents → func fetchEventsAhead
// 内部実装無変更、events.list の query が timeMin/timeMax のみで N 日対応
func fetchEventsAhead(timeMin: Date, timeMax: Date) async throws -> [GoogleAPIEvent]
```

### 3.2 Gateway fetch 拡張

```swift
@Published private(set) var nextFutureEvent: Event? = nil

private func fetchTimelineAndNextFuture() async -> (DayTimeline, Event?) {
    let dayStart = calendar.startOfDay(for: Date())
    guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart),
          let weekEnd = calendar.date(byAdding: .day, value: 7, to: dayStart) else {
        return (DayTimeline(date: dayStart, events: []), nil)
    }
    guard oauthClient.isAuthorized else {
        return (DayTimeline(date: dayStart, events: []), nil)
    }
    do {
        let apiEvents = try await api.fetchEventsAhead(timeMin: dayStart, timeMax: weekEnd)

        var todayRaw: [Event] = []
        var todayAllDay: [Bool] = []
        var futureEvents: [Event] = []
        for ge in apiEvents {
            guard let (event, isAllDay) = Self.convert(ge) else { continue }
            if event.start < dayEnd {
                todayRaw.append(event)
                todayAllDay.append(isAllDay)
            } else if !isAllDay {
                // 明日以降の all-day は時刻ラベル付けられないため除外
                futureEvents.append(event)
            }
        }
        let timeline = DayTimeline.make(date: dayStart,
                                        rawEvents: todayRaw,
                                        allDayFlags: todayAllDay,
                                        calendar: calendar)
        let nextFuture = futureEvents.sorted { $0.start < $1.start }.first
        return (timeline, nextFuture)
    } catch {
        print("Google Calendar API fetch failed: \(error)")
        return (subject.value, self.nextFutureEvent)
    }
}

func reload() async {
    let (timeline, nextFuture) = await fetchTimelineAndNextFuture()
    isAuthorized = oauthClient.isAuthorized
    lastReloadAt = Date()
    nextFutureEvent = nextFuture
    subject.send(timeline)
}
```

## 4. Composition 詳細

### 4.1 nextFutureEvent 購読

```swift
@Published private(set) var nextFutureEvent: Event? = nil

// start() 内：
gateway?.$nextFutureEvent
    .receive(on: DispatchQueue.main)
    .sink { [weak self] ev in self?.nextFutureEvent = ev }
    .store(in: &cancellables)
```

### 4.2 nextLineState 選択ロジック拡張

```swift
var nextLineState: NextLineState? {
    guard accessGranted else { return nil }

    // 今日の予定残あり → 既存ロジック（日付ラベルなし）
    if let tl = timeline, let nxt = tl.nextEvent(after: now) {
        return NextLineState(
            timeHHMM: Self.formatHHMM(nxt.start, calendar: calendar),
            title: nxt.title,
            dateLabel: nil
        )
    }

    // spec 012: 今日の予定残ゼロ → 明日以降の最初の未来 event
    if let future = nextFutureEvent {
        return NextLineState(
            timeHHMM: Self.formatHHMM(future.start, calendar: calendar),
            title: future.title,
            dateLabel: Self.formatDateLabel(future.start, relativeTo: now, calendar: calendar)
        )
    }
    return nil
}
```

### 4.3 formatDateLabel helper（private static）

```swift
private static func formatDateLabel(_ target: Date,
                                    relativeTo now: Date,
                                    calendar: Calendar) -> String? {
    let nowDay = calendar.startOfDay(for: now)
    let targetDay = calendar.startOfDay(for: target)
    let comps = calendar.dateComponents([.day], from: nowDay, to: targetDay)
    guard let dayDiff = comps.day else { return nil }
    switch dayDiff {
    case ..<1: return nil
    case 1: return "明日"
    case 2: return "明後日"
    case 3...6: return weekdayName(of: target, calendar: calendar)
    default: return shortDateLabel(of: target, calendar: calendar)
    }
}

private static func weekdayName(of date: Date, calendar: Calendar) -> String {
    let weekday = calendar.component(.weekday, from: date)  // 1=日, 2=月, ...
    let names = ["日曜", "月曜", "火曜", "水曜", "木曜", "金曜", "土曜"]
    return names[max(1, min(7, weekday)) - 1]
}

private static func shortDateLabel(of date: Date, calendar: Calendar) -> String {
    let c = calendar.dateComponents([.month, .day], from: date)
    let m = c.month ?? 1
    let d = c.day ?? 1
    let weekday = calendar.component(.weekday, from: date)
    let shortNames = ["日", "月", "火", "水", "木", "金", "土"]
    return "\(m)/\(d) (\(shortNames[max(1, min(7, weekday)) - 1]))"
}
```

## 5. UI 詳細

### 5.1 NextLineState 拡張

```swift
struct NextLineState: Equatable {
    let timeHHMM: String
    let title: String
    let dateLabel: String?

    init(timeHHMM: String, title: String, dateLabel: String? = nil) {
        self.timeHHMM = timeHHMM
        self.title = title
        self.dateLabel = dateLabel
    }
}
```

### 5.2 NextEventLine の表示

```swift
Text(displayText(s))
    .font(.system(size: 11 * textScale))
    .foregroundStyle(.secondary)
    .lineLimit(2)
    .truncationMode(.tail)

private func displayText(_ s: NextLineState) -> String {
    if let label = s.dateLabel {
        return "\(label) \(s.timeHHMM) \(s.title)"
    }
    return "\(s.timeHHMM) \(s.title)"
}
```

## 6. 実装フェーズ順序

**5 task**：

1. `refactor(infra): GoogleCalendarAPI.fetchTodayEvents を fetchEventsAhead に rename`
2. `feat(infra): GoogleCalendarGateway の fetch 範囲を 7 日先に拡張し nextFutureEvent を Publish`
3. `feat(ui): NextLineState に dateLabel を追加し NextEventLine の表示拡張`
4. `feat(composition): formatDateLabel + nextFutureEvent 購読 + nextLineState 選択ロジック拡張`
5. （任意）`docs(spec): SPEC.md spec 012 完了反映`

依存：1 → 2 → 3 / 4 → 5

## 7. リスク

| # | リスク | 重大度 | 緩和策 |
|---|---|---|---|
| R1 | fetch 範囲拡張で API レスポンスサイズ増 | 低 | 7 日 × 全 calendar、現状 2 分ポーリングで問題なし |
| R2 | 今日/未来分離ロジックの誤り | 中 | `event.start < dayEnd` の単一条件、手動 E2E で確認 |
| R3 | nextFutureEvent Equatable | 低 | Event 自動合成、id ベース |
| R4 | 日付ラベル整形バグ | 中 | private static helper 1 箇所、`startOfDay` ベース、曜日 index ハードコード |
| R5 | NextEventLine lineLimit(2) の改行 | 低 | textScale 大時のみ、既存挙動と同等の劣化 |
| R6 | Gateway @Published 増加コスト | 低 | Event 1 件、無視できる |
| R7 | DayTimeline 今日 1 日責務維持 | 低 | spec 012 §Non-goals と整合 |
| R8 | Domain テスト影響 | 0 | Domain 無変更 |
| R9 | AppearanceModel との結合 | 低 | textScale 経路無変更 |
| R10 | 7 日先まで何もない | 低 | nextFutureEvent nil → NextEventLine 既存通り空 |
| R11 | 明日以降 all-day event | 中 | Gateway で明示除外 |
| R12 | reload 失敗時の挙動 | 低 | last-known 維持（spec 008 と整合） |
| R13 | accessGranted ガード順序 | 低 | nextLineState 冒頭で維持 |

## 8. テスト方針

### 自動
- Domain 36 ケース無変更で全 pass
- 新規 Domain テスト追加なし

### 手動チェックリスト
| # | 状況 | 期待表示 |
|---|---|---|
| M1 | 今日予定あり、次 16:00 | `次 16:00 タイトル`（既存） |
| M2 | 今日最終 event 終了後、明日 9:00 | `次 明日 09:00 朝会` |
| M3 | 今日空、明後日 14:00 | `次 明後日 14:00 ミーティング` |
| M4 | 今日空、4 日後 10:00（土曜） | `次 土曜 10:00 個人作業` |
| M5 | 今日空、7 日後の event | `次 5/30 (土) 09:00 出張準備` |
| M6 | 7 日先まで何もない | NextEventLine 空（lastUpdated のみ） |
| M7 | OAuth 未接続 | NextEventLine nil（既存） |
| M8 | ホバー / popover / 円弧 / 設定 / OAuth / リサイズ | 全て無変更 |
| M9 | 進行中 + 次の今日 event | 既存通り（nextFutureEvent 不使用） |
| M10 | 進行中のみ、今日残ゼロ、明日朝会 | `次 明日 09:00 朝会` |

## 9. Out of scope

spec 012 §Non-goals 再掲：
- 30 日以上先の event 検索
- 中央テキスト変更
- 複数日 navigation
- 次未来 event hover / popover / クリック
- 設定で ON/OFF
- 翌日プレビュー / 2 段リング
- タイムゾーン跨ぎ新規対応
- 参加可否操作
- `fields` 絞り込み

## 参考ファイル

- `specs/012-next-future-event.md`
- `specs/010-event-preview-plan.md`
- `specs/011-appearance-model-plan.md`

次のステップ：`/tasks 012-next-future-event` で 5 atomic task ファイル化。
