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

    private func makeEvent(id: String, start: Date, end: Date, calendarTitle: String = "", webURL: URL? = nil) -> Event {
        Event(id: id, title: "ev-\(id)", start: start, end: end,
              calendarColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
              externalIdentifier: nil,
              calendarTitle: calendarTitle,
              webURL: webURL)!
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

    // 10 partial overlap
    func testFilterOverlaps_partialOverlap() {
        let a = makeEvent(id: "a", start: date(2026, 5, 20, 9, 0), end: date(2026, 5, 20, 10, 0))
        let b = makeEvent(id: "b", start: date(2026, 5, 20, 9, 30), end: date(2026, 5, 20, 9, 45))
        let out = DayTimeline.filterOverlaps([a, b])
        XCTAssertEqual(out.map(\.id), ["a"])
    }

    // 11 fully nested
    func testFilterOverlaps_fullyNested() {
        let a = makeEvent(id: "a", start: date(2026, 5, 20, 9, 0), end: date(2026, 5, 20, 11, 0))
        let b = makeEvent(id: "b", start: date(2026, 5, 20, 10, 0), end: date(2026, 5, 20, 10, 30))
        let out = DayTimeline.filterOverlaps([a, b])
        XCTAssertEqual(out.map(\.id), ["a"])
    }

    // 12 端接触
    func testFilterOverlaps_noOverlap() {
        let a = makeEvent(id: "a", start: date(2026, 5, 20, 9, 0), end: date(2026, 5, 20, 10, 0))
        let b = makeEvent(id: "b", start: date(2026, 5, 20, 10, 0), end: date(2026, 5, 20, 11, 0))
        let out = DayTimeline.filterOverlaps([a, b])
        XCTAssertEqual(out.map(\.id), ["a", "b"])
    }

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

    // 14 make 全ルール統合
    func testMake_combined() {
        let allDay = makeEvent(id: "ad",
                               start: date(2026, 5, 20, 0, 0),
                               end: date(2026, 5, 21, 0, 0))
        let crossing = makeEvent(id: "cross",
                                 start: date(2026, 5, 20, 23, 30),
                                 end: date(2026, 5, 21, 0, 30))
        let a = makeEvent(id: "a", start: date(2026, 5, 20, 9, 0), end: date(2026, 5, 20, 10, 0))
        let b = makeEvent(id: "b", start: date(2026, 5, 20, 9, 30), end: date(2026, 5, 20, 9, 45))
        let tl = DayTimeline.make(date: today(),
                                  rawEvents: [allDay, crossing, a, b],
                                  allDayFlags: [true, false, false, false],
                                  calendar: calendar)
        // ad 除外、b は a と重なるので除外、a と cross（23:30-24:00 にクリップ）が残る
        XCTAssertEqual(tl.events.map(\.id), ["a", "cross"])
        let crossClipped = tl.events.last!
        XCTAssertEqual(crossClipped.end, date(2026, 5, 21, 0, 0))
    }
}
