import XCTest
import CoreGraphics
@testable import Toki

final class EventStatusTests: XCTestCase {
    private func makeEvent(start: Date, end: Date, webURL: URL? = nil,
                           location: String? = nil,
                           note: String? = nil,
                           attendees: [Attendee] = [],
                           meetURL: URL? = nil) -> Event {
        Event(id: "e1", title: "test", start: start, end: end,
              calendarColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
              webURL: webURL,
              location: location, note: note,
              attendees: attendees, meetURL: meetURL)!
    }

    func testPast() {
        let now = Date()
        let e = makeEvent(start: now.addingTimeInterval(-3600),
                          end: now.addingTimeInterval(-1))
        XCTAssertEqual(e.status(at: now), .past)
    }

    func testFuture() {
        let now = Date()
        let e = makeEvent(start: now.addingTimeInterval(1),
                          end: now.addingTimeInterval(3600))
        XCTAssertEqual(e.status(at: now), .future)
    }

    func testCurrent_inside() {
        let now = Date()
        let e = makeEvent(start: now.addingTimeInterval(-1800),
                          end: now.addingTimeInterval(1800))
        XCTAssertEqual(e.status(at: now), .current)
    }

    func testBoundary_endEqualsNow() {
        let now = Date()
        let e = makeEvent(start: now.addingTimeInterval(-3600), end: now)
        XCTAssertEqual(e.status(at: now), .past)
    }

    func testBoundary_startEqualsNow() {
        let now = Date()
        let e = makeEvent(start: now, end: now.addingTimeInterval(3600))
        XCTAssertEqual(e.status(at: now), .current)
    }
}
