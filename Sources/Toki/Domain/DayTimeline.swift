import Foundation

/// 今日 1 日分のイベントを集約する Value Object。
/// spec 013 で従来の `events: [Event]` 単一フィールドを廃止し、
/// `groups: [OverlapGroup]`（重なりグループ群）+ `backgroundEvents: [Event]`（24h timed の背景帯）
/// の二系統に分離した。`events` は後方互換のため computed property として残す（24h を含まない）。
struct DayTimeline {
    let date: Date
    /// 重なりグループ群。`start` 昇順を維持する想定（make 内で構築、Task 5 で本実装）。
    let groups: [OverlapGroup]
    /// 24h timed event（背景帯描画用、Task 5 で検出ロジックを実装）。
    let backgroundEvents: [Event]

    /// 後方互換：既存呼び出しが `tl.events` で flat な Event 列を読めるようにする。
    /// groups を flatten して返す（24h 背景帯は含まない）。
    /// `start` 昇順、同 start は `end` 昇順（groups と OverlapGroup の sort 不変条件に依拠）。
    var events: [Event] { groups.flatMap { $0.events } }

    /// 後方互換 init。Gateway の placeholder（空 events）や既存テストで利用。
    /// 渡された events を sort し、各 event を単独 group として保持する（grouping は行わない）。
    init(date: Date, events: [Event]) {
        self.date = date
        let sorted = events.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.end < rhs.end
        }
        self.groups = sorted.compactMap { OverlapGroup(events: [$0]) }
        self.backgroundEvents = []
    }

    /// 新規 init。`make` の正式経路（Task 5 で利用）。
    /// groups / backgroundEvents は呼び出し側で構築済みである前提。
    init(date: Date, groups: [OverlapGroup], backgroundEvents: [Event]) {
        self.date = date
        self.groups = groups
        self.backgroundEvents = backgroundEvents
    }

    /// 指定時刻 `now` に進行中のイベントを返す。複数該当時は最先のもの。
    /// 後方互換のため `events`（flat）ベースで判定する。
    func currentEvent(at now: Date) -> Event? {
        events.first { $0.status(at: now) == .current }
    }

    /// 指定時刻 `now` 以降に始まる最初のイベントを返す。
    /// 後方互換のため `events`（flat）ベースで判定する。
    func nextEvent(after now: Date) -> Event? {
        events.first { $0.start > now }
    }

    /// イベントを指定日 `[dayStart, dayEnd)` の範囲にクリップする。
    /// 交差なし、または交差区間が 0（端点接触）なら nil を返す。
    static func clip(_ event: Event, toDayOf date: Date, calendar: Calendar) -> Event? {
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        let newStart = max(event.start, dayStart)
        let newEnd = min(event.end, dayEnd)
        // Event の failable init が start < end を保証するため、
        // 交差なし（newStart >= newEnd）の場合は自動的に nil になる。
        return Event(id: event.id,
                     title: event.title,
                     start: newStart,
                     end: newEnd,
                     calendarColor: event.calendarColor,
                     webURL: event.webURL,
                     location: event.location,
                     note: event.note,
                     attendees: event.attendees,
                     meetURL: event.meetURL)
    }

    /// 生イベント列に all-day 除外 → 24h timed 検出 → clip → sort → groupOverlaps を適用するファクトリ。
    /// Infrastructure 層から呼ばれる Domain の入口。
    /// spec 013：24h timed event（start == dayStart && end == nextDayStart）は
    /// backgroundEvents に分離し、残りを groupOverlaps で重なりグループに集約する。
    static func make(date: Date,
                     rawEvents: [Event],
                     allDayFlags: [Bool],
                     calendar: Calendar) -> DayTimeline {
        let dayStart = calendar.startOfDay(for: date)
        guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return DayTimeline(date: date, groups: [], backgroundEvents: [])
        }

        // 1. all-day 除外（既存）
        let timedOnly = zip(rawEvents, allDayFlags).compactMap { (event, isAllDay) -> Event? in
            isAllDay ? nil : event
        }

        // 2. 24h timed event 検出（clip 前に exact match で判定、spec 013 §Open Questions §4）
        var backgrounds: [Event] = []
        var foreground: [Event] = []
        for ev in timedOnly {
            if ev.start == dayStart && ev.end == nextDayStart {
                backgrounds.append(ev)
            } else {
                foreground.append(ev)
            }
        }

        // 3. clip + sort（既存ロジック）
        let clipped = foreground.compactMap { clip($0, toDayOf: date, calendar: calendar) }
        let sorted = clipped.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.end < rhs.end
        }

        // 4. groupOverlaps（filterOverlaps 撤廃、spec 013）
        return DayTimeline(date: date, groups: groupOverlaps(sorted), backgroundEvents: backgrounds)
    }

    /// start 昇順 events を相互重複でグループ化する。
    /// 端接触（prev.end == next.start）は別グループ扱い（spec 013 §Open Questions §3、`<` strict）。
    /// `filterOverlaps`（earliest start wins, 捨てる）の代替。
    /// 入力は事前に start 昇順 sort 済みである前提（make から呼ばれる経路）。
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
}
