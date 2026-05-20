import Foundation
import AppKit
import Combine
import CoreGraphics

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
                externalIdentifier: ev.externalIdentifier
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

    // MARK: - クリックハンドラ

    /// イベント円弧のクリックを処理する。
    /// 該当イベントの externalIdentifier から純正カレンダー.app を開く。
    /// ヒットなし / externalIdentifier 欠落 / URL 組み立て失敗の場合は何もしない（無音）。
    func handleArcTap(at point: CGPoint, geometry: ClockGeometry) {
        guard let event = hitTest(point: point, events: canvasEvents, geometry: geometry) else { return }
        guard let extID = event.externalIdentifier,
              !extID.isEmpty,
              let url = URL(string: "ical://ekevent/\(extID)?method=show&options=more") else { return }
        if !NSWorkspace.shared.open(url) {
            // URL scheme が無視された場合のフォールバック：カレンダー.app を起動だけする
            if let fallback = URL(string: "ical:") {
                NSWorkspace.shared.open(fallback)
            }
        }
    }
}
