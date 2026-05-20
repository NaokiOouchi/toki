import Foundation
import EventKit
import Combine

/// EventKit アクセス権限要求の結果。
/// granted / denied は明確に区別し、システム例外は error に包む。
enum AccessResult {
    case granted
    case denied
    case error(Error)
}

/// EventKit と Domain 層を繋ぐ Gateway。
/// `EKEvent` などの Infrastructure 型は本クラス内で完結させ、
/// 外部には Domain の値型（`DayTimeline` / `Event`）のみを返す。
///
/// 本 task（Task 6）では権限要求と今日のイベント取得の骨格まで実装し、
/// 実体の `EKEvent → Event` 変換は Task 7、購読は Task 8 で追加する。
final class EventKitGateway {
    private let store = EKEventStore()
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// EventKit のフルアクセス権限を要求する。
    /// macOS 14+ 専用 API（`requestFullAccessToEvents`）を使用。
    /// 旧 `requestAccess(to:)` は deprecated のため使わない。
    func requestAccess() async -> AccessResult {
        do {
            let granted = try await store.requestFullAccessToEvents()
            return granted ? .granted : .denied
        } catch {
            return .error(error)
        }
    }

    /// 今日のイベントを取得し `DayTimeline` を返す。
    /// 本 task では変換を実装せず空の `DayTimeline` を返す。
    /// Task 7 で `EKEvent → Event` 変換と `DayTimeline.make` 呼び出しに置き換える。
    func fetchTodayTimeline() async -> DayTimeline {
        let dayStart = calendar.startOfDay(for: Date())
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return DayTimeline(date: dayStart, events: [])
        }
        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
        let _ = store.events(matching: predicate)  // Task 7 で変換予定
        return DayTimeline(date: dayStart, events: [])
    }
}
