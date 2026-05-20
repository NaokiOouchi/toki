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
/// Task 8 で `EKEventStoreChanged` 通知購読と `timelineUpdates` Publisher を追加。
final class EventKitGateway {
    private let store = EKEventStore()
    private let calendar: Calendar

    /// 最新値を保持し、新規購読時にも即座に値を渡せるよう CurrentValueSubject を使う。
    /// 外部には `eraseToAnyPublisher()` 経由でのみ公開し、send 権限は内部に閉じる。
    private let subject: CurrentValueSubject<DayTimeline, Never>
    private var cancellables = Set<AnyCancellable>()

    init(calendar: Calendar = .current) {
        self.calendar = calendar
        let initialDate = calendar.startOfDay(for: Date())
        self.subject = CurrentValueSubject(DayTimeline(date: initialDate, events: []))
    }

    /// DayTimeline の最新値を購読できる Publisher。
    /// 新規購読者は CurrentValueSubject により直近の値を即座に受け取る。
    var timelineUpdates: AnyPublisher<DayTimeline, Never> {
        subject.eraseToAnyPublisher()
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

    /// 変更通知の購読を開始する。
    /// 多重購読を防ぐため冒頭で cancellables をリセットする。
    /// 300ms debounce することで連続した変更通知を集約する。
    /// 呼び出し直後に初回 reload を非同期で実行し、最新の DayTimeline を subject に流す。
    func start() {
        cancellables.removeAll()

        NotificationCenter.default
            .publisher(for: .EKEventStoreChanged, object: store)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { await self?.reload() }
            }
            .store(in: &cancellables)

        Task { await reload() }
    }

    /// 変更通知の購読を停止する。
    /// cancellables をクリアすることで sink を破棄する。
    func stop() {
        cancellables.removeAll()
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

    /// 今日の DayTimeline を再取得して subject に流す。
    /// 変更通知購読の sink から呼ばれる他、`start()` 時にも初回 reload として呼ばれる。
    private func reload() async {
        let timeline = await fetchTodayTimeline()
        subject.send(timeline)
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
