import XCTest
import CoreGraphics
@testable import Toki

final class EventTests: XCTestCase {
    private func makeColor() -> CGColor {
        CGColor(red: 1, green: 0, blue: 0, alpha: 1)
    }

    private func makeEvent(id: String = "id-1",
                           title: String = "テスト予定",
                           start: Date = Date(timeIntervalSince1970: 1_700_000_000),
                           end: Date = Date(timeIntervalSince1970: 1_700_003_600),
                           calendarTitle: String = "",
                           webURL: URL? = nil)
        -> Event? {
        Event(id: id, title: title, start: start, end: end,
              calendarColor: makeColor(), externalIdentifier: "ext-1",
              calendarTitle: calendarTitle,
              webURL: webURL)
    }

    // 1. zero duration
    func testInit_zeroDuration() {
        let now = Date()
        XCTAssertNil(makeEvent(start: now, end: now))
    }

    // 2. start > end
    func testInit_startAfterEnd() {
        let start = Date(timeIntervalSince1970: 1_700_003_600)
        let end = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertNil(makeEvent(start: start, end: end))
    }

    // 3. empty id
    func testInit_emptyId() {
        XCTAssertNil(makeEvent(id: ""))
    }

    // 4. normal
    func testInit_normal() {
        let e = makeEvent()
        XCTAssertNotNil(e)
        XCTAssertEqual(e?.id, "id-1")
        XCTAssertEqual(e?.title, "テスト予定")
        XCTAssertEqual(e?.externalIdentifier, "ext-1")
    }

    // 5. Equatable by id (同 id 異タイトル)
    func testEquatable_byId() {
        let a = makeEvent(id: "same", title: "タイトル A")!
        let b = makeEvent(id: "same", title: "タイトル B")!
        XCTAssertEqual(a, b)
    }

    // 6. Equatable different id
    func testEquatable_differentId() {
        let a = makeEvent(id: "x", title: "同じ")!
        let b = makeEvent(id: "y", title: "同じ")!
        XCTAssertNotEqual(a, b)
    }
}
