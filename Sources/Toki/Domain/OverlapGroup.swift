import Foundation

/// 同じ時間帯に重なる Event のグループを表す Value Object。
/// 1 件以上の event を start 昇順で保持し、相互に時間重複する。
/// 単独 event = events.count == 1 のグループ。
/// 端接触（prev.end == next.start）は別グループ扱い（spec 013 §Open Questions §3）。
struct OverlapGroup: Identifiable, Equatable, Hashable {
    /// 1 件以上、start 昇順で保持。
    let events: [Event]

    /// failable init。空配列は拒否、入力は自動で start 昇順に sort される。
    /// 重なり整合性は呼び出し側（DayTimeline.make の groupOverlaps）の責務で、
    /// init では強制しない（誤呼出時のクラッシュを避けるため）。
    init?(events: [Event]) {
        guard !events.isEmpty else { return nil }
        self.events = events.sorted { lhs, rhs in
            lhs.start != rhs.start ? lhs.start < rhs.start : lhs.end < rhs.end
        }
    }

    /// 安定 ID。events[0].id を流用（spec 013 §Open Questions §1）。
    var id: String { events[0].id }

    /// 重なり件数。
    var count: Int { events.count }

    /// 重なりがあるか（count > 1）。
    var isOverlapping: Bool { events.count > 1 }

    /// グループ全体の最早 start（= events[0].start）。
    var start: Date { events[0].start }

    /// グループ全体の最遅 end。groupOverlaps が「最大 end 以下に next.start」を判定するために使う。
    var end: Date { events.map(\.end).max() ?? events[0].end }

    /// index 番目の event を循環参照で取得。
    /// 負数 / count 超過でも modulo で安全に巻き戻る（scroll の wraparound 用）。
    func event(at index: Int) -> Event {
        let c = events.count
        let normalized = ((index % c) + c) % c
        return events[normalized]
    }
}
