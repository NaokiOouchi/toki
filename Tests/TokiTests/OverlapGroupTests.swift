import XCTest
@testable import Toki

/// OverlapGroup の単体テスト。spec 013 で導入。
final class OverlapGroupTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    /// 2026/05/23 hour 時刻に start し、durationMinutes 分続く event を生成。
    private func makeEvent(id: String, hour: Int, minute: Int = 0, durationMinutes: Int = 60) -> Event {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 23
        c.hour = hour; c.minute = minute
        let start = cal.date(from: c)!
        let end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        return Event(
            id: id, title: id, start: start, end: end,
            calendarColor: CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        )!
    }

    // T1: 単独 event の OverlapGroup → count=1, isOverlapping=false
    func testSingle_countAndIsOverlapping() {
        let group = OverlapGroup(events: [makeEvent(id: "a", hour: 10)])!
        XCTAssertEqual(group.count, 1)
        XCTAssertFalse(group.isOverlapping)
        XCTAssertEqual(group.event(at: 0).id, "a")
        XCTAssertEqual(group.id, "a")
    }

    // T2: 2 件重なりグループ → count=2, isOverlapping=true
    func testTwoEvents_countAndAccess() {
        let a = makeEvent(id: "a", hour: 10)
        let b = makeEvent(id: "b", hour: 10, minute: 30, durationMinutes: 30)
        let group = OverlapGroup(events: [a, b])!
        XCTAssertEqual(group.count, 2)
        XCTAssertTrue(group.isOverlapping)
        XCTAssertEqual(group.event(at: 0).id, "a")
        XCTAssertEqual(group.event(at: 1).id, "b")
    }

    // T3: 循環参照（正の index）event(at: 5) == events[5 % count]
    func testCyclicAccess_positive() {
        let a = makeEvent(id: "a", hour: 10)
        let b = makeEvent(id: "b", hour: 10, minute: 30, durationMinutes: 30)
        let group = OverlapGroup(events: [a, b])!
        XCTAssertEqual(group.event(at: 2).id, "a")  // 2 % 2 == 0
        XCTAssertEqual(group.event(at: 5).id, "b")  // 5 % 2 == 1
        XCTAssertEqual(group.event(at: 6).id, "a")  // 6 % 2 == 0
    }

    // T4: 負数循環 event(at: -1) == events.last
    func testCyclicAccess_negative() {
        let a = makeEvent(id: "a", hour: 10)
        let b = makeEvent(id: "b", hour: 10, minute: 30, durationMinutes: 30)
        let group = OverlapGroup(events: [a, b])!
        XCTAssertEqual(group.event(at: -1).id, "b")
        XCTAssertEqual(group.event(at: -2).id, "a")
        XCTAssertEqual(group.event(at: -3).id, "b")
    }
}
