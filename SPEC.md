# Toki — macOS 常時前面表示型カレンダーアプリ

円形時計型UIで「今やってる予定 / これからやる予定」を常時画面に表示するmacOSアプリ。
画面の隅に小さく置いて邪魔にならず、視線を移すだけで現状把握できることを狙う。

---

## 1. スコープ

### 作るもの
- 個人利用前提（自分のGoogleカレンダーは iCloud アカウント追加経由で EventKit に統合済み）
- Mac専用（macOS 14 Sonoma 以降）
- 常時前面表示・全Space表示のフローティングウィンドウ

### 作らないもの
- 設定UIの細部（必要なら後付け）
- イベント編集機能（クリックで純正カレンダー.appに飛ばす）
- 共有・マルチユーザー
- Windows対応（将来必要になったらドメイン層の設計を流用して別実装）

---

## 2. UI仕様

### ウィンドウ
- サイズ：280 × 320 px（時計直径 約240px + 上下余白）
- 背景：不透明（システムテーマ追従、白 or 黒）
- 角丸：12px
- 枠線：0.5px の薄いボーダー
- タイトルバーなし、ボーダーレス
- 背景ドラッグで移動可能

### 時計
- 24時間アナログ時計（0:00 が真上、12:00 が真下、時計回り）
- 二重円のリング（内径 220px、外径 260px）が「時間トラック」
- 時刻マーク：0, 6, 12, 18 の4箇所に小さく数字
- 針：中心から外周まで 1.5px の線、現在時刻を指す

### イベント円弧
- 各イベントはリング上の annulus segment（円環の一部）として描画
- 色：`EKCalendar.cgColor` をそのまま使用
- 状態別の見た目：
  - **過去**（end ≤ now）：alpha 0.3、薄く残す
  - **現在**（start ≤ now < end）：alpha 1.0 + 0.75px のアウトライン
  - **未来**（start > now）：alpha 1.0
- 重なり：MVPでは1段のみ。重なったら開始時刻が早い方を優先。Phase 3で2段目リング対応

### 中央テキスト（時計の内側）
予定中：
```
14:30           ← 現在時刻（11px、tertiary）
DeNA 1on1       ← 今の予定（15px、weight 500、primary）
残り 60分        ← 残り時間（11px、tertiary）
```

空き時間中：
```
14:30
—
次まで 30分
```

### 下部「次の予定」ライン
時計の下に1行：
```
次          16:00 ENEOS実装
```
- フォント 11px、secondary色
- 時計と区切る 0.5px ボーダー

### インタラクション
- **マウスオーバー**：イベント円弧の上に来ると、中央表示がそのイベント情報に切り替わる（離すと現在に戻る）
- **左クリック**：そのイベントを純正カレンダー.appで開く
- **右クリック**：コンテキストメニュー（位置リセット / 再読込 / 終了）
- **メニューバーアイコン**：クリックで時計の表示／非表示トグル

---

## 3. 技術スタック

- Swift 5.9+
- macOS 14+ (Sonoma)
- SwiftPM（シングルパッケージ、ターゲット1つ）
- AppKit（`NSApplication`, `NSWindow`, `NSStatusBar`）
- SwiftUI（描画、状態管理）
- EventKit（カレンダーデータ）
- Combine（時刻・イベント変更のストリーム）

---

## 4. アーキテクチャ

DDD的にレイヤーを薄く切る。自分用だが「ドメイン層を別実装に持っていける」状態は保つ。

```
Toki/
├── Package.swift
├── Sources/Toki/
│   ├── App/
│   │   ├── TokiApp.swift                # @main entry
│   │   └── AppDelegate.swift            # メニューバー、ウィンドウライフサイクル
│   ├── Window/
│   │   └── FloatingClockWindow.swift    # NSWindow 設定
│   ├── UI/
│   │   ├── ClockView.swift              # ルートView
│   │   ├── ClockFaceCanvas.swift        # SwiftUI Canvas 描画
│   │   ├── EventArcRenderer.swift       # 円弧描画ロジック
│   │   └── CurrentEventLabel.swift      # 中央テキスト
│   ├── Domain/
│   │   ├── TimeOfDay.swift              # 0:00-24:00 を扱う VO
│   │   ├── Event.swift                  # value object
│   │   ├── EventStatus.swift            # past/current/future
│   │   └── DayTimeline.swift            # 今日のイベント集約
│   ├── Infrastructure/
│   │   └── EventKitGateway.swift        # EventKit wrapper
│   └── Composition/
│       └── ClockViewModel.swift         # Domain ↔ UI のブリッジ
├── Resources/
│   └── Info.plist                       # LSUIElement=YES
└── Tests/TokiTests/
    ├── TimeOfDayTests.swift
    └── DayTimelineTests.swift
```

### レイヤー責務
| Layer | 責務 | 依存先 |
|---|---|---|
| Domain | 時間／イベント／状態の純粋ロジック | なし（Foundation のみ） |
| Infrastructure | EventKit との通信、Domain型への変換 | EventKit, Domain |
| UI | SwiftUI Views、表示状態 | SwiftUI, Domain |
| App / Window | 起動、ウィンドウ、メニューバー | AppKit, UI, Composition |
| Composition | 依存を組み立てる、ViewModel | 全部 |

---

## 5. ドメインモデル

### `TimeOfDay`
```swift
struct TimeOfDay: Equatable, Comparable {
    let hour: Int    // 0..<24
    let minute: Int  // 0..<60

    var minutesSinceMidnight: Int { hour * 60 + minute }

    /// 24時間時計上の角度（ラジアン）。0:00 が上 (-π/2)、時計回り
    var clockAngle: Double {
        let fraction = Double(minutesSinceMidnight) / (24 * 60)
        return fraction * 2 * .pi - .pi / 2
    }

    static func now(calendar: Calendar = .current) -> TimeOfDay {
        let comps = calendar.dateComponents([.hour, .minute], from: Date())
        return TimeOfDay(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
    }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}
```

### `Event`
```swift
struct Event: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let calendarColor: CGColor
    let externalIdentifier: String?  // EventKit identifier、クリックで開く用
}
```

### `EventStatus`
```swift
enum EventStatus { case past, current, future }

extension Event {
    func status(at now: Date) -> EventStatus {
        if end <= now { return .past }
        if start > now { return .future }
        return .current
    }
}
```

### `DayTimeline`
```swift
struct DayTimeline {
    let date: Date
    let events: [Event]  // start 昇順

    func currentEvent(at now: Date) -> Event? {
        events.first { $0.status(at: now) == .current }
    }

    func nextEvent(after now: Date) -> Event? {
        events.first { $0.start > now }
    }
}
```

---

## 6. 実装フェーズ

### Phase 1 — MVP（最初のゴール）
これだけ作って動かす。

1. SwiftPM プロジェクト初期化（`swift package init --type executable`）
2. `Info.plist` で `LSUIElement=YES`、`NSCalendarsUsageDescription` 設定
3. `AppDelegate` でメニューバーアイコン表示（`NSStatusBar`）
4. `FloatingClockWindow` でボーダーレス・常時前面ウィンドウを作る
5. `EventKitGateway` で権限要求 → 今日のイベント取得 → Domain型に変換
6. `ClockFaceCanvas` で円形時計 + イベント円弧 + 針 + 中央テキスト描画
7. `Timer.publish(every: 60)` で1分ごとに針更新
8. `EKEventStoreChanged` 通知でイベント再取得

### Phase 2 — インタラクション
- マウスホバーでイベント円弧 → 中央表示切替
- クリックで純正カレンダーに飛ぶ
- 右クリックメニュー
- ウィンドウ位置を `UserDefaults` に記憶

### Phase 3 — 仕上げ
- 重なりイベントの2段リング
- 透明度調整（Option + scroll）
- メニューバーから対象カレンダー選択
- 起動時自動オン（LaunchAtLogin）

---

## 7. 実装メモ・落とし穴

### Info.plist 必須項目
```xml
<key>LSUIElement</key>
<true/>
<key>NSCalendarsUsageDescription</key>
<string>カレンダーの予定を時計上に表示するために使用します</string>
```

### EventKit 権限要求（macOS 14+）
```swift
let store = EKEventStore()
// requestAccess(to:) は deprecated、これを使う
try await store.requestFullAccessToEvents()
```

### Floating Window セットアップ
```swift
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 280, height: 320),
    styleMask: [.borderless, .fullSizeContentView],
    backing: .buffered,
    defer: false
)
window.level = .floating
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
window.isOpaque = false
window.backgroundColor = .clear
window.hasShadow = true
window.isMovableByWindowBackground = true
window.contentView = NSHostingView(rootView: ClockView())
```

`canJoinAllSpaces` だけだと Mission Control 切替で消えるので、`stationary` も必須。

### SwiftUI Canvas で annulus segment
```swift
Canvas { ctx, size in
    let center = CGPoint(x: size.width / 2, y: size.height / 2)
    let outerR: CGFloat = 130
    let innerR: CGFloat = 110

    for event in events {
        let startAngle = TimeOfDay(from: event.start).clockAngle
        let endAngle = TimeOfDay(from: event.end).clockAngle

        var path = Path()
        path.addArc(center: center, radius: outerR,
                    startAngle: .radians(startAngle), endAngle: .radians(endAngle),
                    clockwise: false)
        path.addArc(center: center, radius: innerR,
                    startAngle: .radians(endAngle), endAngle: .radians(startAngle),
                    clockwise: true)
        path.closeSubpath()

        let opacity: Double = event.status == .past ? 0.3 : 1.0
        ctx.fill(path, with: .color(Color(cgColor: event.calendarColor).opacity(opacity)))

        if event.status == .current {
            ctx.stroke(path, with: .color(Color(cgColor: event.calendarColor).opacity(0.8)),
                       lineWidth: 0.75)
        }
    }
}
```

### 1分タイマーの精度
`Timer.publish(every: 60)` で十分（秒針はないので秒精度不要）。
ただし起動直後は次の `:00` までの差分を待ってから60秒間隔開始すると針がカクつかない。

```swift
let secondsToNextMinute = 60 - Calendar.current.component(.second, from: Date())
DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(secondsToNextMinute)) {
    self.startMinuteTimer()
}
```

### EventKit の変更購読
```swift
NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: store)
    .sink { [weak self] _ in self?.reloadEvents() }
    .store(in: &cancellables)
```

### 純正カレンダー.app を特定イベントで開く
```swift
let url = URL(string: "ical://ekevent/\(event.externalIdentifier)?method=show&options=more")!
NSWorkspace.shared.open(url)
```
（この URL scheme は非公式だが安定して動く。動かなければ単に `NSWorkspace.shared.open(URL(string: "ical:")!)` で起動だけする）

---

## 8. テスト方針

自分用なので最小限。`Domain/` だけ XCTest で抑える。

```swift
// TimeOfDayTests.swift
func testClockAngleAtMidnight() {
    XCTAssertEqual(TimeOfDay(hour: 0, minute: 0).clockAngle, -.pi / 2, accuracy: 0.0001)
}
func testClockAngleAt6am() {
    XCTAssertEqual(TimeOfDay(hour: 6, minute: 0).clockAngle, 0, accuracy: 0.0001)
}
func testClockAngleAtNoon() {
    XCTAssertEqual(TimeOfDay(hour: 12, minute: 0).clockAngle, .pi / 2, accuracy: 0.0001)
}
func testClockAngleAt6pm() {
    XCTAssertEqual(TimeOfDay(hour: 18, minute: 0).clockAngle, .pi, accuracy: 0.0001)
}
```

UI / Infrastructure は手動確認でOK。

---

## 9. ビルド・実行

```bash
swift build
swift run
```

リリースビルド：
```bash
swift build -c release
```

`.app` バンドル化は MVP では不要（`swift run` で十分）。後で `xcodebuild` で Archive するか、手で Contents/Info.plist と実行ファイルを配置。

---

## 10. Claude Code への指示

このSPECに沿って実装してください。進め方の推奨：

1. **Phase 1 を順に作る**：`Package.swift` → `Info.plist` → `Domain/` → `Infrastructure/` → `Window/` → `UI/` → `App/`
2. **ドメインから書く**：純粋ロジックなので最初に書いてテストも入れると後が楽
3. **Canvas描画の動作確認は早めに**：イベントデータをハードコードしてでも早く目視確認する
4. **EventKit 権限がブロッカー**：実機で初回起動 → システム設定でカレンダーアクセス許可、を忘れずに案内
5. **エラーが出たら止まって質問**：自分用アプリなので適当に進めず、設計判断は確認してから

ファイル長くなりすぎたら適宜分割OK。命名は SPEC のものを優先、迷ったら聞いて。
