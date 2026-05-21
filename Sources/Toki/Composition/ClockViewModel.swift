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

    private let gateway: EventKitGateway
    private let calendar: Calendar
    private var cancellables = Set<AnyCancellable>()
    private var minuteTimerCancellable: AnyCancellable?

    init(gateway: EventKitGateway, calendar: Calendar = .current) {
        self.gateway = gateway
        self.calendar = calendar
    }

    /// ViewModel を起動する。権限要求 → 購読開始 → タイマー開始 → wake 監視を順に行う。
    func start() async {
        let result = await gateway.requestAccess()
        // AccessResult は `.error(Error)` を持つため Equatable 合成されない。
        // 明示的にパターンマッチで判定する。
        if case .granted = result {
            accessGranted = true
        } else {
            accessGranted = false
        }
        gateway.start()
        gateway.timelineUpdates
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
            }
            .store(in: &cancellables)
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
                externalIdentifier: ev.externalIdentifier,
                start: ev.start,
                end: ev.end,
                calendarTitle: ev.calendarTitle
            )
        }
    }

    /// 中央 3 行テキストの表示状態を組み立てる。
    /// 権限なし / 未取得 / 進行中 / 次あり / 予定なし の 5 パターンを網羅する。
    var centerState: CenterState {
        let timeStr = Self.formatHHMM(now, calendar: calendar)
        if !accessGranted {
            return .freeTime(time: timeStr, subtitle: "権限が必要")
        }
        guard let tl = timeline else {
            return .freeTime(time: timeStr, subtitle: "読み込み中")
        }
        if let cur = tl.currentEvent(at: now) {
            // 「あと 0 分」表示にならないよう ceil で次の整数分に丸める。
            let remaining = Int(ceil(cur.end.timeIntervalSince(now) / 60))
            return .duringEvent(time: timeStr,
                                title: cur.title,
                                remaining: "残り \(remaining)分")
        }
        if let nxt = tl.nextEvent(after: now) {
            let until = Int(ceil(nxt.start.timeIntervalSince(now) / 60))
            return .freeTime(time: timeStr, subtitle: "次まで \(until)分")
        }
        return .freeTime(time: timeStr, subtitle: "予定なし")
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
    /// 該当イベントの開始日から Google Calendar の今日のビュー URL を組み立て、
    /// デフォルトブラウザで開く。Calendar.app は spec 003 で撤去済み。
    /// ホバーツールチップは即時消去する（クリックとの UX 競合回避）。
    /// ヒットなし / URL 組み立て失敗の場合は何もしない（無音）。
    func handleArcTap(at point: CGPoint, geometry: ClockGeometry) {
        guard let event = hitTest(point: point, events: canvasEvents, geometry: geometry) else { return }
        hoveredTooltip = nil
        let urlStr = Self.calendarURL(for: event, calendar: calendar)
        guard let url = URL(string: urlStr) else { return }
        NSWorkspace.shared.open(url)
    }

    /// クリック対象イベントから開くべき URL を決定する。
    /// Google event なら detail URL、それ以外（および詳細生成失敗時）は今日のビュー fallback。
    private static func calendarURL(for event: RenderableEvent, calendar: Calendar) -> String {
        if let detail = googleEventDetailURL(for: event) {
            return detail
        }
        return googleCalendarDayURL(for: event.start, calendar: calendar)
    }

    /// Google Calendar の event detail URL を組み立てる。
    /// 失敗時は nil（呼び出し側で今日のビュー fallback）。
    ///
    /// 形式：https://calendar.google.com/calendar/u/0/r/event?eid=<URL-safe-base64>
    /// eid 中身：base64("<base_uid> <calendar_email>")
    ///   - base_uid：externalIdentifier から `_R<digits>T<digits>` suffix を除去
    ///   - URL-safe：`+`→`-`、`/`→`_`、`=` 除去
    private static func googleEventDetailURL(for event: RenderableEvent) -> String? {
        guard let extID = event.externalIdentifier,
              extID.hasSuffix("@google.com"),
              !event.calendarTitle.isEmpty else { return nil }

        let baseUID = stripRecurrenceSuffix(from: extID)
        let raw = "\(baseUID) \(event.calendarTitle)"
        guard let data = raw.data(using: .utf8) else { return nil }
        let b64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "https://calendar.google.com/calendar/u/0/r/event?eid=\(b64)"
    }

    /// `_R<digits>T<digits>` の繰り返し instance suffix を除去する。
    /// 例：`b7ru16r58op25kb1nlvn6993hq_R20251106T120000@google.com`
    ///   → `b7ru16r58op25kb1nlvn6993hq@google.com`
    /// 単発イベントには影響しない。
    private static func stripRecurrenceSuffix(from externalID: String) -> String {
        guard let range = externalID.range(of: "_R[0-9]+T[0-9]+", options: .regularExpression) else {
            return externalID
        }
        var stripped = externalID
        stripped.removeSubrange(range)
        return stripped
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
