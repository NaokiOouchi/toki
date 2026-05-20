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
/// Task 7 で `EKEvent → Event` 変換と `DayTimeline.make` 呼び出しを実装。
/// 購読（変更通知）は Task 8 で追加する。
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
    /// `EKEvent` を Domain の `Event` に変換し、all-day flag と共に
    /// `DayTimeline.make` に委譲する。all-day 除外 / clip / 重なりフィルタは
    /// Domain 側で処理する（Infrastructure には Domain ロジックを書かない）。
    func fetchTodayTimeline() async -> DayTimeline {
        let dayStart = calendar.startOfDay(for: Date())
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return DayTimeline(date: dayStart, events: [])
        }
        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
        let ekEvents = store.events(matching: predicate)

        var rawEvents: [Event] = []
        var allDayFlags: [Bool] = []
        for ek in ekEvents {
            guard let event = Self.convert(ek) else { continue }
            rawEvents.append(event)
            allDayFlags.append(ek.isAllDay)
        }

        return DayTimeline.make(date: dayStart,
                                rawEvents: rawEvents,
                                allDayFlags: allDayFlags,
                                calendar: calendar)
    }

    /// `EKEvent` を Domain の `Event` に変換する。
    /// recurring イベントは全 occurrence で `eventIdentifier` が共通になるため、
    /// `startDate` を組み合わせて id を一意化する。
    /// 0 分以下や不正な値は `Event` の failable init で自動的に弾かれる。
    private static func convert(_ ek: EKEvent) -> Event? {
        let baseId = ek.eventIdentifier ?? UUID().uuidString
        let id = "\(baseId)#\(ek.startDate.timeIntervalSince1970)"
        return Event(
            id: id,
            title: ek.title ?? "(無題)",
            start: ek.startDate,
            end: ek.endDate,
            calendarColor: ek.calendar.cgColor,
            externalIdentifier: ek.eventIdentifier
        )
    }
}
