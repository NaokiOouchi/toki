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
    /// EKCalendar.title から伝播するカレンダー名（Google の場合はメールアドレス）。
    /// Google event 詳細 URL の eid 生成に必要。空文字列は許容。
    let calendarTitle: String
    /// Google Calendar API で取得した event detail URL（`htmlLink`）。
    /// 非 Google event / API 取得失敗の場合は nil。
    let webURL: URL?

    init?(id: String, title: String, start: Date, end: Date,
          calendarColor: CGColor, externalIdentifier: String?,
          calendarTitle: String, webURL: URL? = nil) {
        guard !id.isEmpty, start < end else { return nil }
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.calendarColor = calendarColor
        self.externalIdentifier = externalIdentifier
        self.calendarTitle = calendarTitle
        self.webURL = webURL
    }
}

extension Event: Equatable {
    /// CGColor のポインタ比較を避けるため、Equatable は id ベース限定。
    static func == (lhs: Event, rhs: Event) -> Bool {
        lhs.id == rhs.id
    }
}
