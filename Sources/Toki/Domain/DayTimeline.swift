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

    /// 生イベント列に all-day 除外 → clip → sort を適用するファクトリ。
    /// Infrastructure 層から呼ばれる Domain の入口。
    /// 本 task（Task 4）では placeholder として「各 event を単独 group」として保持する。
    /// Task 5 で groupOverlaps（重なり grouping）+ 24h timed 検出（backgroundEvents 振り分け）を実装する。
    static func make(date: Date,
                     rawEvents: [Event],
                     allDayFlags: [Bool],
                     calendar: Calendar) -> DayTimeline {
        let timedOnly = zip(rawEvents, allDayFlags).compactMap { (event, isAllDay) -> Event? in
            isAllDay ? nil : event
        }
        let clipped = timedOnly.compactMap { clip($0, toDayOf: date, calendar: calendar) }
        let sorted = clipped.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.end < rhs.end
        }
        // placeholder：各 event を単独 group として保持（Task 5 で grouping + 24h 検出に差し替え）
        let groups = sorted.compactMap { OverlapGroup(events: [$0]) }
        return DayTimeline(date: date, groups: groups, backgroundEvents: [])
    }
}
