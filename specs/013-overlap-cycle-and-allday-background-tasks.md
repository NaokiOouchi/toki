# 013 — overlap-cycle-and-allday-background: Tasks

参照: `specs/013-overlap-cycle-and-allday-background.md` / `specs/013-overlap-cycle-and-allday-background-plan.md`

合計: **11 tasks**

実装順序：上から順。各 task は fresh subagent に渡して 1 commit ずつ（小規模 task はオーケストレータが直接対応も可）。

新規 3 ファイル + 編集 7 ファイル。Domain テスト 33（既存 -3）+ 12（新規）= 45 ケース全 pass 維持。

---

## Task 1: Event を id ベース Hashable 化

**Commit**: `feat(domain): Event を id ベース Hashable 化`

**目的**: OverlapGroup の Hashable 自動合成を可能にする。Equatable は既存通り id ベース、Hashable も同じ id ベースで手動実装。spec 010 の Attendee と同 pattern。

**実装**:

ファイル: `Sources/Toki/Domain/Event.swift`（編集）

末尾の `extension Event: Equatable` に隣接して追加：

```swift
extension Event: Hashable {
    /// Equatable と整合させるため id ベースで実装。
    /// `CGColor` は自動合成 Hashable 不可だが、id だけで一意性が担保される。
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
```

**完了条件**:
```bash
grep -n "extension Event: Hashable" Sources/Toki/Domain/Event.swift
# → 1 件
grep -n "hasher.combine(id)" Sources/Toki/Domain/Event.swift
# → 1 件
swift build && swift test
```

**コミット**:
```bash
git add Sources/Toki/Domain/Event.swift
git commit -m "feat(domain): Event を id ベース Hashable 化"
```

**依存**: なし

---

## Task 2: OverlapGroup を新規追加

**Commit**: `feat(domain): OverlapGroup 値オブジェクトを新規追加`

**目的**: 同じ時間帯に重なる Event を 1 つの value object でまとめる。1 件以上の event を start 昇順で保持し、`event(at:)` で循環参照可能。

**実装**:

ファイル: `Sources/Toki/Domain/OverlapGroup.swift`（新規）

```swift
import Foundation

/// 同じ時間帯に重なる Event のグループを表す Value Object。
/// 1 件以上の event を start 昇順で保持し、相互に時間重複する。
/// 単独 event = events.count == 1 のグループ。
/// 端接触（prev.end == next.start）は別グループ扱い（spec 013 §Open Questions §3）。
struct OverlapGroup: Identifiable, Equatable, Hashable {
    /// 1 件以上、start 昇順で保持。
    let events: [Event]

    /// failable init。空配列は拒否、入力は自動で start 昇順に sort される。
    /// 重なり整合性は呼び出し側（DayTimeline.make の groupOverlaps）の責務。
    init?(events: [Event]) {
        guard !events.isEmpty else { return nil }
        self.events = events.sorted { lhs, rhs in
            lhs.start != rhs.start ? lhs.start < rhs.start : lhs.end < rhs.end
        }
    }

    /// 安定 ID。events[0].id を流用（spec 013 §Open Questions §1）。
    var id: String { events[0].id }

    /// 重なり件数。
    var count: Int { events.count }

    /// 重なりがあるか（count > 1）。
    var isOverlapping: Bool { events.count > 1 }

    /// グループ全体の最早 start（= events[0].start）。
    var start: Date { events[0].start }

    /// グループ全体の最遅 end。groupOverlaps が「最大 end 以下に next.start」を判定するために使う。
    var end: Date { events.map(\.end).max() ?? events[0].end }

    /// index 番目の event を循環参照で取得。
    /// 負数 / count 超過でも modulo で安全に巻き戻る（scroll の wraparound 用）。
    func event(at index: Int) -> Event {
        let c = events.count
        let normalized = ((index % c) + c) % c
        return events[normalized]
    }
}
```

**完了条件**:
```bash
grep -n "struct OverlapGroup" Sources/Toki/Domain/OverlapGroup.swift
grep -n "Identifiable, Equatable, Hashable" Sources/Toki/Domain/OverlapGroup.swift
grep -n "func event(at index: Int)" Sources/Toki/Domain/OverlapGroup.swift
swift build && swift test  # 36 ケース pass
```

**コミット**:
```bash
git add Sources/Toki/Domain/OverlapGroup.swift
git commit -m "feat(domain): OverlapGroup 値オブジェクトを新規追加"
```

**依存**: Task 1

---

## Task 3: OverlapGroupTests を追加

**Commit**: `test(domain): OverlapGroupTests T1-T4 を追加`

**実装**:

ファイル: `Tests/TokiTests/OverlapGroupTests.swift`（新規）

4 テストケース：

```swift
import XCTest
@testable import Toki

final class OverlapGroupTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    private func makeEvent(id: String, hour: Int, durationMinutes: Int = 60) -> Event {
        var c = DateComponents(); c.year = 2026; c.month = 5; c.day = 23; c.hour = hour
        let start = cal.date(from: c)!
        let end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        return Event(
            id: id, title: id, start: start, end: end,
            calendarColor: CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        )!
    }

    // T1: 単独 event の OverlapGroup
    func testSingle_countAndIsOverlapping() {
        let g = OverlapGroup(events: [makeEvent(id: "a", hour: 10)])!
        XCTAssertEqual(g.count, 1)
        XCTAssertFalse(g.isOverlapping)
        XCTAssertEqual(g.event(at: 0).id, "a")
    }

    // T2: 2 件重なりグループ
    func testTwoEvents_countAndAccess() {
        let g = OverlapGroup(events: [makeEvent(id: "a", hour: 10), makeEvent(id: "b", hour: 10)])!
        XCTAssertEqual(g.count, 2)
        XCTAssertTrue(g.isOverlapping)
        XCTAssertEqual(g.event(at: 0).id, "a")
        XCTAssertEqual(g.event(at: 1).id, "b")
    }

    // T3: 循環参照 event(at: 5) == events[5 % count]
    func testCyclicAccess_positive() {
        let g = OverlapGroup(events: [makeEvent(id: "a", hour: 10), makeEvent(id: "b", hour: 10)])!
        XCTAssertEqual(g.event(at: 5).id, "b")  // 5 % 2 == 1
        XCTAssertEqual(g.event(at: 6).id, "a")  // 6 % 2 == 0
    }

    // T4: 負数循環 event(at: -1) == events.last
    func testCyclicAccess_negative() {
        let g = OverlapGroup(events: [makeEvent(id: "a", hour: 10), makeEvent(id: "b", hour: 10)])!
        XCTAssertEqual(g.event(at: -1).id, "b")
        XCTAssertEqual(g.event(at: -2).id, "a")
    }
}
```

**完了条件**:
```bash
swift test 2>&1 | grep "Executed 40 tests"
# → 36 + 4 = 40 ケース全 pass
```

**コミット**:
```bash
git add Tests/TokiTests/OverlapGroupTests.swift
git commit -m "test(domain): OverlapGroupTests T1-T4 を追加"
```

**依存**: Task 2

---

## Task 4: DayTimeline を groups 構造に改修（filterOverlaps 削除）

**Commit**: `feat(domain): DayTimeline を groups + backgroundEvents 構造に改修、filterOverlaps 削除`

**目的**: 既存 `events: [Event]` フィールドを撤廃し、`groups: [OverlapGroup]` + `backgroundEvents: [Event]` に構造変更。後方互換のため `events` は computed property、`init(date:events:)` は単独グループ群を生成する init として維持。古い `filterOverlaps` メソッドは完全削除。

**注意**: 本 task では `make` は **groupOverlaps / 24h 検出を実装しない**（Task 5 で実装）。`make` 内部の clip + sort 処理は維持し、`filterOverlaps` 呼び出しを `groupOverlaps`（後で実装する placeholder）に置き換えるが、placeholder としては各 event を単独 group にする仮実装で OK。

**実装**:

ファイル: `Sources/Toki/Domain/DayTimeline.swift`（編集）

完全書き換えに近い：

```swift
import Foundation

/// 今日 1 日の event timeline。
/// groups は重なりグループの配列（grouping 間隔は groupOverlaps で構築）。
/// backgroundEvents は 24h timed event（背景帯描画用）。
struct DayTimeline {
    let date: Date
    let groups: [OverlapGroup]
    let backgroundEvents: [Event]

    /// 後方互換：既存呼び出しが `tl.events` を読めるようにする。
    /// groups を flatten した start 昇順の Event 配列。24h は含まない。
    var events: [Event] { groups.flatMap { $0.events } }

    /// 後方互換 init。Gateway placeholder（空 events）や既存テストで利用。
    /// 渡された events を単独グループ群として保持（groupOverlaps しない）。
    init(date: Date, events: [Event]) {
        self.date = date
        let sorted = events.sorted { lhs, rhs in
            lhs.start != rhs.start ? lhs.start < rhs.start : lhs.end < rhs.end
        }
        self.groups = sorted.compactMap { OverlapGroup(events: [$0]) }
        self.backgroundEvents = []
    }

    /// 新規 init。make の正式経路。
    init(date: Date, groups: [OverlapGroup], backgroundEvents: [Event]) {
        self.date = date
        self.groups = groups
        self.backgroundEvents = backgroundEvents
    }

    // 既存：currentEvent / nextEvent / clip / make は維持
    // make の中身は Task 5 で更新、本 task では既存 clip + sort + groupOverlaps placeholder
    // filterOverlaps メソッドは完全削除

    static func make(date: Date,
                     rawEvents: [Event],
                     allDayFlags: [Bool],
                     calendar: Calendar) -> DayTimeline {
        // all-day 除外（既存）
        let timedOnly = zip(rawEvents, allDayFlags).compactMap { (ev, isAllDay) -> Event? in
            isAllDay ? nil : ev
        }
        // clip（既存）
        let clipped = timedOnly.compactMap { clip($0, toDayOf: date, calendar: calendar) }
        let sorted = clipped.sorted { lhs, rhs in
            lhs.start != rhs.start ? lhs.start < rhs.start : lhs.end < rhs.end
        }
        // placeholder：各 event を単独 group に（Task 5 で groupOverlaps + 24h 検出に差し替え）
        let groups = sorted.compactMap { OverlapGroup(events: [$0]) }
        return DayTimeline(date: date, groups: groups, backgroundEvents: [])
    }

    /// 既存 clip ロジック（無変更）
    private static func clip(_ event: Event, toDayOf date: Date, calendar: Calendar) -> Event? {
        // 既存実装そのまま
    }

    /// 既存 currentEvent / nextEvent ロジック（無変更、events flat ベース）
    func currentEvent(at instant: Date) -> Event? {
        events.first { $0.start <= instant && instant < $0.end }
    }

    func nextEvent(after instant: Date) -> Event? {
        events.first { $0.start > instant }
    }

    // ❌ filterOverlaps メソッドは完全削除
}
```

**完了条件**:
```bash
grep -c "filterOverlaps" Sources/Toki/Domain/DayTimeline.swift
# → 0
grep -n "let groups: \[OverlapGroup\]" Sources/Toki/Domain/DayTimeline.swift
grep -n "let backgroundEvents: \[Event\]" Sources/Toki/Domain/DayTimeline.swift
grep -n "var events: \[Event\]" Sources/Toki/Domain/DayTimeline.swift  # computed
grep -n "init(date: Date, events: \[Event\])" Sources/Toki/Domain/DayTimeline.swift
grep -n "init(date: Date, groups: \[OverlapGroup\]" Sources/Toki/Domain/DayTimeline.swift
swift build  # 成功
# テスト：T10/T11/T12 が削除されていないので filterOverlaps 参照で破綻するはず → Task 6 で対応
# 一旦テスト失敗を許容（Task 6 で対応）か、本 task で同時に T10/T11/T12 を削除する
```

**実装上の判断**:
- Task 6 を待たずに **本 task で T10/T11/T12 を削除**する方が build green を保てる
- もしくは Task 6 を Task 4 の直後にして、本 task と Task 6 を 1 つにまとめる
- **推奨**：Task 4 と Task 6 を統合し、本 task で同時に削除（コミット 1 つで build green 維持）

→ **タスク統合**：本 task で `Tests/TokiTests/DayTimelineTests.swift` から T10/T11/T12 を削除する作業も含める。

**コミット**:
```bash
git add Sources/Toki/Domain/DayTimeline.swift Tests/TokiTests/DayTimelineTests.swift
git commit -m "feat(domain): DayTimeline を groups + backgroundEvents 構造に改修、filterOverlaps 削除"
```

**依存**: Task 2

---

## Task 5: DayTimeline.make に groupOverlaps + 24h 検出を実装

**Commit**: `feat(domain): DayTimeline.make に groupOverlaps + 24h 検出を実装`

**目的**: Task 4 の placeholder（各 event を単独 group）を本実装に置き換え。24h timed event を `backgroundEvents` に分離、残りを `groupOverlaps` で重なりグループ化。

**実装**:

ファイル: `Sources/Toki/Domain/DayTimeline.swift`（編集）

`make` を以下に置き換え：

```swift
static func make(date: Date,
                 rawEvents: [Event],
                 allDayFlags: [Bool],
                 calendar: Calendar) -> DayTimeline {
    let dayStart = calendar.startOfDay(for: date)
    guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
        return DayTimeline(date: date, groups: [], backgroundEvents: [])
    }

    // 1. all-day 除外（既存）
    let timedOnly = zip(rawEvents, allDayFlags).compactMap { (ev, isAllDay) -> Event? in
        isAllDay ? nil : ev
    }

    // 2. 24h timed 検出（clip 前に exact match で判定、spec 013 §Open Questions §4）
    var backgrounds: [Event] = []
    var foreground: [Event] = []
    for ev in timedOnly {
        if ev.start == dayStart && ev.end == nextDayStart {
            backgrounds.append(ev)
        } else {
            foreground.append(ev)
        }
    }

    // 3. clip + sort
    let clipped = foreground.compactMap { clip($0, toDayOf: date, calendar: calendar) }
    let sorted = clipped.sorted { lhs, rhs in
        lhs.start != rhs.start ? lhs.start < rhs.start : lhs.end < rhs.end
    }

    // 4. groupOverlaps（filterOverlaps 撤廃、spec 013）
    return DayTimeline(date: date, groups: groupOverlaps(sorted), backgroundEvents: backgrounds)
}

/// start 昇順 events を相互重複でグループ化する。
/// 端接触（prev.end == next.start）は別グループ扱い（spec 013 §Open Questions §3）。
static func groupOverlaps(_ events: [Event]) -> [OverlapGroup] {
    guard !events.isEmpty else { return [] }
    var groups: [[Event]] = []
    var currentEnd: Date? = nil
    for ev in events {
        if let lastEnd = currentEnd, ev.start < lastEnd, !groups.isEmpty {
            groups[groups.count - 1].append(ev)
            currentEnd = max(lastEnd, ev.end)
        } else {
            groups.append([ev])
            currentEnd = ev.end
        }
    }
    return groups.compactMap { OverlapGroup(events: $0) }
}
```

**完了条件**:
```bash
grep -n "static func groupOverlaps" Sources/Toki/Domain/DayTimeline.swift
grep -n "ev.start == dayStart && ev.end == nextDayStart" Sources/Toki/Domain/DayTimeline.swift
swift build && swift test  # 既存テスト + T1-T4 全 pass、まだ T14 testMake_combined は失敗するかも
```

**注意**: T14（`testMake_combined`）は b が a と重なる前提で書かれており、新仕様では `b` も保持されるためアサーション失敗する。Task 6 で T14 を T22 として書き直す。本 task では一旦失敗を許容するか、Task 5 と Task 6 を統合する。

→ **推奨**：Task 5 と Task 6 を **統合**して、make 実装 + テスト更新を同一 commit にする。

**コミット**:
```bash
git add Sources/Toki/Domain/DayTimeline.swift Tests/TokiTests/DayTimelineTests.swift
git commit -m "feat(domain): DayTimeline.make に groupOverlaps + 24h 検出を実装"
```

**依存**: Task 4

---

## Task 6: DayTimelineTests を新仕様で更新（T14 書き直し + T15-T21 追加）

**Commit**: `test(domain): DayTimelineTests を新仕様で更新（T14 書き直し + T15-T21 追加）`

**目的**: T14 を新仕様で書き直し（`b` が a と重なるが保持される）、T15-T21 の新規テストを追加。

**実装**:

ファイル: `Tests/TokiTests/DayTimelineTests.swift`（編集）

注：Task 4 で T10/T11/T12 削除済み前提。T14 を以下に書き直し + T15-T21 追加。

```swift
// T22（T14 を新仕様に書き直し）
func testMake_combined() {
    let a = makeEvent(id: "a", hour: 10)
    let b = makeEvent(id: "b", hour: 10)  // a と重なる
    let cross = makeEvent(id: "cross", hour: 23, durationMinutes: 120)  // 日跨ぎ
    let allDay = makeEvent(id: "allDay", hour: 0, durationMinutes: 60 * 24)
    let tl = DayTimeline.make(
        date: makeDate(),
        rawEvents: [a, b, cross, allDay],
        allDayFlags: [false, false, false, true],
        calendar: cal
    )
    // a と b は同じ groups[0] に保持、cross は clip されて別 group、allDay は除外、24h なし
    XCTAssertEqual(tl.groups.count, 2)
    XCTAssertEqual(tl.groups[0].events.map(\.id), ["a", "b"])
    XCTAssertEqual(tl.groups[1].events.first?.id, "cross")
    XCTAssertTrue(tl.backgroundEvents.isEmpty)
}

// T15: groupOverlaps 単独 → 1 グループ
func testGroupOverlaps_single() {
    let a = makeEvent(id: "a", hour: 10)
    let groups = DayTimeline.groupOverlaps([a])
    XCTAssertEqual(groups.count, 1)
    XCTAssertEqual(groups[0].events.map(\.id), ["a"])
}

// T16: 2 件重なり → 1 グループ 2 件
func testGroupOverlaps_overlapping() {
    let a = makeEvent(id: "a", hour: 10)
    let b = makeEvent(id: "b", hour: 10, durationMinutes: 30)
    let groups = DayTimeline.groupOverlaps([a, b])
    XCTAssertEqual(groups.count, 1)
    XCTAssertEqual(groups[0].events.map(\.id), ["a", "b"])
}

// T17: チェーン 3 件
func testGroupOverlaps_chain() {
    let a = makeEvent(id: "a", hour: 10)         // 10:00-11:00
    let b = makeEvent(id: "b", hour: 10, durationMinutes: 90)  // 10:00-11:30
    let c = makeEvent(id: "c", hour: 11)         // 11:00-12:00（b と重なる）
    let groups = DayTimeline.groupOverlaps([a, b, c])
    XCTAssertEqual(groups.count, 1)
    XCTAssertEqual(groups[0].events.map(\.id), ["a", "b", "c"])
}

// T18: 端接触 → 別グループ
func testGroupOverlaps_endToStart() {
    let a = makeEvent(id: "a", hour: 10)  // 10:00-11:00
    let b = makeEvent(id: "b", hour: 11)  // 11:00-12:00
    let groups = DayTimeline.groupOverlaps([a, b])
    XCTAssertEqual(groups.count, 2)
}

// T19: 24h 検出 → backgroundEvents
func test24h_detectedAsBackground() {
    var c = DateComponents(); c.year = 2026; c.month = 5; c.day = 23
    let dayStart = cal.date(from: c)!
    let nextDayStart = cal.date(byAdding: .day, value: 1, to: dayStart)!
    let busy24h = Event(id: "busy", title: "出張", start: dayStart, end: nextDayStart,
                       calendarColor: CGColor(red: 0, green: 1, blue: 0, alpha: 1))!
    let tl = DayTimeline.make(date: dayStart, rawEvents: [busy24h], allDayFlags: [false], calendar: cal)
    XCTAssertEqual(tl.backgroundEvents.count, 1)
    XCTAssertEqual(tl.backgroundEvents[0].id, "busy")
    XCTAssertEqual(tl.groups.count, 0)
}

// T20: all-day + 24h 並存 → all-day 除外、24h は背景
func testAllDayAnd24h_combined() {
    var c = DateComponents(); c.year = 2026; c.month = 5; c.day = 23
    let dayStart = cal.date(from: c)!
    let nextDayStart = cal.date(byAdding: .day, value: 1, to: dayStart)!
    let allDay = Event(id: "ad", title: "ad", start: dayStart, end: nextDayStart,
                      calendarColor: CGColor(red: 1, green: 0, blue: 0, alpha: 1))!
    let busy24h = Event(id: "24h", title: "24h", start: dayStart, end: nextDayStart,
                       calendarColor: CGColor(red: 0, green: 1, blue: 0, alpha: 1))!
    let tl = DayTimeline.make(date: dayStart, rawEvents: [allDay, busy24h],
                              allDayFlags: [true, false], calendar: cal)
    XCTAssertEqual(tl.groups.count, 0)
    XCTAssertEqual(tl.backgroundEvents.count, 1)
    XCTAssertEqual(tl.backgroundEvents[0].id, "24h")
}

// T21: 24h + 通常 event 並存 → 通常は groups、24h は背景
func test24hAndNormal_separated() {
    var c = DateComponents(); c.year = 2026; c.month = 5; c.day = 23
    let dayStart = cal.date(from: c)!
    let nextDayStart = cal.date(byAdding: .day, value: 1, to: dayStart)!
    let busy24h = Event(id: "24h", title: "24h", start: dayStart, end: nextDayStart,
                       calendarColor: CGColor(red: 0, green: 1, blue: 0, alpha: 1))!
    let normal = makeEvent(id: "normal", hour: 10)
    let tl = DayTimeline.make(date: dayStart, rawEvents: [busy24h, normal],
                              allDayFlags: [false, false], calendar: cal)
    XCTAssertEqual(tl.groups.count, 1)
    XCTAssertEqual(tl.groups[0].events.first?.id, "normal")
    XCTAssertEqual(tl.backgroundEvents.count, 1)
    XCTAssertEqual(tl.backgroundEvents[0].id, "24h")
}
```

**完了条件**:
```bash
swift test 2>&1 | grep "Executed 45 tests"
# → 33（既存 36 - 3 削除）+ 12（新規 4 OverlapGroupTests + 8 DayTimelineTests）= 45 ケース全 pass
```

**コミット**:
```bash
git add Tests/TokiTests/DayTimelineTests.swift
git commit -m "test(domain): DayTimelineTests を新仕様で更新（T14 書き直し + T15-T21 追加）"
```

**依存**: Task 5

---

## Task 7: RenderableOverlapGroup を追加

**Commit**: `feat(ui): RenderableOverlapGroup を追加`

**実装**:

ファイル: `Sources/Toki/UI/RenderableEvent.swift`（編集、末尾追記）

```swift
/// 重なりグループ表示単位。current / next（peek 用） / extraCount を保持。
/// spec 013 で導入。ClockFaceCanvas が描画、ClockViewModel.canvasGroups が生成。
struct RenderableOverlapGroup: Identifiable, Equatable {
    let id: String                // = OverlapGroup.id
    let current: RenderableEvent  // 現在表示中
    let next: RenderableEvent?    // peek 用、重なりなし（count == 1）は nil
    let extraCount: Int           // 重なり追加件数 = max(0, count - 1)
}
```

**完了条件**:
```bash
grep -n "struct RenderableOverlapGroup" Sources/Toki/UI/RenderableEvent.swift
swift build && swift test  # 45 ケース pass
```

**コミット**:
```bash
git add Sources/Toki/UI/RenderableEvent.swift
git commit -m "feat(ui): RenderableOverlapGroup を追加"
```

**依存**: なし（並列可）

---

## Task 8: ClockViewModel に overlapIndices / canvasGroups / scroll handler を追加

**Commit**: `feat(composition): ClockViewModel に overlapIndices / canvasGroups / canvasBackgroundEvent / scroll handler を追加`

**実装**:

ファイル: `Sources/Toki/Composition/ClockViewModel.swift`（編集）

詳細はプラン §4 参照。追加項目：

1. `@Published var overlapIndices: [String: Int]`
2. `private var lastHoverPoint / lastHoverGeometry`
3. `private var pendingScrollSteps / scrollDebounceTask`
4. `var canvasGroups: [RenderableOverlapGroup]` computed
5. `var canvasBackgroundEvent: RenderableEvent?` computed
6. `var canvasEvents: [RenderableEvent]`（後方互換 = canvasGroups.map(\.current)）
7. `private func makeRenderable(_:) -> RenderableEvent`（既存 canvasEvents ロジック抽出）
8. `func handleScrollRaw(deltaY: CGFloat)`（200ms debounce）
9. `private func applyScroll(steps: Int)`
10. `private func hitTestGroup(at: geometry:) -> OverlapGroup?`
11. 既存 `handleHover` に `lastHoverPoint / lastHoverGeometry` 保存追加
12. 既存 `handleArcTap` は無変更（canvasEvents 経由）

**完了条件**:
```bash
grep -n "@Published private(set) var overlapIndices" Sources/Toki/Composition/ClockViewModel.swift
grep -n "var canvasGroups: \[RenderableOverlapGroup\]" Sources/Toki/Composition/ClockViewModel.swift
grep -n "var canvasBackgroundEvent: RenderableEvent?" Sources/Toki/Composition/ClockViewModel.swift
grep -n "func handleScrollRaw" Sources/Toki/Composition/ClockViewModel.swift
grep -n "func applyScroll" Sources/Toki/Composition/ClockViewModel.swift
grep -n "func hitTestGroup" Sources/Toki/Composition/ClockViewModel.swift
swift build && swift test  # 45 ケース pass
./scripts/build-app.sh
```

**コミット**:
```bash
git add Sources/Toki/Composition/ClockViewModel.swift
git commit -m "feat(composition): ClockViewModel に overlapIndices / canvasGroups / canvasBackgroundEvent / scroll handler を追加"
```

**依存**: Task 5, 7

---

## Task 9: ScrollCatcher を新規追加

**Commit**: `feat(ui): ScrollCatcher を新規追加`

**実装**:

ファイル: `Sources/Toki/UI/ScrollCatcher.swift`（新規）

プラン §5.1 のコード（MVP は hitTest nil）。

**完了条件**:
```bash
grep -n "struct ScrollCatcher" Sources/Toki/UI/ScrollCatcher.swift
grep -n "scrollWheel(with event:" Sources/Toki/UI/ScrollCatcher.swift
swift build && swift test
```

**コミット**:
```bash
git add Sources/Toki/UI/ScrollCatcher.swift
git commit -m "feat(ui): ScrollCatcher を新規追加"
```

**依存**: なし（並列可）

---

## Task 10: ClockFaceCanvas を groups + backgroundEvent 入力に改修、背景帯 / peek / badge 描画追加

**Commit**: `feat(ui): ClockFaceCanvas を groups + backgroundEvent 入力に改修、背景帯 / peek / badge 描画追加`

**実装**:

ファイル: `Sources/Toki/UI/ClockFaceCanvas.swift`（編集）

詳細はプラン §5.3 + §6.2（planner 出力）参照。変更点：

1. `events: [RenderableEvent]` → `groups: [RenderableOverlapGroup]`
2. 新規 `backgroundEvent: RenderableEvent?`
3. 描画順を変更（背景帯 → 既存 → peek → badge → 既存最前面）
4. 新規 helper：`drawBackgroundBand` / `drawPeeks` / `drawBadges`
5. 既存 `drawEventArcs` は `groups.map(\.current)` を流す形に内部変換

**完了条件**:
```bash
grep -n "let groups: \[RenderableOverlapGroup\]" Sources/Toki/UI/ClockFaceCanvas.swift
grep -n "let backgroundEvent: RenderableEvent?" Sources/Toki/UI/ClockFaceCanvas.swift
grep -n "func drawBackgroundBand" Sources/Toki/UI/ClockFaceCanvas.swift
grep -n "func drawPeeks" Sources/Toki/UI/ClockFaceCanvas.swift
grep -n "func drawBadges" Sources/Toki/UI/ClockFaceCanvas.swift
swift build && swift test
# ClockView 側はまだ events 渡してるので build エラー予想 → Task 11 で対応
```

**注意**: ClockFaceCanvas 改修だけだと ClockView 側 build break するため、Task 10 + Task 11 を統合するか、ClockView 側を仮対応する。

**推奨**：Task 10 と Task 11 を統合（次の `feat(ui): ClockView を canvasGroups / canvasBackgroundEvent に切替 + ScrollCatcher overlay 追加` と同一 commit）

**コミット**: Task 11 に統合

**依存**: Task 7

---

## Task 11: ClockView を canvasGroups / canvasBackgroundEvent に切替 + ScrollCatcher overlay 追加

**Commit**: `feat(ui): ClockView を canvasGroups / canvasBackgroundEvent に切替 + ScrollCatcher overlay 追加`

**実装**:

ファイル 1: `Sources/Toki/UI/ClockView.swift`（編集）

```swift
ClockFaceCanvas(
    nowAngle: viewModel.nowAngle,
    groups: viewModel.canvasGroups,                     // ← events から差し替え
    backgroundEvent: viewModel.canvasBackgroundEvent,   // ← 新規
    themeColor: appearance.resolvedThemeColor,
    ringThickness: appearance.ringThickness.factor,
    handLineWidth: appearance.handThickness.lineWidth,
    textScale: appearance.textScale.factor,
    circleOutlineLineWidth: appearance.circleOutlineThickness.lineWidth,
    circleOutlineColor: appearance.resolvedCircleOutlineColor,
    onTap: { point, geometry in
        viewModel.handleArcTap(at: point, geometry: geometry)
    },
    onHover: { phase, geometry in
        viewModel.handleHover(phase: phase, geometry: geometry)
    }
)
.overlay(
    ScrollCatcher { deltaY in
        viewModel.handleScrollRaw(deltaY: deltaY)
    }
)
```

ファイル 2: Task 10 の ClockFaceCanvas 改修も同 commit に含める。

**完了条件**:
```bash
grep -n "viewModel.canvasGroups" Sources/Toki/UI/ClockView.swift
grep -n "viewModel.canvasBackgroundEvent" Sources/Toki/UI/ClockView.swift
grep -n "ScrollCatcher" Sources/Toki/UI/ClockView.swift
grep -n "viewModel.handleScrollRaw" Sources/Toki/UI/ClockView.swift
swift build && swift test  # 45 ケース pass
./scripts/build-app.sh
```

実機目視チェック（手動）：
- 単独 event：既存通り、badge / peek なし
- 重なり 2 件：badge `+1` 表示、peek 表示
- scroll：上で次 event 切替、下で前
- 24h timed：背景帯描画
- popover / tooltip：現 index event 表示
- OAuth / 設定 / 次未来 event 等：無変更

**コミット**:
```bash
git add Sources/Toki/UI/ClockFaceCanvas.swift Sources/Toki/UI/ClockView.swift
git commit -m "feat(ui): ClockView を canvasGroups / canvasBackgroundEvent に切替 + ScrollCatcher overlay 追加"
```

**依存**: Task 8, 9, 10

---

## 全 task 完了後

### 回帰確認

- [ ] `swift test`：Domain 45 ケース全 pass
- [ ] `./scripts/build-app.sh && open .build/Toki.app`：実機目視で spec 013 §AC walkthrough

### 手動チェックリスト

| # | シナリオ | 期待 |
|---|---|---|
| M1 | 単独 event | 既存通り、badge / peek なし |
| M2 | 2 件重なり | badge `+1`、peek、scroll で cycle |
| M3 | 3 件重なり | badge `+2`、scroll 3 回で wraparound |
| M4 | scroll 下方向 | 逆 cycle |
| M5 | 24h timed のみ | 背景帯薄色、通常 event なし |
| M6 | 24h + 通常並存 | 背景帯下、通常 event 前面 |
| M7 | all-day のみ | 従来通り何も描画されない |
| M8 | hover 外 scroll | no-op |
| M9 | 重なりなし上 scroll | no-op |
| M10 | popover / tooltip | 現 index event 1 件のみ |
| M11 | OAuth / 設定 / リサイズ / 次未来 event | 全て無変更 |
| M12 | trackpad inertia | 200ms 集計、過剰反応なし |

### コードレビュー（任意）

- `code-reviewer` agent で spec 013 全体レビュー
