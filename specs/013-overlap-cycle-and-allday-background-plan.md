# 013 — overlap-cycle-and-allday-background 技術プラン

`specs/013-overlap-cycle-and-allday-background.md` を技術プランに展開したもの。`/tasks` で atomic task に分解する元となる。

## 0. 確定済み設計判断（17 項目すべて [CONFIDENT] + 追加 3 件確定）

spec 013 §Open Questions 17 件すべて [CONFIDENT]、追加で planner レビューで判明した 3 件も確定：

### spec §Open Questions

| # | 論点 | 判断 |
|---|---|---|
| 1 | OverlapGroup ID | `events[0].id` 流用 |
| 2 | DayTimeline.events 既存 API | computed property で flatten + 後方互換 init 維持 |
| 3 | 重なり判定 | 端接触は別グループ（`<` strict） |
| 4 | 24h 検出 | `start == dayStart && end == nextDayStart` exact |
| 5 | all-day と 24h 並存 | 独立処理 |
| 6 | scroll 方向 | 上 = 次（index++） |
| 7 | scroll sensitivity | 1 notch = 1 step、200ms debounce 集計 |
| 8 | hover 外 scroll | no-op |
| 9 | 重なりなしグループ scroll | no-op |
| 10 | peek 角度 | min(arc × 5%, 8pt 相当)、arc の 30% 超なら skip |
| 11 | peek 描画位置 | 弧の終端（時計回り進行方向） |
| 12 | badge `+N` | 弧の外側 6pt、Text 9pt |
| 13 | 背景帯色 | calendarColor × opacity 0.15 |
| 14 | 背景帯クリック | pass-through |
| 15 | 複数 24h | `backgroundEvents.first` のみ MVP |
| 16 | scroll handler 実装 | `NSViewRepresentable` + `scrollWheel(with:)` |
| 17 | scroll handler 配置 | `UI/ScrollCatcher.swift` 新規 |

### planner レビュー由来の追加確定（spec 013 から逸脱する判断）

| # | 論点 | 判断 | 理由 |
|---|---|---|---|
| 18 | `filterOverlaps` の扱い | **完全削除 + T10/11/12 削除** | make 経路で使われなくなり deprecated 化、構造負債回避。groupOverlaps の挙動は T15-T18 で網羅 |
| 19 | `OverlapGroup: Hashable` 実装 | **Event を id ベース Hashable 化、OverlapGroup は Hashable 自動合成** | spec 010 Attendee と同 pattern、Equatable 手動 + Hashable なしは非対称 |
| 20 | `ScrollCatcher.hitTest` 戻り値 | **MVP は nil 試行 → 駄目なら hitTest self + responder chain 明示転送** | SwiftUI overlay 上の NSView での scrollWheel 受信は macOS の動作依存、実機検証 |

## 1. Requirements restatement

実用 pain 2 件を一括解消：(1) 重なり event の earliest-start-wins ロジックを撤廃し、Domain に `OverlapGroup` 概念を導入してグループ単位で event を保持。UI 側で hover + scroll wheel により表示中 event を cycle 切替。視覚 indicator は `+N` badge と次 event 色の peek。(2) `start = 0:00 / end = 翌 0:00` の 24h timed event を `backgroundEvents` に分離し、円弧描画から外して背景帯（calendarColor × opacity 0.15）として全周薄色で描画、クリック pass-through。

Domain は OverlapGroup 新規 + Event Hashable 化 + DayTimeline 構造改修、Composition は overlapIndices + scroll handler、UI は ScrollCatcher + 描画追加（背景帯 / peek / badge）、Tests は filterOverlaps テスト 3 件削除 + 新規 12 件追加。

## 2. ファイル別変更計画

### 新規（3 ファイル）

| パス | 役割 | 想定行数 |
|---|---|---|
| `Sources/Toki/Domain/OverlapGroup.swift` | OverlapGroup 値オブジェクト（init?, id, event(at:), count, isOverlapping, start, end） | ~60 |
| `Sources/Toki/UI/ScrollCatcher.swift` | scrollWheel を SwiftUI に橋渡しする NSViewRepresentable | ~50 |
| `Tests/TokiTests/OverlapGroupTests.swift` | OverlapGroup 単体テスト 4 件 | ~80 |

### 編集（7 ファイル）

| パス | 主な変更 |
|---|---|
| `Sources/Toki/Domain/Event.swift` | Hashable 追加（id ベース手動実装） |
| `Sources/Toki/Domain/DayTimeline.swift` | groups + backgroundEvents 構造、events は computed flatten、init 後方互換、make に groupOverlaps + 24h 検出、**filterOverlaps メソッド削除** |
| `Sources/Toki/UI/RenderableEvent.swift` | 末尾に RenderableOverlapGroup 追加 |
| `Sources/Toki/Composition/ClockViewModel.swift` | overlapIndices / lastHoverPoint+Geometry / canvasGroups / canvasBackgroundEvent / makeRenderable / handleScrollRaw / hitTestGroup 追加、canvasEvents は flatten 後方互換 |
| `Sources/Toki/UI/ClockFaceCanvas.swift` | 入力を groups + backgroundEvent に、背景帯 / peek / badge 描画追加 |
| `Sources/Toki/UI/ClockView.swift` | ClockFaceCanvas を groups 入力に切替、ScrollCatcher overlay 追加 |
| `Tests/TokiTests/DayTimelineTests.swift` | **T10/T11/T12 削除**、T14 を新仕様で書き直し、T15-T22 追加（合計 net +8） |

## 3. Domain 改修

### 3.1 Event Hashable

```swift
extension Event: Hashable {
    // Equatable と整合：id ベース
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
```

### 3.2 OverlapGroup（新規）

```swift
struct OverlapGroup: Identifiable, Equatable, Hashable {
    let events: [Event]   // 1 件以上、start 昇順、相互重複（端接触除く）

    init?(events: [Event]) {
        guard !events.isEmpty else { return nil }
        self.events = events.sorted { l, r in
            l.start != r.start ? l.start < r.start : l.end < r.end
        }
    }

    var id: String { events[0].id }
    var count: Int { events.count }
    var isOverlapping: Bool { events.count > 1 }
    var start: Date { events[0].start }
    var end: Date { events.map(\.end).max() ?? events[0].end }

    /// 循環参照（負数 / count 超過でも modulo で巻き戻る）
    func event(at index: Int) -> Event {
        let c = events.count
        let normalized = ((index % c) + c) % c
        return events[normalized]
    }
}
```

### 3.3 DayTimeline 改修

```swift
struct DayTimeline {
    let date: Date
    let groups: [OverlapGroup]
    let backgroundEvents: [Event]

    /// 後方互換：既存 API
    var events: [Event] { groups.flatMap { $0.events } }

    /// 後方互換 init（Gateway placeholder / 既存テスト用）
    init(date: Date, events: [Event]) {
        self.date = date
        let sorted = events.sorted { l, r in
            l.start != r.start ? l.start < r.start : l.end < r.end
        }
        self.groups = sorted.compactMap { OverlapGroup(events: [$0]) }
        self.backgroundEvents = []
    }

    /// 新規 init（make から）
    init(date: Date, groups: [OverlapGroup], backgroundEvents: [Event]) {
        self.date = date
        self.groups = groups
        self.backgroundEvents = backgroundEvents
    }

    // currentEvent / nextEvent / clip は events flat ベースで挙動維持
    // filterOverlaps は完全削除
}
```

### 3.4 make ロジック

```swift
static func make(date:, rawEvents:, allDayFlags:, calendar:) -> DayTimeline {
    let dayStart = calendar.startOfDay(for: date)
    guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
        return DayTimeline(date: date, groups: [], backgroundEvents: [])
    }

    // 1. all-day 除外
    let timedOnly = zip(rawEvents, allDayFlags).compactMap { (ev, isAllDay) -> Event? in
        isAllDay ? nil : ev
    }

    // 2. 24h 検出（clip 前に exact match で判定）
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
    let sorted = clipped.sorted { l, r in
        l.start != r.start ? l.start < r.start : l.end < r.end
    }

    // 4. groupOverlaps（filterOverlaps 撤廃）
    return DayTimeline(date: date, groups: groupOverlaps(sorted), backgroundEvents: backgrounds)
}

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

## 4. Composition 改修

### 4.1 ClockViewModel 追加プロパティ

```swift
@Published private(set) var overlapIndices: [String: Int] = [:]

private var lastHoverPoint: CGPoint? = nil
private var lastHoverGeometry: ClockGeometry? = nil

private var pendingScrollSteps: Int = 0
private var scrollDebounceTask: Task<Void, Never>? = nil
```

### 4.2 computed properties

```swift
var canvasGroups: [RenderableOverlapGroup] {
    guard let tl = timeline else { return [] }
    return tl.groups.map { group in
        let idx = overlapIndices[group.id] ?? 0
        return RenderableOverlapGroup(
            id: group.id,
            current: makeRenderable(group.event(at: idx)),
            next: group.isOverlapping ? makeRenderable(group.event(at: idx + 1)) : nil,
            extraCount: max(0, group.count - 1)
        )
    }
}

var canvasBackgroundEvent: RenderableEvent? {
    guard let tl = timeline, let ev = tl.backgroundEvents.first else { return nil }
    return makeRenderable(ev)
}

// 後方互換 + popover/tap 経路
var canvasEvents: [RenderableEvent] { canvasGroups.map(\.current) }

private func makeRenderable(_ ev: Event) -> RenderableEvent {
    RenderableEvent(
        id: ev.id, title: ev.title,
        startAngle: TimeOfDay.from(date: ev.start, calendar: calendar).clockAngle,
        endAngle: TimeOfDay.from(date: ev.end, calendar: calendar).clockAngle,
        color: ev.calendarColor, status: ev.status(at: now),
        start: ev.start, end: ev.end,
        webURL: ev.webURL, location: ev.location, note: ev.note,
        attendees: ev.attendees, meetURL: ev.meetURL
    )
}
```

### 4.3 hover / scroll handlers

```swift
func handleHover(phase: HoverPhase, geometry: ClockGeometry) {
    switch phase {
    case .active(let loc):
        lastHoverPoint = loc
        lastHoverGeometry = geometry
        // 既存 tooltip 構築（canvasGroups.map(\.current) 経由）
    case .ended:
        lastHoverPoint = nil
        lastHoverGeometry = nil
        if hoveredTooltip != nil { hoveredTooltip = nil }
    }
}

func handleScrollRaw(deltaY: CGFloat) {
    let step = deltaY > 0 ? 1 : -1
    pendingScrollSteps += step
    scrollDebounceTask?.cancel()
    scrollDebounceTask = Task { @MainActor [weak self] in
        try? await Task.sleep(nanoseconds: 200_000_000)
        guard let self, !Task.isCancelled else { return }
        let pending = self.pendingScrollSteps
        self.pendingScrollSteps = 0
        self.applyScroll(steps: pending)
    }
}

private func applyScroll(steps: Int) {
    guard steps != 0,
          let point = lastHoverPoint,
          let geo = lastHoverGeometry,
          let group = hitTestGroup(at: point, geometry: geo),
          group.isOverlapping else { return }
    let current = overlapIndices[group.id] ?? 0
    let c = group.count
    overlapIndices[group.id] = ((current + steps) % c + c) % c
}

private func hitTestGroup(at point: CGPoint, geometry: ClockGeometry) -> OverlapGroup? {
    guard let tl = timeline else { return nil }
    for (idx, rgroup) in canvasGroups.enumerated() {
        let arc = annulusPath(
            center: geometry.center,
            innerR: geometry.innerRadius, outerR: geometry.outerRadius,
            startAngle: rgroup.current.startAngle, endAngle: rgroup.current.endAngle
        )
        if arc.contains(point) { return tl.groups[idx] }
    }
    return nil
}
```

## 5. UI 改修

### 5.1 ScrollCatcher

```swift
struct ScrollCatcher: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = ScrollHandlingView(); v.onScroll = onScroll; return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ScrollHandlingView)?.onScroll = onScroll
    }
    private final class ScrollHandlingView: NSView {
        var onScroll: ((CGFloat) -> Void)?
        override func scrollWheel(with event: NSEvent) {
            let dy = event.scrollingDeltaY
            guard abs(dy) > 0 else { return }
            onScroll?(dy)
        }
        // MVP：hitTest nil で下層 click / hover 通す。
        // 駄目なら hitTest self + mouseDown/mouseUp 明示 super 転送に切替。
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
```

### 5.2 RenderableOverlapGroup

`RenderableEvent.swift` 末尾に追加：

```swift
struct RenderableOverlapGroup: Identifiable, Equatable {
    let id: String
    let current: RenderableEvent
    let next: RenderableEvent?  // peek 用
    let extraCount: Int
}
```

### 5.3 ClockFaceCanvas 改修

入力：`events: [RenderableEvent]` → `groups: [RenderableOverlapGroup]` + `backgroundEvent: RenderableEvent?`

描画順：
1. 背景帯（24h、calendarColor × 0.15）
2. リング輪郭（既存）
3. 時刻マーク（既存）
4. event 円弧（`groups.map(\.current)` を既存 drawEventArcs に流す）
5. peek（next の色で弧終端を 5% / 最低 8pt 上書き、弧の 30% 超なら skip）
6. badge `+N`（弧外側 6pt、Text 9pt）
7. 中心ドット、針（既存最前面）

### 5.4 ClockView 改修

```swift
ClockFaceCanvas(
    nowAngle: viewModel.nowAngle,
    groups: viewModel.canvasGroups,
    backgroundEvent: viewModel.canvasBackgroundEvent,
    // 既存パラメータ群
    onTap: { ... },
    onHover: { ... }
)
.overlay(
    ScrollCatcher { dy in viewModel.handleScrollRaw(deltaY: dy) }
)
```

## 6. テスト方針

### 6.1 既存テスト変更
- **削除**：T10 `testFilterOverlaps_partialOverlap` / T11 `testFilterOverlaps_fullyNested` / T12 `testFilterOverlaps_noOverlap`（filterOverlaps メソッド撤廃のため）
- **更新**：T14 `testMake_combined`（b は a に重なるが新仕様では同じ group に保持される、cross は clip）

### 6.2 新規テスト

**OverlapGroupTests.swift（4 件）**：
- T1: 単独 event → count=1, isOverlapping=false
- T2: 2 件重なり → count=2, isOverlapping=true
- T3: 循環参照 `event(at: 5) == events[5 % count]`
- T4: 負数循環 `event(at: -1) == events.last`

**DayTimelineTests.swift 追加（8 件）**：
- T15: groupOverlaps 単独 → 1 グループ
- T16: groupOverlaps 2 件重なり → 1 グループ 2 件
- T17: groupOverlaps チェーン 3 件 → 1 グループ 3 件
- T18: groupOverlaps 端接触 → 別グループ
- T19: make で 24h 検出 → backgroundEvents
- T20: all-day と 24h 並存 → all-day 除外、24h は背景
- T21: 24h + 通常並存 → 通常は groups
- T22（T14 置換）: testMake_combined 新仕様

合計：33（既存 -3）+ 12（新規）= **45 ケース**

## 7. 実装フェーズ順序

**11 タスク**：

1. `feat(domain): Event を id ベース Hashable 化`
2. `feat(domain): OverlapGroup 値オブジェクトを新規追加`
3. `test(domain): OverlapGroupTests T1-T4 を追加`
4. `feat(domain): DayTimeline を groups + backgroundEvents 構造に改修、filterOverlaps 削除`
5. `feat(domain): DayTimeline.make に groupOverlaps + 24h 検出を実装`
6. `test(domain): DayTimelineTests T10/T11/T12 削除、T14 を T22 として書き直し、T15-T21 追加`
7. `feat(ui): RenderableOverlapGroup 追加`
8. `feat(composition): ClockViewModel に overlapIndices / canvasGroups / canvasBackgroundEvent / scroll handler 追加`
9. `feat(ui): ScrollCatcher を新規追加`
10. `feat(ui): ClockFaceCanvas を groups + backgroundEvent 入力に改修、背景帯 / peek / badge 描画追加`
11. `feat(ui): ClockView を canvasGroups / canvasBackgroundEvent に切替 + ScrollCatcher overlay 追加`

依存：
- Domain: 1 → 2 → 3 / 4 → 5 → 6
- UI 並列：7, 9
- Composition: 7 → 8（要 RenderableOverlapGroup）
- 統合：10 → 11

## 8. リスク

| # | リスク | 重大度 | 緩和策 |
|---|---|---|---|
| R1 | `DayTimeline.init(date:events:)` 後方互換破り | 高 | init 維持 |
| R2 | ScrollCatcher hitTest nil で scrollWheel 不達 | 高 | MVP 試行 → 駄目なら hitTest self + responder chain 明示転送 |
| R3 | 24h exact equality の Date 揺らぎ | 中 | Google API の startOfDay 整合性を実機検証 |
| R4 | trackpad inertia scroll 過剰反応 | 中 | 200ms debounce |
| R5 | peek 小さい弧で支配的 | 中 | 30% 超で skip |
| R6 | badge と他要素重なり | 中 | outer + 6pt 外側、実機調整 |
| R7 | canvasGroups 毎フレーム計算 | 低 | 件数小、無問題 |
| R8 | overlapIndices 永続化なし | 低 | spec §Non-goals |
| R9 | 中央テキスト cycle 非反映 | 低 | spec §Goal 外 |
| R10 | Hashable 化で既存挙動影響 | 低 | id ベース手動、Equatable と整合 |

## 9. テスト確認

### 自動
- Domain 45 ケース全 pass（33 既存 + 12 新規 -3 削除）

### 手動チェックリスト
- 単独 event：既存通り、badge / peek なし
- 2/3 件重なり：badge、peek、scroll cycle、wraparound
- 24h timed：背景帯薄色、通常 event 前面
- all-day：従来通り非表示
- hover 外 / 重なりなし scroll：no-op
- popover / tooltip：現 index 1 件のみ
- 既存挙動（OAuth / 設定 / リサイズ / 次未来 event 等）：無変更

## 10. Out of scope

spec 013 §Non-goals 再掲：
- popover cycle ナビ（spec 015 候補）
- 2 段リング描画（不採用）
- scroll で透明度操作（別 spec）
- キーボード cycle（spec 015 候補）
- 同時表示（半透明重ね、不採用）
- 中央テキスト cycle 反映（spec 015 候補）
- 複数 24h 同時描画（spec 014 候補）

## 参考ファイル

- `specs/013-overlap-cycle-and-allday-background.md`
- `specs/010-event-preview-plan.md`
- `specs/011-appearance-model-plan.md`
- `specs/012-next-future-event-plan.md`

次のステップ：`/tasks 013-overlap-cycle-and-allday-background` で 11 atomic task ファイル化。
