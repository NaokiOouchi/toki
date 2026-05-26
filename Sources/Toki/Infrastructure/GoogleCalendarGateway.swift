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

    /// 明日以降の最初の未来 event（spec 012）。
    /// 今日の予定が全て終了 / ゼロのとき NextEventLine に表示する。
    /// 7 日先まで何もない場合は nil。Event の Equatable は id ベースで重複変更時の再描画を抑制する。
    /// 終日（all-day）event は時刻ラベルが付けられないため除外する。
    @Published private(set) var nextFutureEvent: Event? = nil

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
        let (timeline, nextFuture) = await fetchTimelineAndNextFuture()
        // refresh 失敗で Keychain がクリアされていれば isAuthorized=false に転落
        isAuthorized = oauthClient.isAuthorized
        // spec 008: reload 完了時刻を発火、ViewModel が「最終更新 X 分前」表示に使う
        lastReloadAt = Date()
        nextFutureEvent = nextFuture
        subject.send(timeline)
    }

    /// 7 日先までの event を fetch し、今日分は DayTimeline、明日以降分の
    /// 先頭 1 件（時刻付き）は nextFutureEvent として返す（spec 012）。
    /// 既存の DayTimeline は今日 1 日分の責務を維持する（Domain 不変条件）。
    /// 明日以降の all-day event は時刻ラベルが付けられないため除外する。
    private func fetchTimelineAndNextFuture() async -> (DayTimeline, Event?) {
        let dayStart = calendar.startOfDay(for: Date())
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart),
              let weekEnd = calendar.date(byAdding: .day, value: 7, to: dayStart) else {
            return (DayTimeline(date: dayStart, events: []), nil)
        }
        guard oauthClient.isAuthorized else {
            return (DayTimeline(date: dayStart, events: []), nil)
        }
        do {
            let apiEvents = try await api.fetchEventsAhead(timeMin: dayStart, timeMax: weekEnd)

            // 7 日分を「今日」「明日以降の時刻付き」に分離。明日以降の all-day は除外。
            var todayRaw: [Event] = []
            var todayAllDay: [Bool] = []
            var futureEvents: [Event] = []
            for ge in apiEvents {
                guard let (event, isAllDay) = Self.convert(ge) else { continue }
                if event.start < dayEnd {
                    todayRaw.append(event)
                    todayAllDay.append(isAllDay)
                } else if !isAllDay {
                    futureEvents.append(event)
                }
            }
            let timeline = DayTimeline.make(date: dayStart,
                                            rawEvents: todayRaw,
                                            allDayFlags: todayAllDay,
                                            calendar: calendar)
            // 未来 event は start 昇順で並び替え、先頭 1 件を採用
            let nextFuture = futureEvents.sorted { $0.start < $1.start }.first
            return (timeline, nextFuture)
        } catch {
            print("Google Calendar API fetch failed: \(error)")
            // 失敗時は last-known 維持（spec 008 と整合）
            return (subject.value, self.nextFutureEvent)
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
        // spec 029: Google Calendar event 個別色 (colorId) を CGColor に解決。
        // nil なら親 calendar 色が使われる（Event.displayColor で fallback 実装）。
        let eventColor = ge.colorId.flatMap { EventColorPalette.cgColor(forColorId: $0) }

        guard let event = Event(id: id,
                                title: ge.summary,
                                start: start, end: end,
                                calendarColor: ge.calendarColor,
                                eventColor: eventColor,
                                webURL: effectiveWebURL,
                                location: ge.location,
                                note: ge.description,
                                attendees: attendees,
                                meetURL: meetURL) else { return nil }
        return (event, isAllDay)
    }
}
