import Foundation
import Combine

/// Google Calendar API 経由で今日の event を取得して Domain `DayTimeline` を公開する Gateway。
/// EventKit を使わず、`events.list` で event 一覧を直接取得する。
/// 2 分間隔の自動 reload（spec 008 で 5 分→2 分に短縮）+ 接続/切断時の手動 reload に対応。
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

    /// 最後に reload() が完了した時刻。
    /// ViewModel が sink して「最終更新 X 分前」表示に使う。
    /// nil は一度も reload してない状態（初回起動直後）を示す。
    @Published private(set) var lastReloadAt: Date? = nil

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

    /// 初回 reload と 2 分間隔の自動 reload タイマーを開始する。
    /// 多重起動を防ぐため冒頭で既存タイマーを cancel する。
    /// spec 008: 5 分 → 2 分に短縮。Google で event 編集後の反映遅延を半減。
    func start() {
        reloadTimerCancellable?.cancel()
        isAuthorized = oauthClient.isAuthorized
        Task { await reload() }
        reloadTimerCancellable = Timer.publish(every: 120, on: .main, in: .common)
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
        // spec 008: reload 完了時刻を発火、ViewModel が「最終更新 X 分前」表示に使う
        lastReloadAt = Date()
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
    ///
    /// spec 008: busy block 判定で webURL を nil 化する。
    /// 他人のカレンダーから共有されている「予定あり」event は htmlLink を
    /// 開いてもタイトル / 日時のみが表示され情報価値が低いため、
    /// 既存 fallback 経路（今日ビュー）にクリックを流す。
    private static func convert(_ ge: GoogleAPIEvent) -> (Event, Bool)? {
        let isAllDay = ge.start.dateTime == nil
        guard let start = ge.start.dateTime ?? ge.start.date,
              let end = ge.end.dateTime ?? ge.end.date else { return nil }
        let id = "\(ge.id)#\(start.timeIntervalSince1970)"

        // busy block 判定（spec 010 で改修）：タイトルベースのみ。
        // 旧 spec 008 では visibility=private も busy 扱いしていたが、ユーザー自身が
        // 所有する private event（自分の Meet を private に設定する等）まで誤判定して
        // Calendar ボタンが day view にフォールバックしてしまう問題があった。
        // 「予定あり」「Busy」「空タイトル」のみを busy block とし、visibility は無視する。
        let busyTitles: Set<String> = ["予定あり", "Busy", ""]
        let trimmedSummary = ge.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let isBusyBlock = busyTitles.contains(trimmedSummary)
        let effectiveWebURL = isBusyBlock ? nil : ge.htmlLink

        // spec 010: attendees を Domain Attendee に変換、Meet URL を解決。
        // hangoutLink 優先、無ければ conferenceData.entryPoints[type=video] fallback。
        let attendees: [Attendee] = ge.attendees.map { a in
            Attendee(email: a.email,
                     displayName: a.displayName,
                     responseStatus: ResponseStatus.from(apiString: a.responseStatus))
        }
        let meetURL: URL? = ge.hangoutLink ?? ge.conferenceVideoURL

        guard let event = Event(id: id,
                                title: ge.summary,
                                start: start, end: end,
                                calendarColor: ge.calendarColor,
                                webURL: effectiveWebURL,
                                location: ge.location,
                                note: ge.description,
                                attendees: attendees,
                                meetURL: meetURL) else { return nil }
        return (event, isAllDay)
    }
}
