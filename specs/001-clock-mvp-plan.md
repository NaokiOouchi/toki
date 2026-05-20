# 001 — 円形時計型カレンダー MVP 技術プラン

`specs/001-clock-mvp.md` を技術プランに展開したもの。`/tasks` で atomic task に分解する元となる。

## 0. 確定済み設計判断（このプランで採用）

ユーザーとの合意事項を先頭に明示する：

1. **ウィンドウ初回表示位置**：メイン画面の右上、画面端から 16px インセット
2. **イベント円弧の左クリック → 純正カレンダー.app**：**MVP に含める**（spec AC の通り）
3. **all-day イベントを「次の予定」ラインに含めるか**：**含めない**（円弧除外と整合）
4. **Info.plist 適用方針**：**最初から `.app` バンドル化する**（`swift run` での実行は補助、EventKit が絡む動作確認は常に `.app` 経由）。SPEC.md §9 の「`.app` バンドル化は MVP では不要」とは異なる方針。SPEC.md 側は MVP 完了時に追記/修正する。

## 1. Requirements restatement

MVP（Phase 1）完了時の達成状態（SPEC.md §6 Phase 1 / spec Goal 参照）：

- メニューバー常駐 + クリックトグルで 280×320px のボーダーレス・常時前面ウィンドウ
- 24 時間アナログ時計（0:00 真上、時計回り、二重リング径 220–260px、4 箇所の時刻マーク、針）
- 今日の EventKit イベントを `EKCalendar.cgColor` の annulus segment として描画（過去/現在/未来で alpha・アウトライン差別化）
- 中央テキスト（現在時刻 / 現イベント or "—" / 残り or 次まで XX 分）
- 下部 1 行で次の予定（無ければ非表示、all-day は除外）
- 1 分ごと自動更新 + `EKEventStoreChanged` 反映
- イベント円弧の左クリックで純正カレンダー.app を開く

## 2. Open Questions — 解決済み

spec の 14 件を解決した結果：

### UX / 体験

1. **EventKit 権限拒否時 UX** → 時計（針 + 時刻 + 中央 "—"）のみ動作。再要求導線なし
2. **初回表示位置** → 右上 16px インセット（確定済み）
3. **空状態 UX** →
   - 今日 0 件：中央 `現在時刻 / — / 予定なし`、下部ライン非表示
   - 権限なし：中央 `現在時刻 / — / 権限が必要`、下部ライン非表示
   - 全カレンダー OFF：0 件と同扱い
4. **ウィンドウのダブルクリック挙動** → 何もしない（ドラッグ移動と競合回避）。右クリックメニューは MVP 範囲外
5. **長いタイトル trim** → `truncationMode(.tail)`（末尾 …）
6. **`EKCalendar.cgColor` コントラスト** → MVP はそのまま。薄色問題は Phase 3 で対処

### 描画ルール

7. **針の z-index** → 円弧の上（最上位）
8. **クリック判定精度** → annulus セグメントの `Path.contains(point)` でヒットテスト。15 分イベントでも OK の見込み、ダメなら Phase 2 で hit-radius 補正
9. **all-day を「次の予定」ラインに含めるか** → 含めない（確定済み）

### 技術・実装

10. **`EKEventStoreChanged` debounce** → 300ms（Combine `.debounce`）
11. **sleep/wake 復帰** → `NSWorkspace.didWakeNotification` 購読 → 即時 reload + タイマー再アライン
12. **`Event.id` recurring 対応** → `"\(eventIdentifier)#\(start.timeIntervalSince1970)"` で合成。`externalIdentifier` には元の `eventIdentifier` を保持
13. **`canBecomeKey` OFF** → `NSWindow` サブクラスで `canBecomeKey` / `canBecomeMain` を false にオーバーライド
14. **針の終端** → 外リング外径（130px）まで

## 3. Module/file plan

CLAUDE.md / SPEC.md §4 のレイアウトに準拠。各ファイル < 400 行目標。

### ルート
- `/Package.swift` — SwiftPM マニフェスト。executable target `Toki` + test target `TokiTests`、macOS 14 platform、Resources copy
- `/Resources/Info.plist` — `LSUIElement=YES`, `NSCalendarsUsageDescription`, `CFBundleIdentifier`, `CFBundleName`, `CFBundleExecutable`, `CFBundleShortVersionString`, `LSMinimumSystemVersion`
- `/scripts/build-app.sh` — `swift build -c release` → `Toki.app/Contents/{MacOS, Info.plist}` を組み立てるシェルスクリプト
- `/README.md` — 既存。MVP 完了時に「`.app` バンドル経由で起動」を追記（このプランの範囲外）

### App/
- `Sources/Toki/App/TokiApp.swift` — `@main` エントリポイント。`NSApplication.shared` を起動し AppDelegate を装着
- `Sources/Toki/App/AppDelegate.swift` — `NSApplicationDelegate` 実装。StatusBar 設定 + Window 生成 + Composition 構築

### Window/
- `Sources/Toki/Window/FloatingClockWindow.swift` — `NSWindow` サブクラス。`canBecomeKey/Main` を false にオーバーライド、ファクトリ関数提供

### Domain/
- `Sources/Toki/Domain/TimeOfDay.swift`
- `Sources/Toki/Domain/Event.swift`
- `Sources/Toki/Domain/EventStatus.swift`
- `Sources/Toki/Domain/DayTimeline.swift`

### Infrastructure/
- `Sources/Toki/Infrastructure/EventKitGateway.swift`

### UI/
- `Sources/Toki/UI/ClockView.swift` — ルート View
- `Sources/Toki/UI/ClockFaceCanvas.swift` — Canvas 本体
- `Sources/Toki/UI/EventArcRenderer.swift` — annulus segment ヘルパ（free function 群）
- `Sources/Toki/UI/CurrentEventLabel.swift` — 中央テキスト
- `Sources/Toki/UI/NextEventLine.swift` — 下部 1 行

### Composition/
- `Sources/Toki/Composition/ClockViewModel.swift`

### Tests/
- `Tests/TokiTests/TimeOfDayTests.swift`
- `Tests/TokiTests/EventTests.swift`
- `Tests/TokiTests/DayTimelineTests.swift`

## 4. Domain layer detail

### `TimeOfDay`
**API**：
- `let hour: Int`, `let minute: Int`
- failable `init?(hour: Int, minute: Int)`：`0..<24` / `0..<60` 外は nil
- `var minutesSinceMidnight: Int`
- `var clockAngle: Double`（SPEC §5 の式）
- `static func now(calendar: Calendar = .current) -> TimeOfDay`
- `static func from(date: Date, calendar: Calendar = .current) -> TimeOfDay`
- `Equatable` / `Comparable` / `Hashable`

**Invariants**：`hour ∈ 0..<24`、`minute ∈ 0..<60`。failable init で担保

**テスト**：
- `clockAngle` at 0:00 → `-π/2`、6:00 → `0`、12:00 → `π/2`、18:00 → `π`
- failable init: `(24, 0)` → nil、`(0, 60)` → nil、`(-1, 0)` → nil
- `Comparable`: `(9, 30) < (10, 0)`

### `Event`
**API**：
- `let id: String, title: String, start: Date, end: Date, calendarColor: CGColor, externalIdentifier: String?`
- failable `init?(id:title:start:end:calendarColor:externalIdentifier:)`：`start < end` でなければ nil、`id` 空 nil
- `Identifiable`, `Equatable`（id ベース比較に限定して `CGColor` 比較の罠を回避）

**Invariants**：`start < end`、`id` 非空。failable init で担保

**テスト**：
- 0 分イベント（start == end）で init nil
- start > end で init nil
- 通常イベントの init 成功

### `EventStatus`
**API**：
- `enum EventStatus { case past, current, future }`
- `extension Event { func status(at now: Date) -> EventStatus }`

**判定ルール**：`end <= now` past、`start > now` future、それ以外 current

**テスト**：
- 境界：`end == now` → past、`start == now` → current

### `DayTimeline`
**API**：
- `let date: Date, events: [Event]`（start 昇順、同 start は end 昇順、init で sort）
- `init(date: Date, events: [Event])`
- `func currentEvent(at now: Date) -> Event?`
- `func nextEvent(after now: Date) -> Event?`
- `static func clip(_ event: Event, toDayOf date: Date, calendar: Calendar) -> Event?`：日跨ぎイベントを今日の 0:00–24:00 にトリム、交差なしは nil
- `static func filterOverlaps(_ events: [Event]) -> [Event]`：start 昇順走査で「earliest start wins」フィルタ
- `static func make(date:rawEvents:allDayFlags:calendar:) -> DayTimeline`：all-day 除外 → clip → filterOverlaps → sort で正規化したファクトリ

**設計判断**：重なり除去・日跨ぎ clip・all-day 除外は **Domain（DayTimeline.make）で前処理**。理由は UI 責務単純化 + テスト容易 + AC 解釈の自然さ。

**Invariants**：`events` は start 昇順、要素は all-day を含まない、各 event は `date` の 0:00–24:00 に収まる

**テスト**：
- `currentEvent`：3 件中の真ん中だけ current、それを返す
- `currentEvent`：current なし → nil
- `nextEvent`：now より start が大きい最初の event を返す
- `nextEvent`：全イベントが過去 → nil
- `clip`：23:30–翌 0:30 の event → 23:30–24:00 にトリム
- `clip`：完全に翌日 → nil
- `filterOverlaps`：9:00–10:00 と 9:30–9:45 → 前者のみ残る
- `filterOverlaps`：完全な入れ子（9:00–11:00 が先、10:00–10:30 が後）→ 前者のみ
- `make`：all-day flag を含む raw → 除外される

## 5. Infrastructure layer detail

### `EventKitGateway`

**インターフェース**（protocol は切らない、必要になってから）：

```swift
enum AccessResult { case granted, denied, error(Error) }

final class EventKitGateway {
    init(calendar: Calendar = .current)
    func requestAccess() async -> AccessResult
    func fetchTodayTimeline() async -> DayTimeline
    var timelineUpdates: AnyPublisher<DayTimeline, Never> { get }
    func start()
    func stop()
}
```

**責務**：
- `EKEventStore` 保持
- `requestFullAccessToEvents()` 呼び出し、結果を `AccessResult` に変換
- 今日の `predicateForEvents(withStart:end:calendars:)` を全カレンダー対象で実行
- `EKEvent → Event` 変換：
  - `id = "\(ekEvent.eventIdentifier ?? UUID().uuidString)#\(ekEvent.startDate.timeIntervalSince1970)"`
  - `externalIdentifier = ekEvent.eventIdentifier`
  - `calendarColor = ekEvent.calendar.cgColor`
  - all-day フラグを `(rawEvent, isAllDay)` として保持
  - 0 分以下や nil タイトルは捨てる（防御的）
- `(rawEvent, isAllDay)` リストを `DayTimeline.make(date:rawEvents:allDayFlags:calendar:)` に渡す
- `NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: store)` を `.debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)` して再 fetch
- 結果を `CurrentValueSubject<DayTimeline, Never>` で保持、`eraseToAnyPublisher()` で公開

**Composition から見たインターフェース**：Combine Publisher 一本に統一。`fetchTodayTimeline()` は初期化用、外部は `timelineUpdates` を購読

**`EKEvent` の Domain 漏れ防止**：Gateway 内のみで触る。public API は `Event` / `DayTimeline` / `AccessResult` のみ

## 6. UI layer detail

### `ClockView.swift`
- ルート View、`@ObservedObject var viewModel: ClockViewModel`
- レイアウト：
  ```
  VStack(spacing: 0) {
      ZStack {
          ClockFaceCanvas(state: viewModel.canvasState, onArcTap: viewModel.handleArcTap)
          CurrentEventLabel(state: viewModel.centerState)
      }
      .frame(width: 280, height: 280)
      Divider().frame(height: 0.5)
      NextEventLine(state: viewModel.nextLineState)
          .frame(height: 40)
  }
  ```
- 背景：`Color(NSColor.windowBackgroundColor)`、角丸 12px、薄ボーダー 0.5px は `.overlay(RoundedRectangle.stroke)` で
- `onArcTap` クロージャ経由でクリック → ViewModel が `NSWorkspace.shared.open(...)` 呼び出し

### `ClockFaceCanvas.swift`
- `Canvas` を `.onTapGesture(coordinateSpace: .local)` でラップ、または `Canvas` 下に `GeometryReader + Color.clear.contentShape(Rectangle()).onTapGesture` でヒットテスト
- 描画順（z-index、下から上）：
  1. 背景円（任意）
  2. 時刻マーク数字（0/6/12/18）
  3. イベント円弧（過去 → 未来の順）
  4. 針（最上位）
- 入力：`CanvasState`（`events: [RenderableEvent]`, `now: Date`, `geometry: ClockGeometry`）
- `ClockGeometry`：内径 110 / 外径 130 / 中心点を保持する struct

### `EventArcRenderer.swift`
- **free function 群**（struct ではない）
- 関数：
  - `func annulusPath(center: CGPoint, innerR: CGFloat, outerR: CGFloat, startAngle: Double, endAngle: Double) -> Path`
  - `func drawEventArc(in context: GraphicsContext, event: RenderableEvent, geometry: ClockGeometry)`
  - `func hitTest(point: CGPoint, events: [RenderableEvent], geometry: ClockGeometry) -> RenderableEvent?`（クリックハンドラ用）

### `CurrentEventLabel.swift`
- VStack に 3 つの Text。state は enum：
  ```swift
  enum CenterState {
      case duringEvent(time: String, title: String, remaining: String)
      case freeTime(time: String, subtitle: String)  // subtitle 例: "次まで 30分" / "予定なし" / "権限が必要"
  }
  ```
- ViewModel が enum を組み立てる、View は表示のみ

### `NextEventLine.swift`
- 独立ファイル（責務分割）
- state：`NextLineState?`（nil なら非表示）
- HStack で「次」（secondary）+ Spacer + 「HH:MM タイトル」（secondary、truncationMode .tail）

## 7. Composition layer

### `ClockViewModel`

**型**：`final class ClockViewModel: ObservableObject`

**`@Published`**：
- `@Published private(set) var now: Date`
- `@Published private(set) var timeline: DayTimeline?`
- `@Published private(set) var accessGranted: Bool`

**派生（computed）**：
- `var canvasState: CanvasState`
- `var centerState: CenterState`
- `var nextLineState: NextLineState?`

**Construction (DI)**：
```swift
init(gateway: EventKitGateway, calendar: Calendar = .current)
```

**ライフサイクル**：
- `start()` で：
  1. `await gateway.requestAccess()` → `accessGranted` 更新
  2. `gateway.start()`
  3. `gateway.timelineUpdates.assign(to: &$timeline)`
  4. 初回 `now = Date()`
  5. 次の `:00` までの差分を `DispatchQueue.main.asyncAfter` で待ち、その後 `Timer.publish(every: 60, on: .main, in: .common).autoconnect()` を購読
  6. `NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)` 購読 → 即時補正

**クリックハンドラ**：
```swift
func handleArcTap(event: RenderableEvent) {
    guard let extID = event.externalIdentifier else { return }
    let url = URL(string: "ical://ekevent/\(extID)?method=show&options=more")!
    NSWorkspace.shared.open(url)
}
```

## 8. App/Window layer

### `TokiApp.swift`
```swift
@main
enum TokiApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
```

### `AppDelegate.swift`
- `applicationDidFinishLaunching`：
  1. `gateway = EventKitGateway()`、`viewModel = ClockViewModel(gateway: gateway)`
  2. `window = FloatingClockWindow.make(contentView: ClockView(viewModel: viewModel))`
  3. 初回表示位置：メインスクリーンの右上 - 16px インセット
     ```swift
     if let screen = NSScreen.main {
         let frame = screen.visibleFrame
         let origin = NSPoint(x: frame.maxX - window.frame.width - 16,
                              y: frame.maxY - window.frame.height - 16)
         window.setFrameOrigin(origin)
     }
     ```
  4. `Task { await viewModel.start() }`
  5. `window.orderFrontRegardless()`
  6. `NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)`、`button.image = NSImage(systemSymbolName: "clock", ...)`、`button.action = #selector(toggleWindow)`
- `toggleWindow()`：`window.isVisible ? window.orderOut(nil) : window.orderFrontRegardless()`

### `FloatingClockWindow.swift`
```swift
final class FloatingClockWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    static func make(contentView: some View) -> FloatingClockWindow {
        let w = FloatingClockWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 320),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.isMovableByWindowBackground = true
        w.contentView = NSHostingView(rootView: contentView)
        return w
    }
}
```

## 9. .app バンドル構築

確定方針：`.app` バンドルを最初から作る。

### `scripts/build-app.sh`
```bash
#!/bin/bash
set -euo pipefail

CONFIG="${1:-debug}"
swift build -c "$CONFIG"

BIN_DIR=".build/$CONFIG"
APP_DIR=".build/Toki.app"
CONTENTS="$APP_DIR/Contents"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

cp "$BIN_DIR/Toki" "$CONTENTS/MacOS/Toki"
cp "Resources/Info.plist" "$CONTENTS/Info.plist"

echo "Built $APP_DIR"
echo "Run: open $APP_DIR"
```

### 実行フロー
- 開発時：`scripts/build-app.sh && open .build/Toki.app`
- 純粋ロジック開発（EventKit 不要部分）：`swift run` でも可だが、権限ダイアログ等は出ない
- テスト：`swift test`（Domain のみ）

### `Package.swift` の resource 設定
`Resources/Info.plist` は SwiftPM の resource として executable target に含めるが、**実体は `.app` バンドル化スクリプトでコピーする**。SwiftPM の resource は `Bundle.module` 経由で参照される形式になり、`.app/Contents/Info.plist` の規約パスに置けないため、スクリプト側で `Resources/Info.plist` から直接コピーする。

## 10. Implementation phase order

CLAUDE.md「1 タスク = 1 commit、Conventional Commits」。scope は `domain / infra / ui / app / window / composition / chore`。

### Phase 1a — SwiftPM init + Domain
1. `chore: SwiftPM プロジェクト初期化（Package.swift, Resources/Info.plist, scripts/build-app.sh）`
2. `feat(domain): TimeOfDay 実装（hour/minute/clockAngle/from(date:)）`
3. `test(domain): TimeOfDayTests`
4. `feat(domain): Event 実装（failable init で start<end）`
5. `test(domain): EventTests`
6. `feat(domain): EventStatus enum + Event.status(at:)`
7. `test(domain): EventStatusTests`
8. `feat(domain): DayTimeline 実装（clip, filterOverlaps, make ファクトリ）`
9. `test(domain): DayTimelineTests`

**検証**：`swift test` がパス

### Phase 1b — Infrastructure
10. `feat(infra): EventKitGateway 雛形（requestAccess + fetchTodayTimeline）`
11. `feat(infra): EKEvent → Event 変換（recurring id 合成、all-day flag 抽出）`
12. `feat(infra): EKEventStoreChanged 購読 + 300ms debounce + timelineUpdates Publisher`

**検証**：簡易な print デバッグで `.app` バンドル経由起動時に今日のイベントが取れることを目視確認

### Phase 1c — Window + AppDelegate（中身は空）
13. `feat(window): FloatingClockWindow（borderless, floating, canBecomeKey=false）`
14. `feat(app): TokiApp + AppDelegate（NSStatusBar アイコン + ウィンドウトグル + 右上初期位置）`

**検証**：`.app` バンドル起動でメニューバーアイコン出現、クリックで空ウィンドウがトグル、Dock に出ない、すべての Space で見える

### Phase 1d — UI（ハードコードデータで描画）
15. `feat(ui): ClockGeometry + ClockFaceCanvas 骨格（背景+時刻マーク+針）`
16. `feat(ui): EventArcRenderer（annulusPath + drawEventArc + hitTest）`
17. `feat(ui): CurrentEventLabel + NextEventLine`
18. `feat(ui): ClockView 統合（ハードコード Event 配列で描画）`

**検証**：時計が描画され、ハードコードイベントが正しい角度・色・alpha で表示。針が現在時刻を指す。

### Phase 1e — Composition で本接続 + クリック
19. `feat(composition): ClockViewModel（@Published, computed states, sleep/wake, minute-aligned timer）`
20. `refactor(app): AppDelegate を ViewModel + Gateway 経由に差し替え、ハードコード除去`
21. `feat(ui): イベント円弧クリック → 純正カレンダー.app（hitTest + NSWorkspace.open）`

**検証**：実機で初回起動 → 権限ダイアログ → 許可で今日のイベント表示。1 分後に針が動く。カレンダー.app でイベント追加 → Toki に反映。スリープ復帰で正しい時刻。イベント円弧クリックでカレンダー.app が該当イベントを開く。

## 11. Risks

| 重大度 | リスク | 緩和策 |
|---|---|---|
| **HIGH** | EventKit 権限が拒否されると今後のテストが回しづらい | 開発機の System Settings → Privacy → Calendars で Toki エントリを削除して再要求できることを最初に確認 |
| **MED** | `.app` バンドル化スクリプトの code signing 周り。未署名でも開発機ローカルでは動くが Gatekeeper に引っかかる可能性 | MVP は ad-hoc 署名なしで進める。問題が出たら `codesign --sign -` で ad-hoc 署名 |
| **MED** | `ical://ekevent/...` URL scheme は非公式、macOS バージョンで動かない可能性 | Phase 1e のクリック実装時に検証。動かなければ `NSWorkspace.shared.open(URL(string: "ical:")!)` で fallback |
| **MED** | Recurring event の id 衝突。`eventIdentifier + startDate` で合成しても、編集後で start が変動する occurrence で id が変わる | MVP では受容（再描画されるだけで実害なし）。テストで `(eventIdentifier, startDate)` ペアの一意性のみ確認 |
| **MED** | `EKCalendar.cgColor` が背景色と近すぎて見えないケース | MVP は対応しない。Phase 3 で luminance 補正 |
| **LOW** | 1 分タイマーの Canvas 再描画コスト | Canvas は immediate-mode、現代 Mac で 280×280 / イベント数十件は無視できる |
| **LOW** | sleep/wake 復帰時のタイマードリフト | `didWakeNotification` 受信時に `now = Date()` 即時補正 + 次の `:00` までの再アライン |
| **LOW** | `canBecomeKey = false` の副作用：Phase 2 の右クリックメニューで問題が出る可能性 | Phase 2 実装時に検証、必要なら `NSMenu.popUp(positioning:at:in:)` |
| **LOW** | `CGColor` の `Equatable` 比較がポインタ比較になり想定外動作 | `Event.Equatable` を `id` ベース限定で実装し回避 |
| **LOW** | `.onTapGesture` の Canvas 内ヒットテストで Path.contains の精度問題 | 必要なら `simultaneousGesture` + 自前の角度・半径計算で再実装 |

## 12. Out of scope confirmation

以下は MVP では作らない（spec Non-goals 再掲）：

- **マウスホバーで中央表示切替** → Phase 2
- **右クリックメニュー（位置リセット / 再読込 / 終了）** → Phase 2
- **ウィンドウ位置記憶（`UserDefaults`）** → Phase 2
- **イベント重なりの 2 段リング** → Phase 3（MVP は earliest start wins で 1 段）
- **透明度調整（Option + scroll）** → Phase 3
- **対象カレンダー選択 UI** → Phase 3
- **LaunchAtLogin** → Phase 3
- **設定 UI 全般** → Phase 3
- **Windows / Linux 対応** → 当面なし
- **UI / Infrastructure の自動テスト** → CLAUDE.md により対象外、手動確認

## 参考ファイル

- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/CLAUDE.md`
- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/SPEC.md`
- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/specs/001-clock-mvp.md`

次のステップ：`/tasks clock-mvp` で `specs/001-clock-mvp-tasks.md` に atomic task 分解。
