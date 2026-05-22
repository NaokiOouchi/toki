import Foundation
import AppKit
import Combine
import CoreGraphics
import SwiftUI

/// 時計 UI 用 ViewModel。
/// Gateway を購読して `timeline` を保持し、`now` を分単位で進めながら
/// UI に必要な派生 state（`canvasEvents` / `centerState` / `nextLineState`）を提供する。
/// `@MainActor` を class 全体に付けることで `@Published` 更新と派生計算の
/// スレッド安全性を確保する。
@MainActor
final class ClockViewModel: ObservableObject {
    @Published private(set) var now: Date = Date()
    @Published private(set) var timeline: DayTimeline? = nil
    @Published private(set) var accessGranted: Bool = false

    /// ホバー中のイベントから組み立てるツールチップ状態。
    /// nil の場合はツールチップを表示しない。
    /// Equatable 比較により同値時の再描画を抑える。
    @Published private(set) var hoveredTooltip: TooltipState? = nil

    /// 最後に Gateway から timeline を受け取った時刻。
    /// Gateway の $lastReloadAt を sink して更新される。
    /// 中央 / 下部表示の「最終更新 X 分前」算出に使う。
    @Published private(set) var lastUpdatedAt: Date? = nil

    /// OAuth 接続フロー中か。AppDelegate が beginAuthorization 開始 / 完了で叩く。
    /// 中央テキストに「接続中…」を表示するための flag。
    @Published private(set) var isConnecting: Bool = false

    private let gateway: GoogleCalendarGateway?
    private let calendar: Calendar
    private var cancellables = Set<AnyCancellable>()
    private var minuteTimerCancellable: AnyCancellable?

    init(gateway: GoogleCalendarGateway?, calendar: Calendar = .current) {
        self.gateway = gateway
        self.calendar = calendar
    }

    /// ViewModel を起動する。OAuth 接続状態の取り込み → 購読開始 → タイマー開始 → wake 監視を順に行う。
    /// `accessGranted` は EventKit 権限ではなく「Google Calendar に OAuth 接続済みか」を意味する。
    func start() async {
        accessGranted = gateway?.isAuthorized ?? false

        gateway?.start()

        // @Published isAuthorized を購読して accessGranted を自動同期する。
        // refresh 失敗で Keychain がクリアされた場合に中央テキストが「右クリックで接続」へ転落する。
        gateway?.$isAuthorized
            .receive(on: DispatchQueue.main)
            .sink { [weak self] granted in self?.accessGranted = granted }
            .store(in: &cancellables)

        gateway?.timelineUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tl in self?.timeline = tl }
            .store(in: &cancellables)

        now = Date()
        scheduleMinuteTimer()

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.now = Date()
                self.scheduleMinuteTimer()
                self.accessGranted = self.gateway?.isAuthorized ?? false
                Task { await self.gateway?.reload() }
            }
            .store(in: &cancellables)
    }

    /// OAuth 接続状態を最新に同期する。
    /// AppDelegate が beginAuthorization / revoke 完了後に呼び出して即時 UI 反映する。
    func refreshAuthorizationState() {
        accessGranted = gateway?.isAuthorized ?? false
    }

    /// 手動再読込。右クリック「再読込」メニューから呼ばれる。
    /// isConnecting は変えない（接続フロー専用）。
    func handleReload() async {
        await gateway?.reload()
    }

    /// 接続フロー中フラグを更新する。AppDelegate.handleConnect から呼ばれる。
    func setConnecting(_ value: Bool) {
        isConnecting = value
    }

    /// 最後の reload からの経過時間を人間可読な形式に整形する。
    /// 60 秒未満は「最終更新 たった今」、それ以上は「最終更新 X 分前」。
    /// lastUpdatedAt が nil（一度も成功 reload してない）の場合は nil。
    var lastUpdatedFormatted: String? {
        guard let updated = lastUpdatedAt else { return nil }
        let elapsed = Int(now.timeIntervalSince(updated))
        if elapsed < 60 { return "最終更新 たった今" }
        return "最終更新 \(elapsed / 60) 分前"
    }

    /// 次の :00 までの差分を待ってから 60 秒ごとのタイマーを開始する。
    /// 既存タイマーがあれば cancel して再アラインする（wake 復帰時に使う）。
    private func scheduleMinuteTimer() {
        minuteTimerCancellable?.cancel()
        let nowDate = Date()
        let secondsToNextMinute = 60 - calendar.component(.second, from: nowDate)
        // 0 秒待ちで再起動するとタイマー連発リスクがあるため、ちょうど :00 に
        // 着地している場合は次の分まで 60 秒待ってからアラインする。
        let delay = secondsToNextMinute == 0 ? 60 : secondsToNextMinute
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay)) { [weak self] in
            guard let self else { return }
            self.now = Date()
            self.minuteTimerCancellable = Timer.publish(every: 60, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.now = Date() }
        }
    }

    // MARK: - 派生 state

    /// 現在時刻を時計盤の角度（ラジアン）に変換した値。
    /// VM が保持する `calendar` を使うことで `canvasEvents` の角度計算と
    /// 同じカレンダー設定で針の角度を算出する。
    var nowAngle: Double {
        TimeOfDay.from(date: now, calendar: calendar).clockAngle
    }

    /// Domain Event を UI 描画用 `RenderableEvent` に変換する。
    /// 角度は `TimeOfDay.clockAngle`、status は `Event.status(at:)` に委譲する。
    var canvasEvents: [RenderableEvent] {
        guard let tl = timeline else { return [] }
        return tl.events.map { ev in
            RenderableEvent(
                id: ev.id,
                title: ev.title,
                startAngle: TimeOfDay.from(date: ev.start, calendar: calendar).clockAngle,
                endAngle: TimeOfDay.from(date: ev.end, calendar: calendar).clockAngle,
                color: ev.calendarColor,
                status: ev.status(at: now),
                start: ev.start,
                end: ev.end,
                webURL: ev.webURL
            )
        }
    }

    /// 中央 3 行テキストの表示状態を組み立てる。
    /// 権限なし / 未取得 / 進行中 / 次あり / 予定なし の 5 パターンを網羅する。
    var centerState: CenterState {
        let timeStr = Self.formatHHMM(now, calendar: calendar)
        if isConnecting {
            return .freeTime(time: timeStr, subtitle: "接続中…")
        }
        if !accessGranted {
            return .freeTime(time: timeStr, subtitle: "右クリックで接続")
        }
        guard let tl = timeline else {
            return .freeTime(time: timeStr, subtitle: "読み込み中")
        }
        if let cur = tl.currentEvent(at: now) {
            // 「あと 0 分」表示にならないよう ceil で次の整数分に丸める。
            let remaining = Int(ceil(cur.end.timeIntervalSince(now) / 60))
            return .duringEvent(time: timeStr,
                                title: cur.title,
                                remaining: "残り \(Self.formatDurationMinutes(remaining))")
        }
        if let nxt = tl.nextEvent(after: now) {
            let until = Int(ceil(nxt.start.timeIntervalSince(now) / 60))
            return .freeTime(time: timeStr, subtitle: "次まで \(Self.formatDurationMinutes(until))")
        }
        return .freeTime(time: timeStr, subtitle: "予定なし")
    }

    /// 分単位の数値を読みやすい形式に整形する。
    /// 60 分未満は「X 分」、60 分以上は「X 時間 Y 分」（Y=0 のときは「X 時間」）。
    /// 例：45 → "45 分"、60 → "1 時間"、90 → "1 時間 30 分"、600 → "10 時間"
    static func formatDurationMinutes(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) 分" }
        let hours = minutes / 60
        let mins = minutes % 60
        if mins == 0 { return "\(hours) 時間" }
        return "\(hours) 時間 \(mins) 分"
    }

    /// 下部「次の予定」ラインの状態。次イベントが無い／権限なし／未取得は nil。
    var nextLineState: NextLineState? {
        guard accessGranted,
              let tl = timeline,
              let nxt = tl.nextEvent(after: now) else { return nil }
        return NextLineState(
            timeHHMM: Self.formatHHMM(nxt.start, calendar: calendar),
            title: nxt.title
        )
    }

    /// HH:MM 形式の時刻文字列を返す。
    private static func formatHHMM(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// "HH:MM - HH:MM" 形式の時刻範囲文字列。既存 `formatHHMM` を再利用する。
    private static func formatTimeRange(_ start: Date, _ end: Date, calendar: Calendar) -> String {
        "\(formatHHMM(start, calendar: calendar)) - \(formatHHMM(end, calendar: calendar))"
    }

    // MARK: - ホバーハンドラ

    /// イベント円弧上のマウスホバーを処理する。
    /// `.active(location)` で hitTest し該当イベントがあれば TooltipState を組み立てる。
    /// `.ended` または該当なしで nil に戻す。
    /// Equatable 比較により同値時の再描画は no-op となりチラつきを抑える。
    func handleHover(phase: HoverPhase, geometry: ClockGeometry) {
        switch phase {
        case .active(let location):
            if let event = hitTest(point: location, events: canvasEvents, geometry: geometry) {
                let tooltip = TooltipState(
                    startEndLabel: Self.formatTimeRange(event.start, event.end, calendar: calendar),
                    title: event.title,
                    position: location
                )
                if hoveredTooltip != tooltip {
                    hoveredTooltip = tooltip
                }
            } else if hoveredTooltip != nil {
                hoveredTooltip = nil
            }
        case .ended:
            if hoveredTooltip != nil {
                hoveredTooltip = nil
            }
        }
    }

    // MARK: - クリックハンドラ

    /// イベント円弧のクリックを処理する。
    /// Google Calendar API 経由で取得した webURL があればそれを開く（spec 005）。
    /// なければ今日のビュー fallback（spec 003 から継続）。
    /// ホバーツールチップは即時消去する（クリックとの UX 競合回避）。
    func handleArcTap(at point: CGPoint, geometry: ClockGeometry) {
        guard let event = hitTest(point: point, events: canvasEvents, geometry: geometry) else { return }
        hoveredTooltip = nil
        let url: URL
        if let webURL = event.webURL {
            url = webURL
        } else {
            guard let dayURL = URL(string: Self.googleCalendarDayURL(for: event.start, calendar: calendar)) else { return }
            url = dayURL
        }
        NSWorkspace.shared.open(url)
    }

    /// イベント開始日から Google Calendar の day view URL を組み立てる。
    /// 形式：https://calendar.google.com/calendar/u/0/r/day/YYYY/MM/DD
    /// `u/0` は固定（複数アカウント対応は MVP 範囲外、設定 UI 必須なので Phase 3 行き）。
    /// ローカルタイムゾーンの暦日を採用（時計表示と整合）。
    private static func googleCalendarDayURL(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let y = c.year ?? 1970
        let m = c.month ?? 1
        let d = c.day ?? 1
        return String(format: "https://calendar.google.com/calendar/u/0/r/day/%04d/%02d/%02d", y, m, d)
    }
}
