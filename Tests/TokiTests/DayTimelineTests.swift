import XCTest
import CoreGraphics
@testable import Toki

final class DayTimelineTests: XCTestCase {
    // ヘルパ：JST 固定でテストの一意性を担保
    private static let jst = TimeZone(identifier: "Asia/Tokyo")!
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = DayTimelineTests.jst
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        comps.hour = h; comps.minute = min
        return calendar.date(from: comps)!
    }

    private func today() -> Date { date(2026, 5, 20, 0, 0) }

    private func makeEvent(id: String, start: Date, end: Date, webURL: URL? = nil,
                           location: String? = nil,
                           note: String? = nil,
                           attendees: [Attendee] = [],
                           meetURL: URL? = nil) -> Event {
        Event(id: id, title: "ev-\(id)", start: start, end: end,
              calendarColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
              webURL: webURL,
              location: location, note: note,
              attendees: attendees, meetURL: meetURL)!
    }

    // 1
    func testEventsSortedByStart() {
        let a = makeEvent(id: "a", start: date(2026, 5, 20, 10, 0), end: date(2026, 5, 20, 11, 0))
        let b = makeEvent(id: "b", start: date(2026, 5, 20, 9, 0), end: date(2026, 5, 20, 9, 30))
        let c = makeEvent(id: "c", start: date(2026, 5, 20, 9, 0), end: date(2026, 5, 20, 9, 15))
        let tl = DayTimeline(date: today(), events: [a, b, c])
        XCTAssertEqual(tl.events.map(\.id), ["c", "b", "a"])  // 9:00 短い順 → 10:00
    }

    // 2
    func testCurrentEvent_returnsMatch() {
        let now = date(2026, 5, 20, 10, 30)
        let past = makeEvent(id: "p", start: date(2026, 5, 20, 9, 0), end: date(2026, 5, 20, 10, 0))
        let cur = makeEvent(id: "c", start: date(2026, 5, 20, 10, 0), end: date(2026, 5, 20, 11, 0))
        let fut = makeEvent(id: "f", start: date(2026, 5, 20, 12, 0), end: date(2026, 5, 20, 13, 0))
        let tl = DayTimeline(date: today(), events: [past, cur, fut])
        XCTAssertEqual(tl.currentEvent(at: now)?.id, "c")
    }

    // 3
    func testCurrentEvent_noneCurrent() {
        let now = date(2026, 5, 20, 11, 30)
        let past = makeEvent(id: "p", start: date(2026, 5, 20, 9, 0), end: date(2026, 5, 20, 10, 0))
        let fut = makeEvent(id: "f", start: date(2026, 5, 20, 12, 0), end: date(2026, 5, 20, 13, 0))
        let tl = DayTimeline(date: today(), events: [past, fut])
        XCTAssertNil(tl.currentEvent(at: now))
    }

    // 4
    func testNextEvent_returnsFirstFuture() {
        let now = date(2026, 5, 20, 11, 30)
        let past = makeEvent(id: "p", start: date(2026, 5, 20, 9, 0), end: date(2026, 5, 20, 10, 0))
        let next = makeEvent(id: "n", start: date(2026, 5, 20, 12, 0), end: date(2026, 5, 20, 13, 0))
        let later = makeEvent(id: "l", start: date(2026, 5, 20, 14, 0), end: date(2026, 5, 20, 15, 0))
        let tl = DayTimeline(date: today(), events: [past, next, later])
        XCTAssertEqual(tl.nextEvent(after: now)?.id, "n")
    }

    // 5
    func testNextEvent_allPast() {
        let now = date(2026, 5, 20, 20, 0)
        let e = makeEvent(id: "p", start: date(2026, 5, 20, 9, 0), end: date(2026, 5, 20, 10, 0))
        let tl = DayTimeline(date: today(), events: [e])
        XCTAssertNil(tl.nextEvent(after: now))
    }

    // 6 clip 日跨ぎ (今日 23:30 → 翌 0:30)
    func testClip_midnightCrossing_endsNextDay() {
        let e = makeEvent(id: "x",
                          start: date(2026, 5, 20, 23, 30),
                          end: date(2026, 5, 21, 0, 30))
        let clipped = DayTimeline.clip(e, toDayOf: today(), calendar: calendar)
        XCTAssertNotNil(clipped)
        XCTAssertEqual(clipped?.start, date(2026, 5, 20, 23, 30))
        XCTAssertEqual(clipped?.end, date(2026, 5, 21, 0, 0))  // 今日の終わり = 翌 0:00
        XCTAssertEqual(clipped?.id, "x")
    }

    // 7 clip 前日跨ぎ
    func testClip_midnightCrossing_startsPrevDay() {
        let e = makeEvent(id: "y",
                          start: date(2026, 5, 19, 23, 30),
                          end: date(2026, 5, 20, 0, 30))
        let clipped = DayTimeline.clip(e, toDayOf: today(), calendar: calendar)
        XCTAssertNotNil(clipped)
        XCTAssertEqual(clipped?.start, date(2026, 5, 20, 0, 0))
        XCTAssertEqual(clipped?.end, date(2026, 5, 20, 0, 30))
    }

    // 8 fully next day
    func testClip_fullyNextDay() {
        let e = makeEvent(id: "n",
                          start: date(2026, 5, 21, 9, 0),
                          end: date(2026, 5, 21, 10, 0))
        XCTAssertNil(DayTimeline.clip(e, toDayOf: today(), calendar: calendar))
    }

    // 9 fully prev day
    func testClip_fullyPrevDay() {
        let e = makeEvent(id: "p",
                          start: date(2026, 5, 19, 9, 0),
                          end: date(2026, 5, 19, 10, 0))
        XCTAssertNil(DayTimeline.clip(e, toDayOf: today(), calendar: calendar))
    }

    // T10/T11/T12（旧重なりフィルタ系）は spec 013 Task 4 で当該メソッド削除に伴い除去。
    // 重なり処理は OverlapGroup + groupOverlaps（Task 5）に責務移譲される。

    // 13 make all-day 除外
    func testMake_excludesAllDay() {
        let a = makeEvent(id: "a", start: date(2026, 5, 20, 9, 0), end: date(2026, 5, 20, 10, 0))
        let ad = makeEvent(id: "ad",
                           start: date(2026, 5, 20, 0, 0),
                           end: date(2026, 5, 21, 0, 0))
        let tl = DayTimeline.make(date: today(),
                                  rawEvents: [a, ad],
                                  allDayFlags: [false, true],
                                  calendar: calendar)
        XCTAssertEqual(tl.events.map(\.id), ["a"])
    }

    // MARK: - spec 013: 新仕様テスト（T15-T22）

    /// 当日（2026-05-20）の指定時刻に hour:minute から duration 分の event を作る helper。
    private func eventAtHour(id: String, hour: Int, minute: Int = 0,
                             durationMinutes: Int = 60) -> Event {
        let start = date(2026, 5, 20, hour, minute)
        let end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        return Event(
            id: id, title: id, start: start, end: end,
            calendarColor: CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        )!
    }

    private var dayStart: Date { date(2026, 5, 20, 0, 0) }
    private var nextDayStart: Date { date(2026, 5, 21, 0, 0) }

    // T15: groupOverlaps 単独 → 1 グループ
    func testGroupOverlaps_single() {
        let a = eventAtHour(id: "a", hour: 10)
        let groups = DayTimeline.groupOverlaps([a])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].events.map(\.id), ["a"])
    }

    // T16: 2 件重なり → 1 グループ 2 件
    func testGroupOverlaps_overlapping() {
        let a = eventAtHour(id: "a", hour: 10)
        let b = eventAtHour(id: "b", hour: 10, minute: 30, durationMinutes: 30)
        let groups = DayTimeline.groupOverlaps([a, b])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].events.map(\.id), ["a", "b"])
    }

    // T17: チェーン 3 件（a:10-11, b:10-11:30, c:11-12 → a∩b, b∩c で全部同じグループ）
    func testGroupOverlaps_chain() {
        let a = eventAtHour(id: "a", hour: 10)
        let b = eventAtHour(id: "b", hour: 10, durationMinutes: 90)
        let c = eventAtHour(id: "c", hour: 11)
        let groups = DayTimeline.groupOverlaps([a, b, c])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].events.map(\.id), ["a", "b", "c"])
    }

    // T18: 端接触 → 別グループ（a:10-11, b:11-12）
    func testGroupOverlaps_endToStart() {
        let a = eventAtHour(id: "a", hour: 10)
        let b = eventAtHour(id: "b", hour: 11)
        let groups = DayTimeline.groupOverlaps([a, b])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].events.map(\.id), ["a"])
        XCTAssertEqual(groups[1].events.map(\.id), ["b"])
    }

    // T19: 24h timed event → backgroundEvents
    func test24h_detectedAsBackground() {
        let busy24h = Event(id: "busy", title: "出張", start: dayStart, end: nextDayStart,
                            calendarColor: CGColor(red: 0, green: 1, blue: 0, alpha: 1))!
        let tl = DayTimeline.make(date: today(), rawEvents: [busy24h],
                                  allDayFlags: [false], calendar: calendar)
        XCTAssertEqual(tl.backgroundEvents.count, 1)
        XCTAssertEqual(tl.backgroundEvents[0].id, "busy")
        XCTAssertEqual(tl.groups.count, 0)
    }

    // T20: all-day と 24h timed 並存 → all-day 除外、24h は背景
    func testAllDayAnd24h_combined() {
        let allDay = Event(id: "ad", title: "ad", start: dayStart, end: nextDayStart,
                           calendarColor: CGColor(red: 1, green: 0, blue: 0, alpha: 1))!
        let busy24h = Event(id: "24h", title: "24h", start: dayStart, end: nextDayStart,
                            calendarColor: CGColor(red: 0, green: 1, blue: 0, alpha: 1))!
        let tl = DayTimeline.make(date: today(), rawEvents: [allDay, busy24h],
                                  allDayFlags: [true, false], calendar: calendar)
        XCTAssertEqual(tl.groups.count, 0)
        XCTAssertEqual(tl.backgroundEvents.count, 1)
        XCTAssertEqual(tl.backgroundEvents[0].id, "24h")
    }

    // T21: 24h + 通常 event 並存 → 通常は groups、24h は背景
    func test24hAndNormal_separated() {
        let busy24h = Event(id: "24h", title: "24h", start: dayStart, end: nextDayStart,
                            calendarColor: CGColor(red: 0, green: 1, blue: 0, alpha: 1))!
        let normal = eventAtHour(id: "normal", hour: 10)
        let tl = DayTimeline.make(date: today(), rawEvents: [busy24h, normal],
                                  allDayFlags: [false, false], calendar: calendar)
        XCTAssertEqual(tl.groups.count, 1)
        XCTAssertEqual(tl.groups[0].events.map(\.id), ["normal"])
        XCTAssertEqual(tl.backgroundEvents.count, 1)
        XCTAssertEqual(tl.backgroundEvents[0].id, "24h")
    }

    // T22（旧 T14 を新仕様で書き直し）: a と b が重なる + cross が日跨ぎ + all-day 除外
    func testMake_combined() {
        let a = eventAtHour(id: "a", hour: 10)            // 10:00-11:00
        let b = eventAtHour(id: "b", hour: 10, minute: 30, durationMinutes: 30)  // 10:30-11:00 (a と重なる)
        // 日跨ぎ event：前日 23:00 から 当日 01:00（clip で 00:00-01:00 に切り詰められる）
        let crossStart = date(2026, 5, 19, 23, 0)
        let crossEnd = crossStart.addingTimeInterval(2 * 60 * 60)  // 当日 01:00
        let cross = Event(id: "cross", title: "cross", start: crossStart, end: crossEnd,
                          calendarColor: CGColor(red: 0, green: 0, blue: 1, alpha: 1))!
        let allDay = eventAtHour(id: "allDay", hour: 0, durationMinutes: 60)

        let tl = DayTimeline.make(
            date: today(),
            rawEvents: [a, b, cross, allDay],
            allDayFlags: [false, false, false, true],
            calendar: calendar
        )

        // 期待：cross は 0:00-1:00 に clip、a/b は同 group、allDay 除外
        // groups[0] = [cross] (00:00-01:00)
        // groups[1] = [a, b] (10:00-11:00)
        XCTAssertEqual(tl.groups.count, 2)
        XCTAssertEqual(tl.groups[0].events.map(\.id), ["cross"])
        XCTAssertEqual(tl.groups[1].events.map(\.id), ["a", "b"])
        XCTAssertTrue(tl.backgroundEvents.isEmpty)
    }
}
