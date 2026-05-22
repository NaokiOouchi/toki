# 008 — データ鮮度 + ウィンドウ調整 + Liquid Glass 技術プラン

`specs/008-ux-refresh-and-window.md` を技術プランに展開したもの。`/tasks` で atomic task に分解する元となる。

## 0. 確定済み設計判断

ユーザーとの合意事項：

### データ鮮度
1. **ポーリング 120 秒**（5 分 → 2 分）：個人 API クォータ余裕、`Timer.publish(every: 120)`
2. **手動再読込**：右クリックメニュー「再読込」項目、`gateway.reload()` を await
3. **最終更新表示**：NextEventLine 右端に控えめ表示（`.tertiary` 9pt、「X 分前」、60 秒未満は「たった今」）
4. **focus reload**：`NSApplication.didBecomeActiveNotification` で reload、30 秒 debounce
5. **接続中スピナー**：`ClockViewModel.isConnecting`、CenterState の subtitle で「接続中…」、アニメなし

### ウィンドウ調整
6. **背景透過**：Liquid Glass material（macOS 26+）、25 以下は `.regularMaterial` fallback
7. **ウィンドウサイズ可変**：`styleMask` に `.resizable` 追加、min 220x260 / max 420x500、ClockGeometry を比例計算
8. **透過率調整**：軽量設定 UI（別 NSWindow）、連続スライダー 0.5〜1.0、UserDefaults 永続化
9. **ウィンドウ位置記憶**：`didMoveNotification` / `didResizeNotification` で UserDefaults 保存、起動時に復元、画面外はクランプ

### 共有 event 対応
10. **検出**：`visibility == "private"` OR `summary ∈ ["予定あり", "Busy", ""]`
11. **fallback**：`Event.webURL` を nil 化、既存 `handleArcTap` 経路で今日ビュー
12. **Domain 無変更**：`GoogleAPIEvent` に `visibility: String?` 追加のみ

### Liquid Glass
13. **macOS 26+ で `.glassEffect()` 系**、25 以下は `.regularMaterial` fallback
14. **`LSMinimumSystemVersion` 14.0 維持**、Liquid Glass は条件分岐
15. **Liquid Glass API 確定が遅れる場合は spec 009 持ち越し可**（Material fallback で機能性は確保）

## 1. Requirements restatement

spec 007 後の実用段で顕在化した UX pain（ポーリング 5 分 / 更新状態不可視 / 手動再読込なし / 接続中無反応 / 背景不透過 / サイズ固定 / 位置記憶なし / 共有 event クリックの行き止まり）を一気に解消し、macOS 26 の Liquid Glass を視覚レイヤーに導入。**Domain 層は無変更**、Infrastructure / Composition / UI / App の 4 層のみ触る。既存 Domain テスト 36 ケースは無変更で全 pass。

## 2. Open Questions — 解決済み

spec 008 の 13 項目すべて [CONFIDENT]（Q13 のみ実装フェーズで実機検証）：

| # | 論点 | 判断 |
|---|---|---|
| 1 | ポーリング間隔 | 120 秒（2 分） |
| 2 | focus reload debounce | 30 秒 |
| 3 | 最終更新表示位置 | NextEventLine 右端 |
| 4 | 接続中表現 | CenterState subtitle「接続中…」 |
| 5 | ウィンドウサイズ可変方法 | `.resizable` 標準ハンドラ |
| 6 | 透過率の形式 | 連続スライダー（0.5〜1.0） |
| 7 | 設定パネル形式 | 別 NSWindow |
| 8 | 位置記憶の保存タイミング | `didMoveNotification` / `didResizeNotification` |
| 9 | busy block 判定 | visibility OR summary（両方検査、OR 結合） |
| 10 | busy block の表示 | 表示する、click 時のみ fallback |
| 11 | macOS 25 以下 fallback | `.regularMaterial` |
| 12 | `LSMinimumSystemVersion` | 14.0 維持 |
| 13 | Liquid Glass SwiftUI API | Task 12 実機検証、API 不明なら spec 009 持ち越し |

## 3. ファイル別変更計画

| パス | 操作 | 概要 | 想定差分 |
|---|---|---|---|
| `Sources/Toki/Infrastructure/GoogleCalendarGateway.swift` | 編集 | ポーリング 120 秒、`lastReloadAt` publisher、busy block 判定 | +25/-3 |
| `Sources/Toki/Infrastructure/GoogleCalendarAPI.swift` | 編集 | `GoogleAPIEvent.visibility` 追加、`parseEvent` で抽出 | +6/-1 |
| `Sources/Toki/Infrastructure/AppSettings.swift` | 新規 | UserDefaults wrapper（opacity / windowFrame） | +60 |
| `Sources/Toki/Composition/ClockViewModel.swift` | 編集 | `lastUpdatedAt` / `isConnecting`、`handleReload`、`lastUpdatedFormatted`、centerState 拡張 | +50/-5 |
| `Sources/Toki/Window/FloatingClockWindow.swift` | 編集 | `.resizable`、min/max、AppSettings 初期サイズ復元 | +18/-2 |
| `Sources/Toki/App/AppDelegate.swift` | 編集 | 「再読込」「設定…」メニュー、focus reload、位置記憶、SettingsWindow | +120/-10 |
| `Sources/Toki/UI/ClockView.swift` | 編集 | 固定 frame 撤去、Liquid Glass 背景、opacity 連動、tooltip 位置可変対応 | +35/-15 |
| `Sources/Toki/UI/ClockGeometry.swift` | 編集 | `standard(in:)` を比例計算（`min(w,h) * 0.30 / 0.38`） | +5/-3 |
| `Sources/Toki/UI/ClockFaceCanvas.swift` | 編集 | `handInnerOffset` / `labelRadius` を ClockGeometry 比例化 | +4/-3 |
| `Sources/Toki/UI/EventTooltip.swift` | 編集 | 背景を Liquid Glass / Material 分岐 | +12/-3 |
| `Sources/Toki/UI/NextEventLine.swift` | 編集 | `lastUpdatedText: String?` 引数、右端表示 | +10/-2 |
| `Sources/Toki/UI/SettingsView.swift` | 新規 | 透過率スライダー、Liquid Glass 背景 | +75 |

合計：**新規 2 / 編集 9 / 計 11 ファイル**。Domain 配下 0 件。

## 4. データ鮮度カテゴリ詳細

### 4.1 ポーリング 120 秒化
`GoogleCalendarGateway.start()` の `Timer.publish(every: 300)` → `every: 120`、コメント追記。

### 4.2 「再読込」メニュー
`AppDelegate.showContextMenu` に `NSMenuItem(title: "再読込", ..., keyEquivalent: "r")` 追加、接続済みのときのみ enabled、`@objc handleReload()` で `viewModel?.handleReload()` を Task 経由で呼ぶ。

### 4.3 ClockViewModel.lastUpdatedAt / isConnecting
```swift
@Published private(set) var lastUpdatedAt: Date?
@Published private(set) var isConnecting: Bool = false

func handleReload() async {
    isConnecting = true
    await gateway?.reload()
    isConnecting = false
}

func setConnecting(_ value: Bool) {
    isConnecting = value
}

var lastUpdatedFormatted: String? {
    guard let updated = lastUpdatedAt else { return nil }
    let elapsed = Int(now.timeIntervalSince(updated))
    if elapsed < 60 { return "最終更新 たった今" }
    return "最終更新 \(elapsed / 60) 分前"
}
```

### 4.4 GoogleCalendarGateway.lastReloadAt publisher
```swift
@Published private(set) var lastReloadAt: Date?

func reload() async {
    let timeline = await fetchTodayTimeline()
    isAuthorized = oauthClient.isAuthorized
    lastReloadAt = Date()
    subject.send(timeline)
}
```
ViewModel が `gateway.$lastReloadAt` を sink。

### 4.5 NextEventLine に最終更新時刻
引数 `let lastUpdatedText: String?` 追加、HStack の右端に `if let text` で `.tertiary` 9pt 表示。

### 4.6 focus reload + 30 秒 debounce
AppDelegate に `private var lastFocusReloadAt: Date?`、`NSApplication.didBecomeActiveNotification` ハンドラで debounce 判定して `viewModel?.handleReload()` を呼ぶ。`NSWindow.didBecomeKeyNotification` は borderless では発火しないので不要。

### 4.7 接続中スピナー
`handleConnect` 冒頭で `setConnecting(true)`、完了 / 失敗の両分岐で `setConnecting(false)`。`centerState` 分岐の先頭で `isConnecting == true → .freeTime(time:, subtitle: "接続中…")`。

## 5. ウィンドウ調整カテゴリ詳細

### 5.1 FloatingClockWindow resizable
```swift
styleMask: [.borderless, .fullSizeContentView, .resizable]
window.contentMinSize = NSSize(width: 220, height: 260)
window.contentMaxSize = NSSize(width: 420, height: 500)
```
初期サイズは `AppSettings.shared.windowFrame?.size ?? NSSize(width: 280, height: 320)`。

### 5.2 ClockGeometry 比例計算
```swift
static func standard(in size: CGSize) -> ClockGeometry {
    let dim = min(size.width, size.height)
    return ClockGeometry(
        center: CGPoint(x: size.width / 2, y: size.height / 2),
        innerRadius: dim * 0.30,
        outerRadius: dim * 0.38
    )
}
```
280x280 で innerRadius ≈ 84 / outerRadius ≈ 106（既存値とほぼ同じ）。

ClockFaceCanvas 側：
- `labelRadius = innerRadius - 12` → `innerRadius * 0.86`
- `handInnerOffset: 28` → `innerRadius * 0.33`

### 5.3 AppSettings struct
```swift
struct AppSettings {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard
    private enum Key { static let opacity = "toki.opacity"; ... }

    var opacity: Double {
        get {
            let v = defaults.double(forKey: Key.opacity)
            return v == 0 ? 1.0 : max(0.5, min(1.0, v))
        }
        nonmutating set { defaults.set(max(0.5, min(1.0, newValue)), forKey: Key.opacity) }
    }

    var windowFrame: NSRect? { get { ... } }
    func setWindowFrame(_ rect: NSRect) { ... }
}
```
`windowFrame` は x/y/w/h の 4 つの Double キーに分解保存。

### 5.4 ウィンドウ位置 save / restore
- 起動時：`AppSettings.shared.windowFrame` を取得 → `clampToVisibleScreen` で画面内に収まるかチェック → ウィンドウ設定
- 監視：`NSWindow.didMoveNotification` / `NSWindow.didResizeNotification` で `setWindowFrame(window.frame)`
- クランプ：全 `NSScreen.screens.visibleFrame` と全く重ならない場合は `NSScreen.main` の右上にフォールバック

### 5.5 SettingsView + SettingsWindow
新規 `SettingsView.swift`：
```swift
struct SettingsView: View {
    @State private var opacity: Double = AppSettings.shared.opacity
    var onChange: (Double) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("透過率").font(.system(size: 12, weight: .medium))
            Slider(value: $opacity, in: 0.5...1.0)
                .onChange(of: opacity) { _, new in
                    AppSettings.shared.opacity = new
                    onChange(new)
                }
            Text("\(Int(opacity * 100))%")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 260, height: 120)
        .tokiGlassBackground(cornerRadius: 12)
    }
}
```

AppDelegate の `handleOpenSettings()` で別 NSWindow（`[.titled, .closable]`）を NSHostingView 経由で表示。`onChange` から `NotificationCenter.default.post(name: .tokiOpacityChanged)` を発火。

### 5.6 ClockView opacity 連動
`@State private var opacity: Double = AppSettings.shared.opacity`、`.onReceive(NotificationCenter.default.publisher(for: .tokiOpacityChanged)) { _ in opacity = AppSettings.shared.opacity }`、`.opacity(opacity)` を ZStack 全体に適用。

## 6. 共有 event 対応詳細

### 6.1 GoogleAPIEvent に visibility
```swift
struct GoogleAPIEvent {
    // 既存
    let visibility: String?  // 追加
}
```

### 6.2 parseEvent で抽出
`item["visibility"] as? String` を構造体に渡す。

### 6.3 convert で busy block 判定
```swift
private static func convert(_ ge: GoogleAPIEvent) -> (Event, Bool)? {
    // 既存処理
    let busyTitles: Set<String> = ["予定あり", "Busy", ""]
    let trimmedSummary = ge.summary.trimmingCharacters(in: .whitespacesAndNewlines)
    let isBusyBlock = (ge.visibility == "private") || busyTitles.contains(trimmedSummary)
    let effectiveWebURL = isBusyBlock ? nil : ge.htmlLink
    guard let event = Event(id: id, title: ge.summary,
                            start: start, end: end,
                            calendarColor: ge.calendarColor,
                            webURL: effectiveWebURL) else { return nil }
    return (event, isAllDay)
}
```

Domain 無変更（`webURL: URL?` 既存）。

## 7. Liquid Glass 適用詳細

### 7.1 ヘルパ（ClockView or UI/GlassBackground.swift 内）
```swift
extension View {
    @ViewBuilder
    func tokiGlassBackground(cornerRadius: CGFloat = 12) -> some View {
        if #available(macOS 26.0, *) {
            // Task 12 で実機検証、API 確定後に正確な signature
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                // .glassEffect(...) などを実機確認後に追加
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}
```

### 7.2 適用箇所
- `ClockView.body`：`Color(NSColor.windowBackgroundColor)` → `tokiGlassBackground(cornerRadius: 12)`
- `EventTooltip`：fill 背景 → `tokiGlassBackground(cornerRadius: 6)`
- `SettingsView`：背景 → `tokiGlassBackground(cornerRadius: 12)`

### 7.3 FloatingClockWindow との整合
`isOpaque = false` / `backgroundColor = .clear` を維持、`clipShape` も維持。`background → clipShape → overlay(stroke)` の順序厳守（material → clip → stroke）。

## 8. ClockViewModel 詳細

新規 @Published：
- `lastUpdatedAt: Date?`
- `isConnecting: Bool`

新規メソッド：
- `handleReload() async`
- `setConnecting(_ value: Bool)`

新規 computed：
- `lastUpdatedFormatted: String?`

centerState 分岐順序（上から優先）：
1. `isConnecting == true` → 「接続中…」
2. `accessGranted == false` → 「右クリックで接続」
3. `timeline == nil` → 「読み込み中」
4. currentEvent → `.duringEvent(...)`
5. nextEvent → 「次まで X」
6. なし → 「予定なし」

gateway 購読追加：
```swift
gateway?.$lastReloadAt
    .receive(on: DispatchQueue.main)
    .sink { [weak self] in self?.lastUpdatedAt = $0 }
    .store(in: &cancellables)
```

## 9. AppDelegate 詳細

### showContextMenu 拡張
1. OAuth 接続/切断（既存）
2. **再読込**（接続済みのみ enabled、新規）
3. separator
4. **設定…**（新規）
5. separator
6. Toki を終了（既存）

### handleConnect / handleDisconnect 拡張
- `handleConnect` 冒頭：`viewModel?.setConnecting(true)`
- 完了 / 失敗の両分岐で `setConnecting(false)`

### 通知監視
- `NSApplication.didBecomeActiveNotification` → focus reload（30 秒 debounce）
- `NSWindow.didMoveNotification` / `didResizeNotification` → AppSettings 保存
- `applicationWillTerminate` でも保険として保存

### SettingsWindow
`private var settingsWindow: NSWindow?`、`handleOpenSettings()` で生成 or `makeKeyAndOrderFront`。

## 10. 実装フェーズ順序

**13 タスク**：

1. `feat(infra): GoogleCalendarGateway のポーリング間隔を 120 秒に短縮`
2. `feat(infra): GoogleAPIEvent に visibility を追加、parseEvent で抽出`
3. `feat(infra): busy block 判定で webURL を nil 化（GoogleCalendarGateway.convert）`
4. `feat(infra): AppSettings struct を新規追加（UserDefaults wrapper）`
5. `feat(composition): ClockViewModel に lastUpdatedAt / isConnecting / handleReload を追加`
6. `feat(infra): GoogleCalendarGateway に lastReloadAt publisher 追加、reload 完了時に更新`
7. `feat(app): AppDelegate に「再読込」メニュー + 接続中スピナー連動 + focus reload`
8. `feat(ui): NextEventLine に最終更新時刻を控えめに表示`
9. `feat(window): FloatingClockWindow を resizable 化、ClockGeometry を size 比例計算へ`
10. `feat(app): ウィンドウ位置 / サイズを AppSettings で永続化、起動時に復元 + 画面外クランプ`
11. `feat(ui): SettingsView 新規 + AppDelegate「設定…」メニュー + ClockView opacity 連動`
12. `feat(ui): Liquid Glass material を ClockView / EventTooltip / SettingsView に適用`
13. `docs(spec): SPEC.md を spec 008 完了状態に追従更新`

各タスクは独立 commit、ビルド可能を維持。

## 11. リスク

| # | リスク | 重大度 | 緩和策 |
|---|---|---|---|
| R1 | Liquid Glass API signature 想定違い | **高** | Task 12 独立 commit、API 確定遅延時は `.regularMaterial` のまま degrade、Goal 12-14 を spec 009 へ持ち越し可 |
| R2 | サイズ可変で Canvas 破綻 | 中 | ClockGeometry / handInnerOffset を比例計算、3 サイズで目視確認 |
| R3 | 保存フレームが画面外 | 中 | クランプロジック（全 visibleFrame と重なり判定） |
| R4 | focus reload 連発 | 低 | 30 秒 debounce |
| R5 | busy block 判定誤検知 | 低 | 誤検知してもクリック挙動 degrade のみ |
| R6 | Domain テスト影響 | 0 | Domain 無変更 |
| R7 | AppDelegate 肥大化（142 → 262 行） | 低 | < 400 行、`// MARK: -` で section 分割 |
| R8 | NSWindow.frame の monitor 切替 | 中 | R3 と同じ |
| R9 | ポーリング + focus + 手動で API 過剰 | 低 | 個人クォータの 1.7% 程度 |
| R10 | borderless + resizable 共存 | 中 | macOS 13+ で動作確認済み、実機目視で再確認 |
| R11 | isMovableByWindowBackground と resize の競合 | 低 | NSWindow が自動エッジ判定で共存可 |
| R12 | material + clip + stroke の合成順序 | 低 | 「background → clipShape → overlay(stroke)」順厳守 |

## 12. テスト方針

### 自動
- Domain 36 ケース全 pass 維持（Domain 無変更）
- 各 commit 後 `swift build` + `swift test`

### 手動チェックリスト
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
| 14 | macOS 26+ | Liquid Glass 効果 |
| 15 | macOS 25 以下 | Material fallback |

## 13. Out of scope

spec 008 §Non-goals 再掲：
- in-app event preview → spec 009
- 複数日 navigation → Phase 3
- OAuth scope 追加（書き込み） → 不要
- 完全な設定 UI → Phase 3
- 複数 Google アカウント並列 → Phase 3
- 永続キャッシュ → 範囲外
- EventKit 再導入 → 撤去継続
- macOS 25 以下サポート（Liquid Glass のみ 26 必須）
- ダークモード切替（OS 追従）
- アクセシビリティ拡張 → Phase 3

## 参考ファイル

- `specs/008-ux-refresh-and-window.md`
- `specs/006-google-only-plan.md` / `specs/007-review-cleanup-plan.md`

次のステップ：`/tasks 008-ux-refresh-and-window` で 13 atomic task ファイル化 → fresh subagent で 1 commit ずつ実装。
