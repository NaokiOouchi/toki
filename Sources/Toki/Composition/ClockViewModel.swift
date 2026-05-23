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

    /// 円弧クリックで表示される event preview popover の対象 event。
    /// nil で popover 非表示。spec 010 で追加。
    /// 背景クリック / ESC / × ボタン / アクション後に closePreview で nil に戻す。
    @Published private(set) var previewedEvent: RenderableEvent? = nil

    /// 直近のクリック位置（popover 配置基準）。spec 010 Task 11 で位置計算に使用予定。
    @Published private(set) var lastTapLocation: CGPoint? = nil

    /// 最後に Gateway から timeline を受け取った時刻。
    /// Gateway の $lastReloadAt を sink して更新される。
    /// 中央 / 下部表示の「最終更新 X 分前」算出に使う。
    @Published private(set) var lastUpdatedAt: Date? = nil

    /// 明日以降の最初の未来 event（spec 012）。
    /// Gateway の $nextFutureEvent を sink して同期する。
    /// 今日の予定が全終了 / ゼロのとき NextEventLine で日付ラベル付き表示する。
    @Published private(set) var nextFutureEvent: Event? = nil

    /// OAuth 接続フロー中か。AppDelegate が beginAuthorization 開始 / 完了で叩く。
    /// 中央テキストに「接続中…」を表示するための flag。
    @Published private(set) var isConnecting: Bool = false

    /// 各重なりグループの選択 index（key = OverlapGroup.id）。spec 013 で導入。
    /// scroll で hover 中グループの index を増減、modulo で循環。
    /// 未操作グループは存在しない or 0 扱い（取得時 default 0）。
    @Published private(set) var overlapIndices: [String: Int] = [:]

    private let gateway: GoogleCalendarGateway?
    private let calendar: Calendar
    private var cancellables = Set<AnyCancellable>()
    private var minuteTimerCancellable: AnyCancellable?

    /// 直近の hover 位置（local 座標、Canvas 内）。spec 013 で導入。
    /// scroll handler が hover 中グループを特定するために使用。nil = hover 外。
    /// @Published にしない（scroll handler が読むだけで UI 再描画は不要）。
    private var lastHoverPoint: CGPoint? = nil
    /// hover 時に保存した geometry（scroll handler の hitTestGroup で使用）。
    private var lastHoverGeometry: ClockGeometry? = nil

    /// scroll debounce 用の累積 step と Task。spec 013 §Open Questions §7。
    /// 200ms 以内の連続 scroll を 1 step として集計する。
    private var pendingScrollSteps: Int = 0
    private var scrollDebounceTask: Task<Void, Never>? = nil

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

        // spec 008: Gateway の reload 完了時刻を sink して「最終更新 X 分前」表示に使う。
        gateway?.$lastReloadAt
            .receive(on: DispatchQueue.main)
            .sink { [weak self] date in self?.lastUpdatedAt = date }
            .store(in: &cancellables)

        // spec 012: 明日以降の最初の未来 event を sink
        gateway?.$nextFutureEvent
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ev in self?.nextFutureEvent = ev }
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

    /// Domain Event → RenderableEvent 変換ヘルパー（spec 013 で抽出）。
    /// canvasEvents / canvasGroups / canvasBackgroundEvent の共通ロジックを集約。
    /// 角度は `TimeOfDay.clockAngle`、status は `Event.status(at:)` に委譲する。
    private func makeRenderable(_ ev: Event) -> RenderableEvent {
        RenderableEvent(
            id: ev.id,
            title: ev.title,
            startAngle: TimeOfDay.from(date: ev.start, calendar: calendar).clockAngle,
            endAngle: TimeOfDay.from(date: ev.end, calendar: calendar).clockAngle,
            color: ev.calendarColor,
            status: ev.status(at: now),
            start: ev.start,
            end: ev.end,
            webURL: ev.webURL,
            location: ev.location,
            note: ev.note,
            attendees: ev.attendees,
            meetURL: ev.meetURL
        )
    }

    /// 重なりグループごとの描画用データ。spec 013 で追加（後に peek 廃止・合成弧 + i/N badge に改修）。
    /// 各グループから「現 index の event」「1-based currentIndex / totalCount」
    /// 「重なり全体の合成弧角度（groupStart/EndAngle）」を組み立てる。
    var canvasGroups: [RenderableOverlapGroup] {
        guard let tl = timeline else { return [] }
        return tl.groups.map { group in
            let idx = overlapIndices[group.id] ?? 0
            let current = makeRenderable(group.event(at: idx))
            return RenderableOverlapGroup(
                id: group.id,
                current: current,
                currentIndex: idx + 1,
                totalCount: group.count,
                groupStartAngle: TimeOfDay.from(date: group.start, calendar: calendar).clockAngle,
                groupEndAngle: TimeOfDay.from(date: group.end, calendar: calendar).clockAngle
            )
        }
    }

    /// 背景帯描画用。複数 24h event のうち最初の 1 件のみ採用（spec 013 §Open Questions §15）。
    var canvasBackgroundEvent: RenderableEvent? {
        guard let tl = timeline, let ev = tl.backgroundEvents.first else { return nil }
        return makeRenderable(ev)
    }

    /// 後方互換：既存 ClockView / hitTest 経路が canvasEvents を読めるようにする。
    /// canvasGroups の current だけを flatten した配列で、popover や hit-test で使う。
    var canvasEvents: [RenderableEvent] {
        canvasGroups.map(\.current)
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

    /// 下部「終日」ラインの状態。spec 013 改修で追加。
    /// 24h timed event（DayTimeline.backgroundEvents）の最初の 1 件のタイトルを返す。
    /// BottomInfoArea が priority 表示で使用、nil なら非表示。
    var allDayLineState: AllDayLineState? {
        guard accessGranted, let tl = timeline, let ev = tl.backgroundEvents.first else {
            return nil
        }
        return AllDayLineState(title: ev.title)
    }

    /// 下部「次の予定」ラインの状態。
    /// 今日の予定残あり → 今日の next event（既存挙動、日付ラベルなし）
    /// 今日の予定残ゼロ → 明日以降の最初の未来 event（spec 012、日付ラベル付き）
    /// 7 日先までゼロ → nil（NextEventLine 非表示）
    var nextLineState: NextLineState? {
        guard accessGranted else { return nil }

        // 今日の予定残あり → 既存ロジック
        if let tl = timeline, let nxt = tl.nextEvent(after: now) {
            return NextLineState(
                timeHHMM: Self.formatHHMM(nxt.start, calendar: calendar),
                title: nxt.title,
                dateLabel: nil
            )
        }

        // spec 012: 今日の予定残ゼロ → 明日以降の最初の未来 event
        if let future = nextFutureEvent {
            return NextLineState(
                timeHHMM: Self.formatHHMM(future.start, calendar: calendar),
                title: future.title,
                dateLabel: Self.formatDateLabel(future.start, relativeTo: now, calendar: calendar)
            )
        }
        return nil
    }

    /// hover 時に BottomInfoArea が下に伸びる高さ（spec 013 改修）。
    /// AppDelegate がこの値を使って window を伸ばすことで、clock 領域を保ったまま
    /// 拡張表示できる。固定値ではなく動的計算するのは、extras の組み合わせで
    /// 必要な高さが変わるため（0 / 1 行 / 2 行）。
    /// estimates（default textScale=1.0 前提）：
    /// - AllDayEventLine row：~20pt（11pt font + 内部 padding）
    /// - lastUpdated row：~16pt（9pt font + 内部 padding）
    /// - VStack 行間 spacing：4pt
    var hoverExpansionDelta: CGFloat {
        let hasNext = nextLineState != nil
        let hasAllDay = allDayLineState != nil
        let hasUpdated = lastUpdatedFormatted != nil

        var delta: CGFloat = 0
        // primary が next の時、extra に allDay 1 行が追加される
        if hasNext && hasAllDay {
            delta += 4 + 20  // spacing + AllDayEventLine row
        }
        // event がある時、最終更新が hover 時末尾に表示される
        if (hasNext || hasAllDay) && hasUpdated {
            delta += 4 + 16  // spacing + lastUpdated row
        }
        return delta
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

    /// 日付ラベル整形 helper（spec 012）。
    /// now を起点に target までの日数差で表示形式を切り替える。
    /// - 今日：nil
    /// - 翌日："明日"
    /// - 翌々日："明後日"
    /// - 3〜6 日後：曜日名（"金曜" / "土曜" 等）
    /// - 7 日後以降："M/d (曜)" フォーマット
    /// 日数差は startOfDay 同士の Calendar.dateComponents で算出（DST 跨ぎ安全）。
    private static func formatDateLabel(_ target: Date,
                                        relativeTo now: Date,
                                        calendar: Calendar) -> String? {
        let nowDay = calendar.startOfDay(for: now)
        let targetDay = calendar.startOfDay(for: target)
        let comps = calendar.dateComponents([.day], from: nowDay, to: targetDay)
        guard let dayDiff = comps.day else { return nil }
        switch dayDiff {
        case ..<1: return nil
        case 1: return "明日"
        case 2: return "明後日"
        case 3...6: return weekdayName(of: target, calendar: calendar)
        default: return shortDateLabel(of: target, calendar: calendar)
        }
    }

    /// 曜日名（"日曜" / "月曜" / ...）。
    /// DateFormatter のロケール依存を避けるため日本語ハードコード。
    /// CLAUDE.md「個人利用、Mac専用」前提で日本語固定 OK。
    private static func weekdayName(of date: Date, calendar: Calendar) -> String {
        let weekday = calendar.component(.weekday, from: date)  // 1=日, 2=月, ..., 7=土
        let names = ["日曜", "月曜", "火曜", "水曜", "木曜", "金曜", "土曜"]
        return names[max(1, min(7, weekday)) - 1]
    }

    /// "M/d (曜)" 形式（例：5/26 (月)）。7 日後の境界用。
    private static func shortDateLabel(of date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.month, .day], from: date)
        let m = c.month ?? 1
        let d = c.day ?? 1
        let weekday = calendar.component(.weekday, from: date)
        let shortNames = ["日", "月", "火", "水", "木", "金", "土"]
        return "\(m)/\(d) (\(shortNames[max(1, min(7, weekday)) - 1]))"
    }

    // MARK: - ホバーハンドラ

    /// イベント円弧上のマウスホバーを処理する。
    /// `.active(location)` で hitTest し該当イベントがあれば TooltipState を組み立てる。
    /// `.ended` または該当なしで nil に戻す。
    /// Equatable 比較により同値時の再描画は no-op となりチラつきを抑える。
    func handleHover(phase: HoverPhase, geometry: ClockGeometry) {
        switch phase {
        case .active(let location):
            // spec 013: scroll handler が hover 中グループ特定に使う
            lastHoverPoint = location
            lastHoverGeometry = geometry
            if let event = hitTest(point: location, events: canvasEvents, geometry: geometry) {
                // spec 013: 重なりグループに属する event なら "i/N" を tooltip にも出す
                // （円弧外側の badge が tooltip に隠れて見えない場合の補完）
                let cycle = canvasGroups.first { $0.current.id == event.id }
                    .flatMap { g -> String? in
                        g.totalCount > 1 ? "\(g.currentIndex)/\(g.totalCount)" : nil
                    }
                let tooltip = TooltipState(
                    startEndLabel: Self.formatTimeRange(event.start, event.end, calendar: calendar),
                    title: event.title,
                    position: location,
                    cycleIndicator: cycle
                )
                if hoveredTooltip != tooltip {
                    hoveredTooltip = tooltip
                }
            } else if hoveredTooltip != nil {
                hoveredTooltip = nil
            }
        case .ended:
            // spec 013: hover 終了で scroll 操作対象を解除
            lastHoverPoint = nil
            lastHoverGeometry = nil
            if hoveredTooltip != nil {
                hoveredTooltip = nil
            }
        }
    }

    // MARK: - クリックハンドラ

    /// イベント円弧のクリックを処理する。
    /// 円弧クリックを処理する（spec 010 で popover 表示方式に変更）。
    /// 全 event で popover を開く（busy block / 共有 event 含めて UX を一貫させる）。
    /// 「Calendar で開く」ボタン押下時のリンク先は webURL（あれば）/ 今日のビュー（fallback）。
    /// ホバーツールチップは即時消去する（クリックとの UX 競合回避）。
    func handleArcTap(at point: CGPoint, geometry: ClockGeometry) {
        guard let event = hitTest(point: point, events: canvasEvents, geometry: geometry) else { return }
        hoveredTooltip = nil
        lastTapLocation = point
        previewedEvent = event
    }

    /// popover を閉じる。背景クリック / ESC / × ボタン / アクションボタン押下後に呼ばれる。
    func closePreview() {
        previewedEvent = nil
        lastTapLocation = nil
    }

    /// "Meet で開く" アクション。meetURL を NSWorkspace で開いて popover を閉じる。
    func openMeet() {
        guard let url = previewedEvent?.meetURL else { return }
        NSWorkspace.shared.open(url)
        closePreview()
    }

    /// "Calendar で開く" アクション。webURL があればそれを、無ければ今日のビューを開く。
    /// 共有「予定あり」event は webURL が nil なので、day view fallback を使う。
    func openCalendarURL() {
        guard let ev = previewedEvent else { return }
        let url: URL
        if let webURL = ev.webURL {
            url = webURL
        } else {
            guard let dayURL = URL(string: Self.googleCalendarDayURL(for: ev.start, calendar: calendar)) else { return }
            url = dayURL
        }
        NSWorkspace.shared.open(url)
        closePreview()
    }

    /// popover ヘッダーに表示する時刻範囲文字列 "HH:MM - HH:MM"。
    /// previewedEvent が nil のときは nil。
    var previewTimeLabel: String? {
        guard let ev = previewedEvent else { return nil }
        return Self.formatTimeRange(ev.start, ev.end, calendar: calendar)
    }

    /// popover ヘッダーに表示する cycle indicator "i/N"（spec 013 改修）。
    /// previewedEvent が属する OverlapGroup が重なり（count > 1）の時のみ返す。
    /// 単独 event や popover 非表示時は nil。
    /// tooltip の cycleIndicator と同じ pattern で、popover 表示中に scroll で
    /// event を cycle した時の進行状況を伝える。
    var previewCycleIndicator: String? {
        guard let preview = previewedEvent, let tl = timeline else { return nil }
        guard let group = tl.groups.first(where: { g in
            g.events.contains(where: { $0.id == preview.id })
        }) else { return nil }
        guard group.isOverlapping else { return nil }
        let idx = overlapIndices[group.id] ?? 0
        return "\(idx + 1)/\(group.count)"
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

    // MARK: - スクロールハンドラ（spec 013）

    /// ScrollCatcher からの raw scroll を受け取り、200ms debounce 後に index を更新する（spec 013）。
    /// hover 外 / 重なりなしグループでは no-op（debounce 適用時にも判定）。
    /// 上スクロール = 次 event（index++）、下スクロール = 前 event（index--）。
    /// macOS の natural scroll でも deltaY 符号は同じ（trackpad 上向き = +）。
    func handleScrollRaw(deltaY: CGFloat) {
        let step = deltaY > 0 ? 1 : -1
        pendingScrollSteps += step

        scrollDebounceTask?.cancel()
        scrollDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)  // 200ms
            guard let self, !Task.isCancelled else { return }
            let pending = self.pendingScrollSteps
            self.pendingScrollSteps = 0
            self.applyScroll(steps: pending)
        }
    }

    /// debounce 後に呼ばれる本体。対象 group の index を循環更新する（spec 013）。
    /// scroll の対象 group の決定優先度：
    ///   1. popover 表示中：previewedEvent が属する group（backdrop が hover を遮断するため）
    ///   2. hover 中：hover 位置から hitTestGroup で特定
    /// どちらでもない / 重なりなしグループは no-op。
    /// index 更新後、tooltip と popover も新 current event に同期する。
    private func applyScroll(steps: Int) {
        guard steps != 0 else { return }

        // scroll 対象 group を popover 優先 → hover の順で決定
        let targetGroup: OverlapGroup?
        if let preview = previewedEvent, let tl = timeline {
            targetGroup = tl.groups.first { g in
                g.events.contains(where: { $0.id == preview.id })
            }
        } else if let point = lastHoverPoint, let geo = lastHoverGeometry {
            targetGroup = hitTestGroup(at: point, geometry: geo)
        } else {
            targetGroup = nil
        }

        guard let group = targetGroup, group.isOverlapping else { return }

        let current = overlapIndices[group.id] ?? 0
        let c = group.count
        let newIndex = ((current + steps) % c + c) % c
        overlapIndices[group.id] = newIndex

        // 新 current event に tooltip / popover を同期する。
        let newCurrent = group.event(at: newIndex)

        // hover tooltip 再構築（hover 中の時のみ）
        if let point = lastHoverPoint {
            let newTooltip = TooltipState(
                startEndLabel: Self.formatTimeRange(newCurrent.start, newCurrent.end, calendar: calendar),
                title: newCurrent.title,
                position: point,
                cycleIndicator: "\(newIndex + 1)/\(group.count)"
            )
            if hoveredTooltip != newTooltip { hoveredTooltip = newTooltip }
        }

        // popover 表示中で、対象 group 内の event を表示しているなら新 current に置換。
        if let prev = previewedEvent, group.events.contains(where: { $0.id == prev.id }) {
            previewedEvent = makeRenderable(newCurrent)
        }
    }

    /// hover 位置から OverlapGroup を特定する（spec 013）。
    /// group の **合成弧範囲（最長 event の範囲）** で hitTest して、対応する Domain OverlapGroup を返す。
    /// current event の弧範囲だけだと、短い event 表示中に長い event の範囲で scroll が効かなくなる
    /// （例：A=09:00-10:00 と B=09:00-09:15 重なり、current=B 表示中に 09:15-10:00 で scroll 不発）。
    /// 薄色で描画される合成弧の範囲全体で scroll を受けるため、group 内最長 event の範囲のどこに
    /// hover しても cycle 可能になる。
    /// tooltip / popover 用の hitTest は引き続き current event の弧範囲を使う（表示中 event のみ反応）。
    private func hitTestGroup(at point: CGPoint, geometry: ClockGeometry) -> OverlapGroup? {
        guard let tl = timeline else { return nil }
        let groups = canvasGroups
        for (idx, rgroup) in groups.enumerated() {
            // 仮想 RenderableEvent を作って、合成弧範囲（groupStartAngle〜groupEndAngle）で hitTest。
            // 既存 hitTest と annulusPath ロジックを流用するための wrap。
            let groupArc = RenderableEvent(
                id: rgroup.id,
                title: rgroup.current.title,
                startAngle: rgroup.groupStartAngle,
                endAngle: rgroup.groupEndAngle,
                color: rgroup.current.color,
                status: rgroup.current.status,
                start: rgroup.current.start,
                end: rgroup.current.end,
                webURL: rgroup.current.webURL,
                location: nil,
                note: nil,
                attendees: [],
                meetURL: nil
            )
            if hitTest(point: point, events: [groupArc], geometry: geometry) != nil {
                return tl.groups[idx]
            }
        }
        return nil
    }
}
