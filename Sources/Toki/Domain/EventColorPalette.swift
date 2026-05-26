import Foundation
import CoreGraphics

/// Google Calendar の event 個別色（API の `colorId` 1-11）と RGB の対応表。
/// spec 029 で導入。Google 公式の color palette は固定で `colors.get` API を
/// 呼ばずにハードコードで対応する（実装簡素化、ネットワーク往復削減）。
///
/// 参考: https://developers.google.com/calendar/api/v3/reference/colors/get
enum EventColorPalette {
    /// Google Event Color Palette (colorId → hex)。
    private static let palette: [String: String] = [
        "1":  "#7986CB",  // Lavender
        "2":  "#33B679",  // Sage
        "3":  "#8E24AA",  // Grape
        "4":  "#E67C73",  // Flamingo
        "5":  "#F6BF26",  // Banana
        "6":  "#F4511E",  // Tangerine
        "7":  "#039BE5",  // Peacock
        "8":  "#616161",  // Graphite
        "9":  "#3F51B5",  // Blueberry
        "10": "#0B8043",  // Basil
        "11": "#D50000"   // Tomato
    ]

    /// colorId（"1"〜"11"）に対応する CGColor を返す。
    /// 範囲外 / 不正な値は nil（呼び出し元で calendar color にフォールバック）。
    static func cgColor(forColorId id: String) -> CGColor? {
        guard let hex = palette[id] else { return nil }
        return cgColor(fromHex: hex)
    }

    /// `#RRGGBB` 形式の hex を CGColor に変換する。
    /// 失敗時は nil（palette は固定なので実際には起きない）。
    private static func cgColor(fromHex hex: String) -> CGColor? {
        var trimmed = hex
        if trimmed.hasPrefix("#") {
            trimmed.removeFirst()
        }
        guard trimmed.count == 6,
              let value = UInt32(trimmed, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        return CGColor(red: r, green: g, blue: b, alpha: 1.0)
    }
}
