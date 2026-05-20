import Foundation
import CoreGraphics

/// カレンダーイベントを表す Value Object。
/// `start < end` と `id` 非空を failable init で強制する。
struct Event: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let calendarColor: CGColor
    let externalIdentifier: String?

    init?(id: String, title: String, start: Date, end: Date,
          calendarColor: CGColor, externalIdentifier: String?) {
        guard !id.isEmpty, start < end else { return nil }
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.calendarColor = calendarColor
        self.externalIdentifier = externalIdentifier
    }
}

extension Event: Equatable {
    /// CGColor のポインタ比較を避けるため、Equatable は id ベース限定。
    static func == (lhs: Event, rhs: Event) -> Bool {
        lhs.id == rhs.id
    }
}
