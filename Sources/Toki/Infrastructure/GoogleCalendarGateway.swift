import Foundation
import Combine

/// Google Calendar API 経由で今日の event を取得して Domain `DayTimeline` を公開する Gateway。
/// EventKit を使わず、`events.list` で event 一覧を直接取得する。
/// 5 分間隔の自動 reload + 接続/切断時の手動 reload に対応。
/// API 失敗時は last-known timeline を維持（clock 表示を止めない）。
@MainActor
final class GoogleCalendarGateway: ObservableObject {
    private let oauthClient: GoogleOAuthClient
    private let api: GoogleCalendarAPI
    private let calendar: Calendar
    private let subject: CurrentValueSubject<DayTimeline, Never>
    private var reloadTimerCancellable: AnyCancellable?

    /// OAuth 接続状態。reload() 完了時に oauthClient.isAuthorized で再評価し、
    /// ViewModel は Combine で sink して accessGranted を同期する。
    @Published private(set) var isAuthorized: Bool = false

    init(oauthClient: GoogleOAuthClient,
         api: GoogleCalendarAPI,
         calendar: Calendar = .current) {
        self.oauthClient = oauthClient
        self.api = api
        self.calendar = calendar
        let initialDate = calendar.startOfDay(for: Date())
        self.subject = CurrentValueSubject(DayTimeline(date: initialDate, events: []))
        self.isAuthorized = oauthClient.isAuthorized
    }

    /// DayTimeline の最新値を購読できる Publisher。
    var timelineUpdates: AnyPublisher<DayTimeline, Never> {
        subject.eraseToAnyPublisher()
    }

    /// 初回 reload と 5 分間隔の自動 reload タイマーを開始する。
    /// 多重起動を防ぐため冒頭で既存タイマーを cancel する。
    func start() {
        reloadTimerCancellable?.cancel()
        isAuthorized = oauthClient.isAuthorized
        Task { await reload() }
        reloadTimerCancellable = Timer.publish(every: 300, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.reload() }
            }
    }

    /// 自動 reload タイマーを停止する。
    func stop() {
        reloadTimerCancellable?.cancel()
    }

    /// event を再取得して subject に流す。
    /// 接続/切断時に AppDelegate から呼び出す。
    func reload() async {
        let timeline = await fetchTodayTimeline()
        // refresh 失敗で Keychain がクリアされていれば isAuthorized=false に転落
        isAuthorized = oauthClient.isAuthorized
        subject.send(timeline)
    }

    /// 今日の DayTimeline を Google Calendar API 経由で取得する。
    /// OAuth 未接続時は空 DayTimeline、API 失敗時は last-known timeline を維持する。
    private func fetchTodayTimeline() async -> DayTimeline {
        let dayStart = calendar.startOfDay(for: Date())
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return DayTimeline(date: dayStart, events: [])
        }
        guard oauthClient.isAuthorized else {
            return DayTimeline(date: dayStart, events: [])
        }
        do {
            let apiEvents = try await api.fetchTodayEvents(timeMin: dayStart, timeMax: dayEnd)
            var rawEvents: [Event] = []
            var allDayFlags: [Bool] = []
            for ge in apiEvents {
                guard let (event, isAllDay) = Self.convert(ge) else { continue }
                rawEvents.append(event)
                allDayFlags.append(isAllDay)
            }
            return DayTimeline.make(date: dayStart,
                                    rawEvents: rawEvents,
                                    allDayFlags: allDayFlags,
                                    calendar: calendar)
        } catch {
            print("Google Calendar API fetch failed: \(error)")
            return subject.value
        }
    }

    /// API event → Domain Event 変換し、(Event, isAllDay) を返す。
    /// dateTime が nil（all-day）の event は isAllDay=true。
    /// Event の failable init が start<end / id 非空を検証する。
    private static func convert(_ ge: GoogleAPIEvent) -> (Event, Bool)? {
        let isAllDay = ge.start.dateTime == nil
        guard let start = ge.start.dateTime ?? ge.start.date,
              let end = ge.end.dateTime ?? ge.end.date else { return nil }
        let id = "\(ge.id)#\(start.timeIntervalSince1970)"
        guard let event = Event(id: id,
                                title: ge.summary,
                                start: start, end: end,
                                calendarColor: ge.calendarColor,
                                webURL: ge.htmlLink) else { return nil }
        return (event, isAllDay)
    }
}
