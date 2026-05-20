import XCTest
@testable import Toki

final class TimeOfDayTests: XCTestCase {
    // 1. clockAngle: 0:00 は真上 (-π/2)
    func testClockAngleAtMidnight() {
        let t = TimeOfDay(hour: 0, minute: 0)!
        XCTAssertEqual(t.clockAngle, -.pi / 2, accuracy: 0.0001)
    }

    // 2. clockAngle: 6:00 は真右 (0)
    func testClockAngleAt6am() {
        let t = TimeOfDay(hour: 6, minute: 0)!
        XCTAssertEqual(t.clockAngle, 0, accuracy: 0.0001)
    }

    // 3. clockAngle: 12:00 は真下 (π/2)
    func testClockAngleAtNoon() {
        let t = TimeOfDay(hour: 12, minute: 0)!
        XCTAssertEqual(t.clockAngle, .pi / 2, accuracy: 0.0001)
    }

    // 4. clockAngle: 18:00 は真左 (π)
    func testClockAngleAt6pm() {
        let t = TimeOfDay(hour: 18, minute: 0)!
        XCTAssertEqual(t.clockAngle, .pi, accuracy: 0.0001)
    }

    // 5. 6:30 は 6:00 と 7:00 の中間
    func testClockAngleAt6_30am() {
        let a = TimeOfDay(hour: 6, minute: 0)!.clockAngle
        let b = TimeOfDay(hour: 7, minute: 0)!.clockAngle
        let mid = TimeOfDay(hour: 6, minute: 30)!.clockAngle
        XCTAssertEqual(mid, (a + b) / 2, accuracy: 0.0001)
    }

    // 6. failable init: hour=24 は nil
    func testFailableInit_hour24() {
        XCTAssertNil(TimeOfDay(hour: 24, minute: 0))
    }

    // 7. failable init: minute=60 は nil
    func testFailableInit_minute60() {
        XCTAssertNil(TimeOfDay(hour: 0, minute: 60))
    }

    // 8. failable init: 負値は nil
    func testFailableInit_negative() {
        XCTAssertNil(TimeOfDay(hour: -1, minute: 0))
        XCTAssertNil(TimeOfDay(hour: 0, minute: -1))
    }

    // 9. Comparable: minutesSinceMidnight 基準で比較
    func testComparable() {
        XCTAssertLessThan(TimeOfDay(hour: 9, minute: 30)!, TimeOfDay(hour: 10, minute: 0)!)
        XCTAssertLessThan(TimeOfDay(hour: 9, minute: 30)!, TimeOfDay(hour: 9, minute: 31)!)
    }

    // 10. minutesSinceMidnight
    func testMinutesSinceMidnight() {
        XCTAssertEqual(TimeOfDay(hour: 9, minute: 30)!.minutesSinceMidnight, 570)
        XCTAssertEqual(TimeOfDay(hour: 0, minute: 0)!.minutesSinceMidnight, 0)
        XCTAssertEqual(TimeOfDay(hour: 23, minute: 59)!.minutesSinceMidnight, 23 * 60 + 59)
    }

    // 11. from(date:): Calendar 経由で hour/minute を抽出
    func testFromDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 1
        components.hour = 9
        components.minute = 30
        let date = calendar.date(from: components)!
        let tod = TimeOfDay.from(date: date, calendar: calendar)
        XCTAssertEqual(tod.hour, 9)
        XCTAssertEqual(tod.minute, 30)
    }
}
