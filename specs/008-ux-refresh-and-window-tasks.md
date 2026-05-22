# 008 — ux-refresh-and-window: Tasks

参照: `specs/008-ux-refresh-and-window.md` / `specs/008-ux-refresh-and-window-plan.md`

合計: **13 tasks**

実装順序：上から順に。各 task は fresh subagent に渡して 1 commit ずつ。

Domain 層は無変更（テスト 36 ケース全 pass 維持）。Infrastructure / Composition / UI / App / Window のみ変更。

---

## Task 1: ポーリング間隔を 120 秒に短縮

**Commit**: `feat(infra): GoogleCalendarGateway のポーリング間隔を 120 秒に短縮`

**目的**: Google で event 編集後の Toki 反映遅延を最大 5 分 → 最大 2 分に短縮。

**実装**:

ファイル: `Sources/Toki/Infrastructure/GoogleCalendarGateway.swift`（編集）

`start()` 内の `Timer.publish(every: 300, ...)` を `every: 120, ...` に変更。コメント更新。

**完了条件**:
```bash
grep -n "Timer.publish(every: 120" Sources/Toki/Infrastructure/GoogleCalendarGateway.swift
# → 1 件

grep -c "Timer.publish(every: 300" Sources/Toki/Infrastructure/GoogleCalendarGateway.swift
# → 0

swift build && swift test  # 36 ケース pass
```

**コミット**: `git commit -m "feat(infra): GoogleCalendarGateway のポーリング間隔を 120 秒に短縮"`

**依存**: なし

---

## Task 2: GoogleAPIEvent に visibility を追加、parseEvent で抽出

**Commit**: `feat(infra): GoogleAPIEvent に visibility を追加、parseEvent で抽出`

**目的**: 共有 event の busy block 判定に必要な `visibility` フィールドを API レスポンスから取得可能にする。Domain には漏らさない（Infrastructure 中間型のみ）。

**実装**:

ファイル: `Sources/Toki/Infrastructure/GoogleCalendarAPI.swift`（編集）

#### Step 1: GoogleAPIEvent に field 追加

```swift
struct GoogleAPIEvent {
    // 既存フィールド
    let visibility: String?  // 新規："default" / "public" / "private" / "confidential" / nil
}
```

#### Step 2: parseEvent で抽出

`parseEvent` 内の `GoogleAPIEvent(...)` 初期化で `visibility: item["visibility"] as? String` を追加。

**完了条件**:
```bash
grep -n "let visibility: String?" Sources/Toki/Infrastructure/GoogleCalendarAPI.swift
# → 1 件

grep -n 'visibility: item\["visibility"\]' Sources/Toki/Infrastructure/GoogleCalendarAPI.swift
# → 1 件

swift build && swift test
```

**コミット**: `git commit -m "feat(infra): GoogleAPIEvent に visibility を追加、parseEvent で抽出"`

**依存**: なし

---

## Task 3: busy block 判定で webURL を nil 化

**Commit**: `feat(infra): busy block 判定で webURL を nil 化（GoogleCalendarGateway.convert）`

**目的**: 共有カレンダー由来の「予定あり」event は detail URL を開いても何も情報が出ないため、`Event.webURL` を nil 化して既存 fallback 経路（今日ビュー）に流す。

**実装**:

ファイル: `Sources/Toki/Infrastructure/GoogleCalendarGateway.swift`（編集）

`convert(_:)` 内で busy block 判定を追加し、該当する場合のみ `webURL` を nil 化：

```swift
private static func convert(_ ge: GoogleAPIEvent) -> (Event, Bool)? {
    let isAllDay = ge.start.dateTime == nil
    guard let start = ge.start.dateTime ?? ge.start.date,
          let end = ge.end.dateTime ?? ge.end.date else { return nil }
    let id = "\(ge.id)#\(start.timeIntervalSince1970)"

    // busy block 判定：他人のカレンダーから共有されている「予定あり」等は
    // detail URL を開いても情報が出ないため webURL を nil 化して今日ビュー fallback に流す。
    let busyTitles: Set<String> = ["予定あり", "Busy", ""]
    let trimmedSummary = ge.summary.trimmingCharacters(in: .whitespacesAndNewlines)
    let isBusyBlock = (ge.visibility == "private") || busyTitles.contains(trimmedSummary)
    let effectiveWebURL = isBusyBlock ? nil : ge.htmlLink

    guard let event = Event(id: id,
                            title: ge.summary,
                            start: start, end: end,
                            calendarColor: ge.calendarColor,
                            webURL: effectiveWebURL) else { return nil }
    return (event, isAllDay)
}
```

**完了条件**:
```bash
grep -n "isBusyBlock" Sources/Toki/Infrastructure/GoogleCalendarGateway.swift
# → 2 件以上

grep -n 'ge.visibility == "private"' Sources/Toki/Infrastructure/GoogleCalendarGateway.swift
# → 1 件

swift build && swift test
```

**コミット**: `git commit -m "feat(infra): busy block 判定で webURL を nil 化（GoogleCalendarGateway.convert）"`

**依存**: Task 2

---

## Task 4: AppSettings struct を新規追加（UserDefaults wrapper）

**Commit**: `feat(infra): AppSettings struct を新規追加（UserDefaults wrapper）`

**目的**: 透過率 / ウィンドウフレームを `UserDefaults` に保存 / 復元する薄い wrapper。Phase 2 で複数プロパティが追加される想定で 1 つのファイルに集約。

**実装**:

ファイル: `Sources/Toki/Infrastructure/AppSettings.swift`（新規）

```swift
import Foundation
import AppKit

/// UserDefaults wrapper for app-level settings (opacity / windowFrame).
/// シングルトン的に `AppSettings.shared` でアクセス、struct 値型で内部状態を持たない。
/// 個別キーで UserDefaults に保存し、必要に応じて clamp / 検証する。
struct AppSettings {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let opacity = "toki.opacity"
        static let windowFrameX = "toki.windowFrame.x"
        static let windowFrameY = "toki.windowFrame.y"
        static let windowFrameW = "toki.windowFrame.w"
        static let windowFrameH = "toki.windowFrame.h"
    }

    /// ウィンドウ透過率（0.5〜1.0）。未設定時は 1.0。
    var opacity: Double {
        get {
            let v = defaults.double(forKey: Key.opacity)
            return v == 0 ? 1.0 : max(0.5, min(1.0, v))
        }
        nonmutating set {
            defaults.set(max(0.5, min(1.0, newValue)), forKey: Key.opacity)
        }
    }

    /// 前回のウィンドウフレーム。x/y/w/h の 4 つのキーに分解して保存。
    /// いずれかが欠落していたら nil（初回起動扱い）。
    var windowFrame: NSRect? {
        guard defaults.object(forKey: Key.windowFrameX) != nil,
              defaults.object(forKey: Key.windowFrameY) != nil,
              defaults.object(forKey: Key.windowFrameW) != nil,
              defaults.object(forKey: Key.windowFrameH) != nil else {
            return nil
        }
        let x = defaults.double(forKey: Key.windowFrameX)
        let y = defaults.double(forKey: Key.windowFrameY)
        let w = defaults.double(forKey: Key.windowFrameW)
        let h = defaults.double(forKey: Key.windowFrameH)
        return NSRect(x: x, y: y, width: w, height: h)
    }

    func setWindowFrame(_ rect: NSRect) {
        defaults.set(rect.origin.x, forKey: Key.windowFrameX)
        defaults.set(rect.origin.y, forKey: Key.windowFrameY)
        defaults.set(rect.size.width, forKey: Key.windowFrameW)
        defaults.set(rect.size.height, forKey: Key.windowFrameH)
    }
}

extension Notification.Name {
    /// 透過率設定が変更されたときに送出される通知。ClockView が購読して opacity 反映。
    static let tokiOpacityChanged = Notification.Name("toki.opacityChanged")
}
```

**完了条件**:
```bash
grep -n "struct AppSettings" Sources/Toki/Infrastructure/AppSettings.swift
# → 1 件

grep -n "static let shared = AppSettings()" Sources/Toki/Infrastructure/AppSettings.swift
# → 1 件

grep -n "tokiOpacityChanged" Sources/Toki/Infrastructure/AppSettings.swift
# → 1 件

swift build && swift test
```

**コミット**: `git commit -m "feat(infra): AppSettings struct を新規追加（UserDefaults wrapper）"`

**依存**: なし

---

## Task 5: ClockViewModel に lastUpdatedAt / isConnecting / handleReload を追加

**Commit**: `feat(composition): ClockViewModel に lastUpdatedAt / isConnecting / handleReload を追加`

**目的**: データ鮮度の可視化と手動再読込の trigger point を ViewModel に追加。

**実装**:

ファイル: `Sources/Toki/Composition/ClockViewModel.swift`（編集）

#### Step 1: @Published 2 つ追加

```swift
@Published private(set) var lastUpdatedAt: Date? = nil
@Published private(set) var isConnecting: Bool = false
```

#### Step 2: handleReload / setConnecting メソッド

```swift
func handleReload() async {
    isConnecting = true
    await gateway?.reload()
    isConnecting = false
}

func setConnecting(_ value: Bool) {
    isConnecting = value
}
```

#### Step 3: lastUpdatedFormatted computed

```swift
/// 最後の reload からの経過時間を人間可読な形式に整形する。
/// 60 秒未満は「最終更新 たった今」、それ以上は「最終更新 X 分前」。
/// lastUpdatedAt が nil（一度も成功 reload してない）の場合は nil。
var lastUpdatedFormatted: String? {
    guard let updated = lastUpdatedAt else { return nil }
    let elapsed = Int(now.timeIntervalSince(updated))
    if elapsed < 60 { return "最終更新 たった今" }
    return "最終更新 \(elapsed / 60) 分前"
}
```

#### Step 4: centerState で「接続中…」を最優先

```swift
var centerState: CenterState {
    let timeStr = Self.formatHHMM(now, calendar: calendar)
    if isConnecting {
        return .freeTime(time: timeStr, subtitle: "接続中…")
    }
    if !accessGranted {
        return .freeTime(time: timeStr, subtitle: "右クリックで接続")
    }
    // 以下既存
}
```

**完了条件**:
```bash
grep -n "@Published private(set) var lastUpdatedAt" Sources/Toki/Composition/ClockViewModel.swift
# → 1 件

grep -n "@Published private(set) var isConnecting" Sources/Toki/Composition/ClockViewModel.swift
# → 1 件

grep -n "func handleReload" Sources/Toki/Composition/ClockViewModel.swift
# → 1 件

grep -n "func setConnecting" Sources/Toki/Composition/ClockViewModel.swift
# → 1 件

grep -n "var lastUpdatedFormatted" Sources/Toki/Composition/ClockViewModel.swift
# → 1 件

grep -n "接続中…" Sources/Toki/Composition/ClockViewModel.swift
# → 1 件

swift build && swift test
```

**コミット**: `git commit -m "feat(composition): ClockViewModel に lastUpdatedAt / isConnecting / handleReload を追加"`

**依存**: なし

---

## Task 6: GoogleCalendarGateway に lastReloadAt publisher 追加、reload 完了時に更新

**Commit**: `feat(infra): GoogleCalendarGateway に lastReloadAt publisher 追加、reload 完了時に更新`

**目的**: reload が成功するたびに ViewModel が `lastUpdatedAt` を同期できるよう Combine publisher を生やす。

**実装**:

#### ファイル 1: `Sources/Toki/Infrastructure/GoogleCalendarGateway.swift`（編集）

```swift
@Published private(set) var lastReloadAt: Date? = nil

func reload() async {
    let timeline = await fetchTodayTimeline()
    isAuthorized = oauthClient.isAuthorized
    lastReloadAt = Date()
    subject.send(timeline)
}
```

#### ファイル 2: `Sources/Toki/Composition/ClockViewModel.swift`（編集）

`start()` 内に sink を追加：

```swift
gateway?.$lastReloadAt
    .receive(on: DispatchQueue.main)
    .sink { [weak self] in self?.lastUpdatedAt = $0 }
    .store(in: &cancellables)
```

**完了条件**:
```bash
grep -n "@Published private(set) var lastReloadAt" Sources/Toki/Infrastructure/GoogleCalendarGateway.swift
# → 1 件

grep -n "lastReloadAt = Date()" Sources/Toki/Infrastructure/GoogleCalendarGateway.swift
# → 1 件

grep -n 'gateway?.\$lastReloadAt' Sources/Toki/Composition/ClockViewModel.swift
# → 1 件

swift build && swift test
```

**コミット**: `git commit -m "feat(infra): GoogleCalendarGateway に lastReloadAt publisher 追加、reload 完了時に更新"`

**依存**: Task 5

---

## Task 7: AppDelegate に「再読込」メニュー + 接続中スピナー連動 + focus reload

**Commit**: `feat(app): AppDelegate に「再読込」メニュー + 接続中スピナー連動 + focus reload`

**目的**: ユーザーが任意のタイミングで reload trigger、OAuth 中の中央表示連動、フォアグラウンド復帰時の自動 reload を実装。

**実装**:

ファイル: `Sources/Toki/App/AppDelegate.swift`（編集）

#### Step 1: 状態プロパティ追加

```swift
private var lastFocusReloadAt: Date?
```

#### Step 2: showContextMenu 拡張

OAuth 接続 / 切断（既存）の直後に「再読込」、separator、「設定…」（**Task 11 で追加するので Task 7 では再読込のみ**）、separator、終了。

```swift
if let oauth = oauthClient, oauth.isAuthorized {
    let reloadItem = NSMenuItem(title: "再読込",
                                action: #selector(handleReload),
                                keyEquivalent: "r")
    reloadItem.isEnabled = true
    menu.addItem(reloadItem)
    menu.addItem(NSMenuItem.separator())
}
```

#### Step 3: handleReload

```swift
@objc private func handleReload() {
    Task { await viewModel?.handleReload() }
}
```

#### Step 4: handleConnect / handleDisconnect 拡張

```swift
@objc private func handleConnect() {
    Task {
        viewModel?.setConnecting(true)
        defer { viewModel?.setConnecting(false) }  // Swift で defer 内 actor call は不可なので明示的に
        do {
            try await oauthClient?.beginAuthorization()
            viewModel?.refreshAuthorizationState()
            await gateway?.reload()
        } catch {
            print("OAuth connect failed: \(error)")
        }
        viewModel?.setConnecting(false)
    }
}
```

実は @MainActor 上の Task なので setConnecting も同じ actor、defer は OK だが明示的に書く方が安全：

```swift
@objc private func handleConnect() {
    Task {
        viewModel?.setConnecting(true)
        do {
            try await oauthClient?.beginAuthorization()
            viewModel?.refreshAuthorizationState()
            await gateway?.reload()
        } catch {
            print("OAuth connect failed: \(error)")
        }
        viewModel?.setConnecting(false)
    }
}
```

#### Step 5: applicationDidFinishLaunching の末尾に focus reload 監視追加

```swift
NotificationCenter.default.addObserver(
    forName: NSApplication.didBecomeActiveNotification,
    object: nil,
    queue: .main
) { [weak self] _ in
    guard let self else { return }
    if let last = self.lastFocusReloadAt,
       Date().timeIntervalSince(last) < 30 {
        return  // 30 秒以内の連発を抑制
    }
    self.lastFocusReloadAt = Date()
    Task { await self.viewModel?.handleReload() }
}
```

**完了条件**:
```bash
grep -n '"再読込"' Sources/Toki/App/AppDelegate.swift
# → 1 件

grep -n "@objc private func handleReload" Sources/Toki/App/AppDelegate.swift
# → 1 件

grep -n "setConnecting(true)" Sources/Toki/App/AppDelegate.swift
# → 1 件以上

grep -n "didBecomeActiveNotification" Sources/Toki/App/AppDelegate.swift
# → 1 件

grep -n "lastFocusReloadAt" Sources/Toki/App/AppDelegate.swift
# → 3 件以上

swift build && swift test && ./scripts/build-app.sh
```

**コミット**: `git commit -m "feat(app): AppDelegate に「再読込」メニュー + 接続中スピナー連動 + focus reload"`

**依存**: Task 5, 6

---

## Task 8: NextEventLine に最終更新時刻を控えめに表示

**Commit**: `feat(ui): NextEventLine に最終更新時刻を控えめに表示`

**目的**: ユーザーが「今のデータが何分前のものか」を一目で把握できるよう、下部の「次の予定」ラインの右端に「最終更新 X 分前」を小さく表示。

**実装**:

#### ファイル 1: `Sources/Toki/UI/NextEventLine.swift`（編集）

```swift
struct NextEventLine: View {
    let state: NextLineState?
    let lastUpdatedText: String?  // 新規

    var body: some View {
        HStack {
            // 既存の state 表示
            if let state {
                // 既存 layout（時刻 + タイトル）
            } else {
                Text("")
            }
            Spacer()
            if let text = lastUpdatedText {
                Text(text)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
    }
}
```

#### ファイル 2: `Sources/Toki/UI/ClockView.swift`（編集）

呼び出し側で `lastUpdatedText` を渡す：

```swift
NextEventLine(state: viewModel.nextLineState,
              lastUpdatedText: viewModel.lastUpdatedFormatted)
    .frame(height: 40)
```

**完了条件**:
```bash
grep -n "lastUpdatedText: String?" Sources/Toki/UI/NextEventLine.swift
# → 1 件

grep -n "lastUpdatedText: viewModel.lastUpdatedFormatted" Sources/Toki/UI/ClockView.swift
# → 1 件

swift build && swift test && ./scripts/build-app.sh
```

**コミット**: `git commit -m "feat(ui): NextEventLine に最終更新時刻を控えめに表示"`

**依存**: Task 5

---

## Task 9: FloatingClockWindow を resizable 化、ClockGeometry を size 比例計算へ

**Commit**: `feat(window): FloatingClockWindow を resizable 化、ClockGeometry を size 比例計算へ`

**目的**: ウィンドウサイズ可変にし、円形時計が動的サイズに追従するよう ClockGeometry / ClockFaceCanvas を比例計算化。

**実装**:

#### ファイル 1: `Sources/Toki/Window/FloatingClockWindow.swift`（編集）

```swift
static func make<Content: View>(contentView: Content) -> FloatingClockWindow {
    let window = FloatingClockWindow(
        contentRect: NSRect(x: 0, y: 0, width: 280, height: 320),
        styleMask: [.borderless, .fullSizeContentView, .resizable],  // .resizable 追加
        backing: .buffered,
        defer: false
    )
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.isMovableByWindowBackground = true
    window.contentMinSize = NSSize(width: 220, height: 260)
    window.contentMaxSize = NSSize(width: 420, height: 500)
    window.contentView = NSHostingView(rootView: contentView)
    return window
}
```

#### ファイル 2: `Sources/Toki/UI/ClockGeometry.swift`（編集）

```swift
static func standard(in size: CGSize) -> ClockGeometry {
    // 比例計算で動的サイズに対応。
    // 280x280 canvas で inner ≈ 84 / outer ≈ 106（既存値とほぼ同等）。
    let dim = min(size.width, size.height)
    return ClockGeometry(
        center: CGPoint(x: size.width / 2, y: size.height / 2),
        innerRadius: dim * 0.30,
        outerRadius: dim * 0.38
    )
}
```

#### ファイル 3: `Sources/Toki/UI/ClockFaceCanvas.swift`（編集）

時刻ラベルと針 offset を比例化：

```swift
private func drawHourMarks(in ctx: inout GraphicsContext, geometry: ClockGeometry) {
    // ...
    let labelRadius = geometry.innerRadius * 0.86  // 0.86 比率で innerRadius の内側
    // ...
}

private func drawHand(in ctx: inout GraphicsContext, geometry: ClockGeometry, angle: Double) {
    // 中央テキストを避けるため、innerRadius の 33% を inner offset として使う
    let handInnerOffset = geometry.innerRadius * 0.33
    // ...
}
```

#### ファイル 4: `Sources/Toki/UI/ClockView.swift`（編集）

`.frame(width: 280, height: 320)` を撤去（ウィンドウサイズに追従）：

```swift
struct ClockView: View {
    @ObservedObject var viewModel: ClockViewModel
    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ZStack {
                    ClockFaceCanvas(...)
                    CurrentEventLabel(state: viewModel.centerState)
                        .allowsHitTesting(false)
                }
                // .frame(width: 280, height: 280) ← 撤去、親に追従

                Divider().frame(height: 0.5)

                NextEventLine(state: viewModel.nextLineState,
                              lastUpdatedText: viewModel.lastUpdatedFormatted)
                    .frame(height: 40)
            }
            // .frame(width: 280, height: 320) ← 撤去
            .background(Color(NSColor.windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
            )

            if let tooltip = viewModel.hoveredTooltip {
                // 既存
            }
        }
        // .frame(width: 280, height: 320) ← 撤去
    }
}
```

注：`tooltipDisplayPosition` の `canvasWidth` / `windowHeight` 定数も動的サイズ対応にする必要があるが、Task 11 で対応（このタスクでは Tooltip 位置計算は触らないで OK、リサイズ時に多少ズレるが致命的ではない）。

**完了条件**:
```bash
grep -n ".resizable" Sources/Toki/Window/FloatingClockWindow.swift
# → 1 件

grep -n "contentMinSize" Sources/Toki/Window/FloatingClockWindow.swift
# → 1 件

grep -n "dim \* 0.30" Sources/Toki/UI/ClockGeometry.swift
# → 1 件

grep -n "innerRadius \* 0.33" Sources/Toki/UI/ClockFaceCanvas.swift
# → 1 件

# ClockView から固定 frame が消えている
grep -c ".frame(width: 280" Sources/Toki/UI/ClockView.swift
# → 0

swift build && swift test && ./scripts/build-app.sh
```

実機目視：起動 → ウィンドウエッジドラッグ → 220x260 〜 420x500 でリサイズ、円弧 / 針 / 中央テキストが破綻しないこと。

**コミット**: `git commit -m "feat(window): FloatingClockWindow を resizable 化、ClockGeometry を size 比例計算へ"`

**依存**: Task 8

---

## Task 10: ウィンドウ位置 / サイズを AppSettings で永続化、起動時に復元 + 画面外クランプ

**Commit**: `feat(app): ウィンドウ位置 / サイズを AppSettings で永続化、起動時に復元 + 画面外クランプ`

**目的**: 起動のたびに位置リセットされる pain を解消。保存フレームが画面外の場合は安全な位置にクランプ。

**実装**:

#### ファイル 1: `Sources/Toki/App/AppDelegate.swift`（編集）

#### Step 1: applicationDidFinishLaunching で復元

ウィンドウ生成後、AppSettings から保存フレームを取得して setFrame：

```swift
// ウィンドウ生成（既存）
let window = FloatingClockWindow.make(contentView: ClockView(viewModel: vm))
self.window = window

// 保存フレームの復元 or デフォルト位置
if let saved = AppSettings.shared.windowFrame,
   Self.isFrameVisible(saved) {
    window.setFrame(saved, display: true)
} else {
    // デフォルト：メインスクリーンの右上 16px
    if let screen = NSScreen.main {
        let frame = NSRect(
            x: screen.visibleFrame.maxX - 280 - 16,
            y: screen.visibleFrame.maxY - 320 - 16,
            width: 280,
            height: 320
        )
        window.setFrame(frame, display: true)
    }
}

window.makeKeyAndOrderFront(nil)
```

#### Step 2: clamp ヘルパ

```swift
/// 保存フレームが現在のスクリーン構成内で表示可能かを判定する。
/// 全 NSScreen の visibleFrame と intersects するなら true。
private static func isFrameVisible(_ frame: NSRect) -> Bool {
    for screen in NSScreen.screens {
        if screen.visibleFrame.intersects(frame) {
            return true
        }
    }
    return false
}
```

#### Step 3: didMoveNotification / didResizeNotification 監視

```swift
NotificationCenter.default.addObserver(
    forName: NSWindow.didMoveNotification,
    object: window,
    queue: .main
) { [weak self] _ in
    guard let w = self?.window else { return }
    AppSettings.shared.setWindowFrame(w.frame)
}

NotificationCenter.default.addObserver(
    forName: NSWindow.didResizeNotification,
    object: window,
    queue: .main
) { [weak self] _ in
    guard let w = self?.window else { return }
    AppSettings.shared.setWindowFrame(w.frame)
}
```

#### Step 4: applicationWillTerminate でも保険保存

```swift
func applicationWillTerminate(_ notification: Notification) {
    if let w = window {
        AppSettings.shared.setWindowFrame(w.frame)
    }
}
```

**完了条件**:
```bash
grep -n "AppSettings.shared.windowFrame" Sources/Toki/App/AppDelegate.swift
# → 1 件以上

grep -n "AppSettings.shared.setWindowFrame" Sources/Toki/App/AppDelegate.swift
# → 2 件以上

grep -n "didMoveNotification" Sources/Toki/App/AppDelegate.swift
# → 1 件

grep -n "didResizeNotification" Sources/Toki/App/AppDelegate.swift
# → 1 件

grep -n "isFrameVisible" Sources/Toki/App/AppDelegate.swift
# → 2 件以上（定義 + 呼び出し）

swift build && swift test && ./scripts/build-app.sh
```

実機目視：起動 → ドラッグで移動 / リサイズ → quit → 再起動 → 前回位置 / サイズで復元。

**コミット**: `git commit -m "feat(app): ウィンドウ位置 / サイズを AppSettings で永続化、起動時に復元 + 画面外クランプ"`

**依存**: Task 4, 9

---

## Task 11: SettingsView 新規 + AppDelegate「設定…」メニュー + ClockView opacity 連動

**Commit**: `feat(ui): SettingsView 新規 + AppDelegate「設定…」メニュー + ClockView opacity 連動`

**目的**: 透過率を調整できる軽量設定 UI を別ウィンドウで提供。

**実装**:

#### ファイル 1: `Sources/Toki/UI/SettingsView.swift`（新規）

```swift
import SwiftUI

/// 透過率調整の軽量設定 UI。別 NSWindow から NSHostingView で表示される。
/// onChange callback で `NotificationCenter` 経由で ClockView に通知。
struct SettingsView: View {
    @State private var opacity: Double = AppSettings.shared.opacity
    var onChange: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("透過率")
                .font(.system(size: 12, weight: .medium))
            Slider(value: $opacity, in: 0.5...1.0)
                .onChange(of: opacity) { _, newValue in
                    AppSettings.shared.opacity = newValue
                    onChange(newValue)
                }
            Text("\(Int(opacity * 100))%")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 260, height: 120)
        .background(Color(NSColor.windowBackgroundColor))  // Task 12 で Liquid Glass / Material に置換
    }
}
```

#### ファイル 2: `Sources/Toki/App/AppDelegate.swift`（編集）

#### Step 1: settingsWindow プロパティ

```swift
private var settingsWindow: NSWindow?
```

#### Step 2: showContextMenu に「設定…」追加（既存「再読込」のあとに）

```swift
let settingsItem = NSMenuItem(title: "設定…",
                              action: #selector(handleOpenSettings),
                              keyEquivalent: ",")
menu.addItem(settingsItem)
menu.addItem(NSMenuItem.separator())
```

#### Step 3: handleOpenSettings

```swift
@objc private func handleOpenSettings() {
    if let w = settingsWindow {
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }
    let view = SettingsView { [weak self] _ in
        NotificationCenter.default.post(name: .tokiOpacityChanged, object: nil)
        _ = self
    }
    let hosting = NSHostingView(rootView: view)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 260, height: 120),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    window.title = "Toki 設定"
    window.contentView = hosting
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    self.settingsWindow = window
}
```

#### ファイル 3: `Sources/Toki/UI/ClockView.swift`（編集）

opacity 状態を保持して反映：

```swift
struct ClockView: View {
    @ObservedObject var viewModel: ClockViewModel
    @State private var opacity: Double = AppSettings.shared.opacity

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 既存 VStack + tooltip overlay
        }
        .opacity(opacity)
        .onReceive(NotificationCenter.default.publisher(for: .tokiOpacityChanged)) { _ in
            opacity = AppSettings.shared.opacity
        }
    }
}
```

**完了条件**:
```bash
grep -n "struct SettingsView" Sources/Toki/UI/SettingsView.swift
# → 1 件

grep -n "Slider(value: \$opacity" Sources/Toki/UI/SettingsView.swift
# → 1 件

grep -n "private var settingsWindow" Sources/Toki/App/AppDelegate.swift
# → 1 件

grep -n '"設定…"' Sources/Toki/App/AppDelegate.swift
# → 1 件

grep -n "handleOpenSettings" Sources/Toki/App/AppDelegate.swift
# → 2 件以上

grep -n "tokiOpacityChanged" Sources/Toki/UI/ClockView.swift
# → 1 件

grep -n ".opacity(opacity)" Sources/Toki/UI/ClockView.swift
# → 1 件

swift build && swift test && ./scripts/build-app.sh
```

実機目視：右クリック →「設定…」→ Slider 動かす → ClockView の透過率変化、再起動後も維持。

**コミット**: `git commit -m "feat(ui): SettingsView 新規 + AppDelegate「設定…」メニュー + ClockView opacity 連動"`

**依存**: Task 4, 10

---

## Task 12: Liquid Glass material を ClockView / EventTooltip / SettingsView に適用

**Commit**: `feat(ui): Liquid Glass material を ClockView / EventTooltip / SettingsView に適用（macOS 26+、25 以下は Material fallback）`

**目的**: macOS 26+ で Liquid Glass の屈折透過を活用し、ウィンドウ背景・ツールチップ・設定パネルの見栄えを刷新。25 以下は `.regularMaterial` で fallback。

**注意**: Liquid Glass の SwiftUI API（`.glassEffect()` 等）の正確な signature は **実機検証が必要**。本タスク実施時に：
1. 最小サンプルでコンパイル / 動作確認
2. API 確定したら 3 箇所に適用
3. **API 確定できない場合は `if #available` 内も `.regularMaterial` のまま留め、Goal 12-14 を spec 009 へ持ち越す**

**実装**:

#### Step 1: ヘルパ View extension（`Sources/Toki/UI/GlassBackground.swift` 新規 or ClockView 内 inline）

```swift
import SwiftUI

extension View {
    /// Liquid Glass 背景を適用する。macOS 26+ では Liquid Glass、未満は .regularMaterial fallback。
    /// material → clipShape → overlay(stroke) の合成順序を保つ。
    @ViewBuilder
    func tokiGlassBackground(cornerRadius: CGFloat = 12) -> some View {
        if #available(macOS 26.0, *) {
            // 実機検証で .glassEffect() 等の API が利用できれば置換。
            // 現時点では .regularMaterial を fallback として適用。
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}
```

**API 確定時の置換例**（参考）：
```swift
if #available(macOS 26.0, *) {
    self.background(.glass, in: RoundedRectangle(cornerRadius: cornerRadius))
    // or .glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius))
}
```

#### Step 2: ClockView の背景を置換

```swift
// 既存
.background(Color(NSColor.windowBackgroundColor))
// 置換後
.tokiGlassBackground(cornerRadius: 12)
```

#### Step 3: EventTooltip の背景を置換

`Sources/Toki/UI/EventTooltip.swift`（編集）：

```swift
// 既存の Color(NSColor.controlBackgroundColor) fill 等を tokiGlassBackground(cornerRadius: 6) に置換
.tokiGlassBackground(cornerRadius: 6)
```

#### Step 4: SettingsView の背景を置換

```swift
// 既存
.background(Color(NSColor.windowBackgroundColor))
// 置換後
.tokiGlassBackground(cornerRadius: 12)
```

**完了条件**:
```bash
grep -n "tokiGlassBackground" Sources/Toki/UI/ClockView.swift
# → 1 件

grep -n "tokiGlassBackground" Sources/Toki/UI/EventTooltip.swift
# → 1 件

grep -n "tokiGlassBackground" Sources/Toki/UI/SettingsView.swift
# → 1 件

grep -rn "if #available(macOS 26" Sources/Toki/
# → 1 件以上

swift build && swift test && ./scripts/build-app.sh
```

実機目視（macOS 26+ なら）：
- ClockView 背景の屈折透過
- ツールチップの glass 効果
- 設定パネルの glass 効果

API 確定できない場合：fallback の `.regularMaterial` でも視覚的に半透明背景になるので機能は損なわない。spec 009 で Liquid Glass のみ再挑戦可能。

**コミット**: `git commit -m "feat(ui): Liquid Glass material を ClockView / EventTooltip / SettingsView に適用"`

**依存**: Task 9, 11

---

## Task 13: SPEC.md を spec 008 完了状態に追従更新

**Commit**: `docs(spec): SPEC.md を spec 008 完了状態に追従更新`

**目的**: spec 008 で実装された項目を SPEC.md に反映、Phase 2 から完了項目を昇格、Phase 3 から実装済み項目を削除。

**実装**:

ファイル: `SPEC.md`（編集）

#### Step 1: §6 Phase 2 から完了項目を削除

以下を Phase 2 から削除（または「完了 spec 008」マーク）：
- 右クリック「再読込」
- ウィンドウ位置 `UserDefaults` 記憶
- 接続中スピナー

#### Step 2: §6 Phase 3 から完了項目を削除

- 「透明度調整（Option + scroll）」は「設定パネルで連続スライダー」に変更されたので Phase 3 から削除（または「完了」マーク）

#### Step 3: §2 / §7 に挙動メモ追記

- §2 ウィンドウサイズが可変になった旨
- §2 右クリック右クリックメニューに「再読込」「設定…」が追加された旨
- §7 ポーリング 120 秒に短縮、focus reload の挙動、busy block fallback の判定ロジック

#### Step 4: §6 Phase 2 / Phase 3 に新規項目を追記（spec 008 §Non-goals 由来）

- Phase 2：（残るもの）isAuthorized 名称分離、print → os_log、ViewModel 二重初期評価コメント化、wake handler コメント化、webURL 値伝播 Domain テスト、ISO8601Formatter キャッシュ、ClockView 定数集約
- Phase 3：（spec 009 候補）in-app event preview、Meet 起動、参加可否操作、complete 設定 UI、複数アカウント、複数日 navigation、calendar 選択 UI 等

**完了条件**:
```bash
grep -n "spec 008" SPEC.md
# → 数件マッチ

grep -n "ポーリング.*120\|120 秒\|2 分" SPEC.md
# → 1 件以上

grep -n "Liquid Glass\|glassEffect" SPEC.md
# → 1 件以上

swift build && swift test
```

**コミット**: `git commit -m "docs(spec): SPEC.md を spec 008 完了状態に追従更新"`

**依存**: Task 12

---

## 全 task 完了後

### 回帰確認

- [ ] `swift test`：Domain 36 ケース全 pass
- [ ] `./scripts/build-app.sh && open .build/Toki.app`：実機目視で spec 008 §AC の項目を walkthrough

### 手動チェックリスト（spec 008 plan §12 ベース）

| # | 項目 | 期待 |
|---|---|---|
| 1 | Google で event 追加 → 2 分以内に反映 | 旧 5 分から短縮 |
| 2 | 右クリック「再読込」 | 即時反映 |
| 3 | 別アプリから Toki クリック | 30 秒以内 skip、それ以降 reload |
| 4 | OAuth「接続」直後 | 「接続中…」表示 |
| 5 | 接続成功後 | 通常表示 + event 反映 |
| 6 | 下部右端 | 「最終更新 X 分前」or「たった今」 |
| 7 | ウィンドウリサイズ | 220x260 〜 420x500 で破綻なし |
| 8 | 「設定…」 | SettingsView 別ウィンドウ表示 |
| 9 | 透過率スライダー | 即時反映 |
| 10 | アプリ再起動 | 位置 / サイズ / 透過率復元 |
| 11 | 外部モニタ抜く | メインスクリーンにクランプ |
| 12 | 共有 event クリック | 今日ビュー fallback |
| 13 | 通常 event クリック | detail へ遷移 |
| 14 | macOS 26+ | Liquid Glass 効果（or Material fallback） |
| 15 | macOS 25 以下 | Material fallback |

### コードレビュー（任意）
`code-reviewer` agent で全体レビュー実行。spec 008 で導入した変更の品質確認。
