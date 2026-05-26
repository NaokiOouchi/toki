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
    /// Event 個別色（spec 029）。Google Calendar の colorId から解決した CGColor。
    /// nil の場合は calendarColor を使う。表示時は `displayColor` で解決済み色を取得する。
    let eventColor: CGColor?
    /// Google Calendar API で取得した event detail URL（`htmlLink`）。
    /// 取得失敗の場合は nil。
    let webURL: URL?
    /// 場所文字列（API の `location`）。spec 010 で追加。
    let location: String?
    /// description（API は `description`、`CustomStringConvertible.description`
    /// と衝突するため Domain では `note` に改名）。spec 010 で追加。
    let note: String?
    /// 参加者リスト。空配列は「参加者なし」、nil は使わない。spec 010 で追加。
    let attendees: [Attendee]
    /// Meet URL（`hangoutLink` 優先、`conferenceData.entryPoints[type=video].uri` fallback）。
    /// spec 010 で追加。
    let meetURL: URL?

    init?(id: String, title: String, start: Date, end: Date,
          calendarColor: CGColor,
          eventColor: CGColor? = nil,
          webURL: URL? = nil,
          location: String? = nil,
          note: String? = nil,
          attendees: [Attendee] = [],
          meetURL: URL? = nil) {
        guard !id.isEmpty, start < end else { return nil }
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.calendarColor = calendarColor
        self.eventColor = eventColor
        self.webURL = webURL
        self.location = location
        self.note = note
        self.attendees = attendees
        self.meetURL = meetURL
    }

    /// 描画用に解決された色（spec 029）。
    /// Event 個別色（colorId 由来）があればそれを優先、なければ calendar 色。
    var displayColor: CGColor {
        eventColor ?? calendarColor
    }
}

extension Event: Equatable {
    /// CGColor のポインタ比較を避けるため、Equatable は id ベース限定。
    static func == (lhs: Event, rhs: Event) -> Bool {
        lhs.id == rhs.id
    }
}

extension Event: Hashable {
    /// Equatable と整合させるため id ベースで実装。
    /// CGColor は自動合成 Hashable 不可だが、id だけで一意性が担保される。
    /// spec 013 で OverlapGroup の Hashable 自動合成を可能にするため追加。
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
