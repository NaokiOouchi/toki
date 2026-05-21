import Foundation

/// 今日 1 日分のイベントを集約する Value Object。
/// 日跨ぎ clip / all-day 除外 / 重なりフィルタ（earliest start wins）を
/// すべて Domain 層で完結させ、UI/Infrastructure に責務を漏らさない。
struct DayTimeline {
    let date: Date
    /// `start` 昇順、同 start は `end` 昇順に保持。
    let events: [Event]

    /// 渡された events を sort して保持。
    init(date: Date, events: [Event]) {
        self.date = date
        self.events = events.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.end < rhs.end
        }
    }

    /// 指定時刻 `now` に進行中のイベントを返す。複数該当時は最先のもの。
    func currentEvent(at now: Date) -> Event? {
        events.first { $0.status(at: now) == .current }
    }

    /// 指定時刻 `now` 以降に始まる最初のイベントを返す。
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
                     externalIdentifier: event.externalIdentifier,
                     calendarTitle: event.calendarTitle)
    }

    /// 重なりフィルタ：start 昇順前提で earliest start wins ルールを適用。
    /// 直前採用イベントの end より start が小さいものはスキップ。
    /// 端接触（前者 end == 後者 start）は重なりとみなさず両方残す。
    static func filterOverlaps(_ events: [Event]) -> [Event] {
        var result: [Event] = []
        var lastEnd: Date? = nil
        for event in events {
            if let le = lastEnd, event.start < le { continue }
            result.append(event)
            lastEnd = event.end
        }
        return result
    }

    /// 生イベント列に all-day 除外 → clip → sort → 重なりフィルタを一括適用する
    /// ファクトリ。Infrastructure 層から呼ばれる Domain の入口。
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
        let filtered = filterOverlaps(sorted)
        return DayTimeline(date: date, events: filtered)
    }
}
