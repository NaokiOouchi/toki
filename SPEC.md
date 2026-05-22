# Toki — macOS 常時前面表示型カレンダーアプリ

円形時計型UIで「今やってる予定 / これからやる予定」を常時画面に表示するmacOSアプリ。
画面の隅に小さく置いて邪魔にならず、視線を移すだけで現状把握できることを狙う。

---

## 1. スコープ

### 作るもの
- 個人利用前提（自分の Google アカウントに OAuth 2.0 で接続し、Google Calendar API から直接予定を取得する。spec 006 で EventKit を完全撤去）
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
- サイズ：可変（最小 220 × 260 px、最大 420 × 500 px、デフォルト 280 × 320 px、spec 008 で可変化）
- 背景：Liquid Glass material（macOS 26 Tahoe 以降、`.glassEffect()` API）。macOS 14 / 15 では `.regularMaterial` にフォールバック（spec 008）
- 角丸：12px
- 枠線：0.5px の薄いボーダー
- タイトルバーなし、ボーダーレス
- 背景ドラッグで移動可能
- ウィンドウ位置 / サイズは `UserDefaults` に記憶し起動時に復元（spec 008）

### 時計
- 24時間アナログ時計（0:00 が真上、12:00 が真下、時計回り）
- 二重円のリング（内径 200px、外径 240px）が「時間トラック」
- 時刻マーク：0, 6, 12, 18 の4箇所に小さく数字
- 針：中心から外周まで 1.5px の線、現在時刻を指す

### イベント円弧
- 各イベントはリング上の annulus segment（円環の一部）として描画
- 色：Google Calendar API の `colorId` を `calendar/colors` の `event[colorId].background` で解決した `CGColor`（カレンダー固有色 `backgroundColor` を fallback として使用、spec 006）
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
- さらに下部に「最終更新 X 分前」を控えめに表示（11px、tertiary色、spec 008）

### インタラクション
- **マウスオーバー**：イベント円弧の上に来ると、ツールチップで時刻 + タイトルが表示される（中央表示は現状維持、ツールチップ表示は spec 003 で追加）
  - ツールチップ位置はウィンドウ端で自動反転する（spec 004 で追加）
- **左クリック**：そのイベントを Google Calendar で開く（spec 006 以降は常に Google Calendar API 経由で取得した URL を使用）
  - 接続済み event → API から取得した `htmlLink` で event detail を開く
  - 未接続 / `htmlLink` 取得失敗 → `/r/day/YYYY/MM/DD` の今日のビュー fallback
- **右クリック**：コンテキストメニュー（Google Calendar 接続 / 切断、「再読込」、「設定…」、終了など。接続項目は spec 005 で動的追加、「再読込」「設定…」は spec 008 で追加）
- **メニューバーアイコン**：クリックで時計の表示／非表示トグル
- **設定パネル**（spec 008）：右クリック → 「設定…」で透明度（連続スライダー）など UI 調整を可能にする

---

## 3. 技術スタック

- Swift 5.9+
- macOS 14+ (Sonoma)
- SwiftPM（シングルパッケージ、ターゲット1つ）
- AppKit（`NSApplication`, `NSWindow`, `NSStatusBar`）
- SwiftUI（描画、状態管理）
- Liquid Glass material（macOS 26 Tahoe 以降の `.glassEffect()` API、spec 008 で導入。旧 macOS では `.regularMaterial` にフォールバック）
- Google Calendar API（OAuth 2.0 + REST、event 取得。spec 006 で EventKit を完全撤去し API 単独運用へ）
- Security.framework（Keychain で OAuth token を永続化）
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
│   │   ├── GoogleCalendarGateway.swift  # Google Calendar API → Domain Event 変換（spec 006）
│   │   ├── GoogleCalendarAPI.swift      # events.list / calendar.colors REST 呼び出し（spec 006）
│   │   ├── GoogleOAuthClient.swift      # OAuth 認可コードフロー、token refresh（spec 005）
│   │   ├── LoopbackOAuthReceiver.swift  # OAuth Loopback redirect 受信（spec 005）
│   │   ├── KeychainStore.swift          # OAuth token を Keychain に永続化（spec 005）
│   │   └── OAuthConfig.swift            # OAuth 2.0 client 設定（spec 005）
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
| Infrastructure | Google Calendar API との通信、OAuth、Domain型への変換 | Foundation, Security, Domain |
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
    let id: String           // Google Calendar event ID
    let title: String
    let start: Date
    let end: Date
    let calendarColor: CGColor  // colorId 解決済み or カレンダー固有色
    let webURL: URL?         // events.list の htmlLink（spec 006 以降 必須経路）
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
2. `Info.plist` で `LSUIElement=YES` を設定（spec 006 で `NSCalendarsUsageDescription` は不要化）
3. `AppDelegate` でメニューバーアイコン表示（`NSStatusBar`）
4. `FloatingClockWindow` でボーダーレス・常時前面ウィンドウを作る
5. `GoogleOAuthClient` で OAuth 2.0 Loopback フロー → token を Keychain に保存
6. `GoogleCalendarGateway` が `events.list` + `calendar/colors` を呼んで Domain `Event` に変換
7. `ClockFaceCanvas` で円形時計 + イベント円弧 + 針 + 中央テキスト描画
8. `Timer.publish(every: 60)` で1分ごとに針更新
9. token expiry 監視 / 接続状態変化で events を再取得（手動「再読込」は Phase 2、spec 006 §Out of scope）

### Phase 2 — インタラクション・運用品質
すでに完了：
- マウスホバーでイベント円弧 → ツールチップ表示（spec 003 / 004）
- クリックで Google Calendar event detail を開く（spec 005 / 006）
- 右クリック「再読込」：手動で events 再取得（✅ 完了 spec 008）
- ウィンドウ位置 / サイズ `UserDefaults` 記憶：起動時に前回状態を復元（✅ 完了 spec 008）
- 接続中スピナー：OAuth consent → loopback 受領中に進捗を可視化（✅ 完了 spec 008）
- ウィンドウ可変サイズ化（220×260 〜 420×500、✅ 完了 spec 008）
- Liquid Glass material 適用（✅ 完了 spec 008、macOS 26+。旧 OS は `.regularMaterial` fallback）
- 「最終更新 X 分前」下部表示（✅ 完了 spec 008）
- データ鮮度向上：ポーリング 120 秒化 + focus reload（✅ 完了 spec 008）
- 共有 event の busy block fallback 表示（✅ 完了 spec 008）

候補（順不同、必要になったら spec で起こす）：
- **`print` → `os_log` 共通化**：Console.app での絞り込み性向上、log prefix 統一（spec 007 review M1 由来）
- **`ISO8601DateFormatter` キャッシュ**：parseEventDate のたびに new していたのを 1 個に（spec 007 review M3 由来）
- **ClockView 定数集約**：tooltipWidth / canvasWidth 等のハードコードを 1 箇所に（spec 007 review M5 由来）
- **`isAuthorized` 名称分離**：`OAuthClient.isAuthorized`（真実）と `Gateway.isAuthorized`（cache）の同名 shadowing 解消、`lastKnownIsAuthorized` 等に rename（spec 007 review H-007-1 由来）
- **ViewModel 二重初期評価コメント化 or 削除**：`@Published` 初回 emit との重複を明示（spec 007 review M-007-1 由来）
- **wake handler 同期コメント化**：`reload()` async 待ちの保険である意図を明記（spec 007 review M-007-2 由来）
- **`webURL` 値伝播 Domain テスト追加**：`Event` / `DayTimeline.clip` で webURL 保持を確認（spec 007 §Non-goals 由来）
- **ClockView tooltip 位置計算の動的サイズ対応**：spec 008 でウィンドウは可変化したが tooltip オフセットは固定値のまま、リサイズ時に微ズレ

### Phase 3 — 仕上げ・拡張

#### 直近の有力候補（spec 012 / 013 想定）

- **表示するカレンダーを選択**（spec 012 候補）：calendars.list 結果を SettingsView で listing し Toggle で表示 / 非表示。UserDefaults に hidden ID set を保存、Gateway.convert で filter。ユーザーがタスクを Google Calendar の event として管理しているため、「仕事 / 個人 / 共有 calendar」を分離して見たい pain がある（spec 007 §Out of scope → spec 012 候補）

#### 機能拡張（pain 待ち）

- **重なりイベントの 2 段リング**：MVP は 1 段のみ
- **透明度の Option + scroll 操作**：spec 008 で設定パネル経由の連続スライダーは実装済み。scroll ジェスチャは未対応
- **複数日 navigation**：マウスホイール / 横スクロールで前後日に移動
- **in-app event preview のリッチ化**：popover で参加可否操作（accept / decline / tentative）→ `calendar.events` write scope 昇格 + OAuth 再認可が必要（spec 010 §Non-goals）
- **起動時自動オン**：LaunchAtLogin（`SMAppService` API）
- **複数 Google アカウント並列**：MVP は 1 アカウントのみ（spec 005 / 006 §Non-goals 由来）
- **完全な設定 UI**：client_id 入力、同期間隔（spec 005 / 006 §Non-goals 由来。spec 008 で透明度パネル / spec 009 で 11 軸 / spec 012 候補で calendar 選択）
- **永続キャッシュ**：オフライン耐性、起動時即時表示（spec 006 §Non-goals 由来）
- **OAuth client_secret の安全化**：個人利用以外で配布する場合は secret を分離（spec 005 §Open Questions 由来）

#### 見送ったアイデア（再提案防止）

- **TODO リスト統合**：見送り。ユーザーは Google Calendar の event 自体をタスク管理に使っているため、別 TODO ソース（Google Tasks 等）の統合は不要。event = タスクの運用で完結している
- **ポモドーロタイマー**：見送り。「時間管理」は別アプリの責務であり、Toki の「今日のカレンダー視覚化」コアから逸脱する

#### spec 009 由来の構造リファクタ候補（CLAUDE.md「設定 UI は Phase 3」の整理）

実験的に追加した設定 UI 11 軸の構造的負債整理。spec 009 §Out of scope を参照。
**H-1〜H-4 + H-7 + H-8 は spec 011 で完了済み**：

- ✅ **AppSettings の構造分割**（H-1、spec 011 完了）：`Composition/SettingsStore.swift`（永続化）+ `UI/AppearanceTokens.swift`（enum 群）+ `Composition/AppearanceModel.swift`（`@MainActor ObservableObject`）への 3 ファイル分割完了、`AppSettings.swift` は撤廃
- ✅ **AppearanceModel への移行**（H-2、spec 011 完了）：ClockView の `@State` 13 個 + 通知 1 本の手動 broadcast を `@ObservedObject AppearanceModel` で集約、`@Published` の自動 binding で再描画
- ✅ **SettingsView の細分化**（H-3、spec 011 完了）：11 セクションを `UI/Settings/<Topic>Section.swift` 11 ファイルに分割、SettingsView は 292 行 → 32 行のコンテナに縮小
- ✅ **ThemeColor 循環依存解消**（H-4、spec 011 完了）：`.custom` ケースを `.accentColor` フォールバックに変更、resolved 値は `AppearanceModel.resolvedThemeColor` で一意供給
- ✅ **`@MainActor` 付与**（H-7、spec 011 完了）：`SettingsStore` / `AppearanceModel` に明示付与
- ✅ **円の色既定値集約**（H-8、spec 011 完了）：`AppearanceModel.resolvedCircleOutlineColor` でリテラル `.secondary.opacity(0.6)` を集約
- **UserDefaults キー rename**（H-5、spec 012 候補）：`customColor.r` → `customThemeColor.r` 等、命名一貫化 + マイグレーション
- **tokiGlassBackground 拡張**（H-6、spec 012 候補）：material 引数を受け取り、EventTooltip / SettingsView の背景にも `materialStrength` を反映
- **ColorPicker `supportsOpacity` の見直し**（spec 012 / 013 候補）：文字色 / 円の色は alpha 可にする検討
- **設定ウィンドウ高さの screen clamp**（spec 012 / 013 候補）：860pt 固定は 13-inch MBP で画面外にはみ出る

---

## 7. 実装メモ・落とし穴

### Info.plist 必須項目
```xml
<key>LSUIElement</key>
<true/>
```

spec 006 で EventKit を撤去したため `NSCalendarsUsageDescription` は不要。OAuth はユーザー操作で
ブラウザに遷移する形式なので、OS パーミッション dialog は出ない。

### OAuth 2.0 (Loopback IP) フロー（spec 005 / 006）

Google Calendar API を単独で使うため、Installed App 用の Loopback Redirect 認可コードフローを採用。

1. `GoogleOAuthClient` がランダムポートで `LoopbackOAuthReceiver` を立てる
2. `https://accounts.google.com/o/oauth2/v2/auth` をブラウザで開く（scope: `calendar.events.readonly` + `calendar.readonly`）
3. ユーザーが認可するとローカルポートに `code` が返ってくる
4. `oauth2.googleapis.com/token` で `code` を access / refresh token に交換し、`KeychainStore` に保存
5. 以降は `events.list`、`calendar/colors` を access token で叩く。401 時は refresh token で再取得

setup 3 ステップ（README 連携想定）：

1. Google Cloud Console で OAuth client（Desktop / Installed App）を作成
2. `OAuthConfig` に client ID / client secret を埋め込み（個人利用前提、Phase 3 で安全化検討）
3. 初回起動時に右クリック → 「Google Calendar を接続」でブラウザを開き、認可

### Floating Window セットアップ
```swift
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 280, height: 320),
    styleMask: [.borderless, .fullSizeContentView, .resizable],
    backing: .buffered,
    defer: false
)
window.level = .floating
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
window.isOpaque = false
window.backgroundColor = .clear
window.hasShadow = true
window.isMovableByWindowBackground = true
window.minSize = NSSize(width: 220, height: 260)   // spec 008
window.maxSize = NSSize(width: 420, height: 500)   // spec 008
window.contentView = NSHostingView(rootView: ClockView())
```

`canJoinAllSpaces` だけだと Mission Control 切替で消えるので、`stationary` も必須。
spec 008 で `.resizable` を追加しウィンドウサイズを可変化。位置 / サイズは `UserDefaults`
（key: `toki.window.frame`）に保存して起動時に復元する。

### Liquid Glass material（spec 008）

macOS 26 Tahoe で導入された `.glassEffect()` を背景に適用。旧 OS では半透明感が損なわれるため
`if #available(macOS 26, *)` で分岐し、それ以前は `.regularMaterial` にフォールバックする。

```swift
if #available(macOS 26, *) {
    contentView.background(.glassEffect())
} else {
    contentView.background(.regularMaterial)
}
```

### SwiftUI Canvas で annulus segment
```swift
Canvas { ctx, size in
    let center = CGPoint(x: size.width / 2, y: size.height / 2)
    let outerR: CGFloat = 120
    let innerR: CGFloat = 100

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

### イベント変更購読（spec 006 / 008 以降）

EventKit の `EKEventStoreChanged` は撤去された。spec 008 では以下のトリガで再取得する：

- 定期ポーリング：120 秒間隔（spec 008 で旧 5 分から短縮、データ鮮度向上）
- 接続状態変化（OAuth connect / disconnect）
- access token の自動 refresh 完了
- ウィンドウ表示トグルなどの明示的なライフサイクル契機
- focus reload：`NSApplication.didBecomeActiveNotification` を購読し、30 秒 debounce で再取得（spec 008）
- 手動「再読込」：右クリックメニューから即時実行（spec 008）

push 通知 / watch API は MVP では使わない（Phase 3 検討）。

### 共有 event の busy block fallback（spec 008）

他カレンダー（同僚など）から共有された event は権限により `summary` が `"予定あり"` や `"Busy"`、
あるいは空文字になることがある。これらを以下で判定し、UI 上は「予定あり」ブロックとして
リング描画する：

- `visibility == "private"` の event
- `summary` が `"予定あり" / "Busy" / ""` のいずれか

タイトルは「予定あり」に置き換え、tooltip / 中央テキストでも同様に表示する。
クリック時の `webURL` 解決は通常 event と同じ。

### イベント円弧クリック時の挙動（spec 003 / 005 / 006）

```swift
// 常に Google Calendar API 経由で取得した webURL を最優先で開く。
// 取得できないケースは今日のビュー fallback。
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
```

`webURL` は `GoogleCalendarGateway` が `events.list` の `htmlLink` をそのまま Domain `Event`
に埋め込む。spec 006 で EventKit を完全に外したため、すべての event が常に Google API 経由で
取得される（fallback ルートはあくまで token 期限切れ・未接続時の今日のビュー URL のみ）。

spec 004 の reverse-engineered eid 経路（`base64("<base_uid> <calendar_email>")`）は
撤去された。Workspace + Exchange ハイブリッド event で eid を組み立てられず
破綻したため、Google 公式 API での `htmlLink` 取得に切り替えた。

今日のビュー URL（fallback、spec 003 から）：
- `https://calendar.google.com/calendar/u/0/r/day/YYYY/MM/DD`

純正カレンダー.app への `ical://` URL scheme 連携は spec 003 で撤去された。
詳細は以下参照：
- `specs/003-hover-tooltip-and-browser.md`（Calendar.app 撤去）
- `specs/004-event-detail-and-tooltip-flip.md`（reverse-engineered eid、後に spec 005 で置換）
- `specs/005-google-calendar-api.md`（Google Calendar API 連携導入）
- `specs/006-google-only.md`（EventKit 完全撤去、Google Calendar API 単独運用）
- `specs/007-*.md`（review / 整理。詳細は specs/ 配下参照）
- `specs/008-visual-polish.md`（データ鮮度向上、可変ウィンドウ、共有 event 対応、Liquid Glass 適用）

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
4. **OAuth 初回接続がブロッカー**：実機で初回起動 → 右クリックメニューから「Google Calendar を接続」→ ブラウザで認可、を忘れずに案内（spec 006）
5. **エラーが出たら止まって質問**：自分用アプリなので適当に進めず、設計判断は確認してから

ファイル長くなりすぎたら適宜分割OK。命名は SPEC のものを優先、迷ったら聞いて。
