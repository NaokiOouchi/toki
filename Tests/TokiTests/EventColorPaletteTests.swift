import XCTest
@testable import Toki

/// Google Event Color Palette (colorId 1-11) → CGColor 変換テスト。
/// spec 029 で導入。
final class EventColorPaletteTests: XCTestCase {

    /// 全 11 個の colorId が valid な CGColor を返すこと。
    func testAllColorIdsResolve() {
        for id in 1...11 {
            let color = EventColorPalette.cgColor(forColorId: "\(id)")
            XCTAssertNotNil(color, "colorId \(id) should resolve to a CGColor")
        }
    }

    /// 範囲外の colorId は nil。
    func testInvalidColorIds() {
        XCTAssertNil(EventColorPalette.cgColor(forColorId: "0"))
        XCTAssertNil(EventColorPalette.cgColor(forColorId: "12"))
        XCTAssertNil(EventColorPalette.cgColor(forColorId: "99"))
        XCTAssertNil(EventColorPalette.cgColor(forColorId: ""))
        XCTAssertNil(EventColorPalette.cgColor(forColorId: "abc"))
    }

    /// 既知の colorId の RGB が期待値と一致すること（Tomato = #D50000）。
    func testKnownColorTomato() {
        guard let color = EventColorPalette.cgColor(forColorId: "11") else {
            XCTFail("colorId 11 (Tomato) should resolve")
            return
        }
        let components = color.components ?? []
        XCTAssertEqual(components.count, 4)
        XCTAssertEqual(components[0], 0xD5 / 255.0, accuracy: 0.001) // R
        XCTAssertEqual(components[1], 0x00 / 255.0, accuracy: 0.001) // G
        XCTAssertEqual(components[2], 0x00 / 255.0, accuracy: 0.001) // B
        XCTAssertEqual(components[3], 1.0, accuracy: 0.001)          // A
    }

    /// Lavender (#7986CB)。
    func testKnownColorLavender() {
        guard let color = EventColorPalette.cgColor(forColorId: "1") else {
            XCTFail("colorId 1 (Lavender) should resolve")
            return
        }
        let components = color.components ?? []
        XCTAssertEqual(components[0], 0x79 / 255.0, accuracy: 0.001)
        XCTAssertEqual(components[1], 0x86 / 255.0, accuracy: 0.001)
        XCTAssertEqual(components[2], 0xCB / 255.0, accuracy: 0.001)
    }
}
