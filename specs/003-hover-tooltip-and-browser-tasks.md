# 003 — hover-tooltip-and-browser: Tasks

参照: `specs/003-hover-tooltip-and-browser.md` / `specs/003-hover-tooltip-and-browser-plan.md`

合計: **7 tasks**

実装順序：上から順に。各 task は fresh subagent に渡して 1 commit ずつ。

UI + Composition 層のみ変更。Domain / Infrastructure / Window / App 層は無変更。

---

## Task 1: Calendar.app 統合（ical:// 連携）を撤去

**Commit**: `refactor(composition): ClockViewModel から Calendar.app 統合（ical:// 連携）を撤去`

**目的**: spec 003 で Calendar.app 統合を廃止する方針が確定したため、`ClockViewModel.handleArcTap` 内の `ical://` URL 構築と `occurrenceURLDateString` ヘルパーを削除。クリック時の挙動は次タスクまでは「何もしない」スケルトンとする。

**コンテキスト**:
- 参照: spec 003 §Why、plan §6
- 前提: Google 繰り返しイベントの `_R<date>` suffix で URL scheme / AppleScript ともに正しい occurrence を開けないことが実機検証で判明（spec 003 §Why 詳述）
- 現状 `ClockViewModel.handleArcTap` は `ical://ekevent/<id>/<dateStr>?method=show&options=more` 形式の URL を構築して `NSWorkspace.open` する。失敗時は `ical:` フォールバック
- `occurrenceURLDateString(_:)` は `yyyyMMdd'T'HHmmss'Z'` UTC 形式の文字列を返すヘルパー

**実装内容**:
- ファイル: `Sources/Toki/Composition/ClockViewModel.swift`（編集）
- 削除：
  - `handleArcTap` 内の `extID` ガード
  - `dateStr` 組み立て
  - `ical://ekevent/...` URL 文字列
  - `URL(string:)` ガード
  - `NSWorkspace.shared.open(url)` 呼び出し
  - `ical:` フォールバック
  - `occurrenceURLDateString(_:)` メソッド全体
- 残す：`handleArcTap` シグネチャと冒頭の `hitTest` ガード
- 暫定コメント：「`// TODO(spec 003): ブラウザで Google Calendar を開く処理を Task 6 で実装`」を入れる

期待される最終形：

```swift
/// イベント円弧のクリックを処理する。
/// Calendar.app 統合は spec 003 で撤去済み。
/// Google Calendar 今日ビューをブラウザで開く処理は Task 6 で実装する。
func handleArcTap(at point: CGPoint, geometry: ClockGeometry) {
    guard hitTest(point: point, events: canvasEvents, geometry: geometry) != nil else { return }
    // TODO(spec 003 Task 6): Google Calendar 今日ビューをブラウザで開く
}
```

**完了条件**:
- [ ] `swift build` 成功
- [ ] `swift test` で既存 36 ケース全 pass
- [ ] `grep -nE "ical://|occurrenceURLDateString" Sources/Toki/Composition/ClockViewModel.swift` が **何もマッチしない**
- [ ] クリックしても Calendar.app が起動しない（手動確認は Task 5 まとめて）
- [ ] `./scripts/build-app.sh` 成功で `.build/Toki.app` 再生成

**コミット**:
```bash
git add Sources/Toki/Composition/ClockViewModel.swift
git status
git commit -m "refactor(composition): ClockViewModel から Calendar.app 統合（ical:// 連携）を撤去"
```

**依存**: なし

---

## Task 2: TooltipState と EventTooltip View を新規作成

**Commit**: `feat(ui): TooltipState と EventTooltip View を新規作成`

**目的**: ホバー時に表示するツールチップの UI 層 Value Object と SwiftUI View を新規作成する。本タスクでは ClockView / ViewModel との結線はしない（次タスク以降）。

**コンテキスト**:
- 参照: spec 003 §AC「ツールチップ表示内容」、plan §5
- 前提: presentation-only な dumb View を目指す。時刻整形やヒットテストは ViewModel 側の責務
- スタイル：角丸 6pt + `Color(NSColor.controlBackgroundColor)` + 0.5pt secondary 枠線 + 薄影。フォント 11pt（時刻）+ 12pt medium（タイトル）

**実装内容**:

### ファイル 1: `Sources/Toki/UI/TooltipState.swift`（新規）

```swift
import CoreGraphics
import Foundation

/// UI 層 Value Object。ホバー中のイベントから組み立てる表示状態。
/// Equatable 準拠により @Published の同値時 no-op を可能にする（チラつき防止）。
struct TooltipState: Equatable {
    let startEndLabel: String   // "HH:MM - HH:MM"
    let title: String
    let position: CGPoint       // Canvas ローカル座標、ツールチップ左上の基準点
}
```

### ファイル 2: `Sources/Toki/UI/EventTooltip.swift`（新規）

```swift
import SwiftUI

/// ホバー中のイベント詳細を 2 行で表示する小さなオーバーレイ。
/// 純粋な presentation View（時刻整形やヒットテストは ViewModel 側）。
struct EventTooltip: View {
    let timeLabel: String   // "14:00 - 15:00"
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(timeLabel)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 200, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
    }
}
```

**完了条件**:
- [ ] `swift build` 成功（未参照 warning は次タスクで解消、本タスクでは許容）
- [ ] `swift test` で既存 36 ケース全 pass
- [ ] 新規 2 ファイル `Sources/Toki/UI/TooltipState.swift` と `Sources/Toki/UI/EventTooltip.swift` が存在
- [ ] UI 層は SwiftUI / Foundation / CoreGraphics のみに依存（EventKit 直接参照なし）

**コミット**:
```bash
git add Sources/Toki/UI/TooltipState.swift Sources/Toki/UI/EventTooltip.swift
git status
git commit -m "feat(ui): TooltipState と EventTooltip View を新規作成"
```

**依存**: なし（Task 1 と並列可）

---

## Task 3: RenderableEvent に end: Date を追加

**Commit**: `feat(ui): RenderableEvent に end: Date を追加`

**目的**: ツールチップで `HH:MM - HH:MM` の時刻範囲を表示するため、`RenderableEvent` に `end: Date` を追加する。`start: Date` と同じ責務でフラットに保持する。

**コンテキスト**:
- 参照: plan §4「event.end をどう取るか」
- 前提: 現状 `RenderableEvent` は `start: Date` のみ保持。`end` を取るために lookup マップを作るより、Value Object に直接追加する方が再描画コストが少なく責務もシンプル
- `ClockViewModel.canvasEvents` で組み立てる際、`Event` から `ev.end` を渡すだけ

**実装内容**:

### ファイル 1: `Sources/Toki/UI/RenderableEvent.swift`（編集）

```swift
import Foundation
import CoreGraphics

/// UI 描画用のイベント表示モデル。
/// ViewModel が Domain Event から角度に変換してこの型を組み立てる。
struct RenderableEvent: Identifiable {
    let id: String
    let title: String
    let startAngle: Double  // ラジアン、TimeOfDay.clockAngle と同じ規約
    let endAngle: Double
    let color: CGColor
    let status: EventStatus
    let externalIdentifier: String?
    /// イベントの開始時刻。繰り返しイベントを開く URL scheme で
    /// 発生日を指定するために保持する。
    let start: Date
    /// イベントの終了時刻。ツールチップで時刻範囲を表示するために保持する。
    let end: Date
}
```

### ファイル 2: `Sources/Toki/Composition/ClockViewModel.swift`（編集）

`canvasEvents` の `RenderableEvent` 組み立て箇所に `end: ev.end` を追加：

```swift
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
            end: ev.end  // ← 追加
        )
    }
}
```

**完了条件**:
- [ ] `swift build` 成功
- [ ] `swift test` で既存 36 ケース全 pass
- [ ] `grep -n "let end: Date" Sources/Toki/UI/RenderableEvent.swift` が 1 件マッチ
- [ ] `grep -n "end: ev.end" Sources/Toki/Composition/ClockViewModel.swift` が 1 件マッチ

**コミット**:
```bash
git add Sources/Toki/UI/RenderableEvent.swift Sources/Toki/Composition/ClockViewModel.swift
git status
git commit -m "feat(ui): RenderableEvent に end: Date を追加"
```

**依存**: なし（Task 1, 2 と並列可）

---

## Task 4: ClockViewModel に hover state と handleHover を追加

**Commit**: `feat(composition): ClockViewModel に hover state と handleHover を追加`

**目的**: ホバー中のイベント情報を保持する `@Published hoveredTooltip: TooltipState?` と、`SwiftUI.HoverPhase` を受けて状態を更新する `handleHover` メソッドを追加。`Equatable` 比較で連続発火時の再描画コストを抑制する。

**コンテキスト**:
- 参照: plan §4「ホバー検出の詳細」、plan §7
- 前提: Task 2 で `TooltipState` 作成済み、Task 3 で `RenderableEvent.end` 追加済み
- `HoverPhase` は SwiftUI 標準 enum（`.active(CGPoint)` / `.ended`）
- ClockView との結線は次タスク（Task 5）

**実装内容**:

ファイル: `Sources/Toki/Composition/ClockViewModel.swift`（編集）

### プロパティ追加

`@Published private(set) var accessGranted: Bool = false` の下に：

```swift
/// ホバー中のイベントから組み立てるツールチップ状態。
/// nil の場合はツールチップを表示しない。
@Published private(set) var hoveredTooltip: TooltipState? = nil
```

### メソッド追加

`// MARK: - クリックハンドラ` セクションの直前に新セクションを追加：

```swift
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
```

### ヘルパー追加

`private static func formatHHMM(_:calendar:) -> String` の直下に：

```swift
/// "HH:MM - HH:MM" 形式の時刻範囲文字列。既存 `formatHHMM` を再利用する。
private static func formatTimeRange(_ start: Date, _ end: Date, calendar: Calendar) -> String {
    "\(formatHHMM(start, calendar: calendar)) - \(formatHHMM(end, calendar: calendar))"
}
```

### Import 追加

`HoverPhase` は SwiftUI 標準なので、`import SwiftUI` を ClockViewModel の先頭に追加する必要がある（spec 002 後の code review で削除した import を、本機能のために再追加）：

```swift
import Foundation
import AppKit
import Combine
import CoreGraphics
import SwiftUI  // ← 追加：HoverPhase 利用のため
```

**完了条件**:
- [ ] `swift build` 成功
- [ ] `swift test` で既存 36 ケース全 pass
- [ ] `grep -n "@Published private(set) var hoveredTooltip" Sources/Toki/Composition/ClockViewModel.swift` が 1 件マッチ
- [ ] `grep -n "func handleHover" Sources/Toki/Composition/ClockViewModel.swift` が 1 件マッチ
- [ ] `grep -n "import SwiftUI" Sources/Toki/Composition/ClockViewModel.swift` が 1 件マッチ

**コミット**:
```bash
git add Sources/Toki/Composition/ClockViewModel.swift
git status
git commit -m "feat(composition): ClockViewModel に hover state と handleHover を追加"
```

**依存**: Task 2, Task 3

---

## Task 5: ClockFaceCanvas に .onContinuousHover を追加し ClockView でツールチップを表示

**Commit**: `feat(ui): ClockFaceCanvas に .onContinuousHover を追加し ClockView でツールチップを表示`

**目的**: ホバー検出を SwiftUI `.onContinuousHover(coordinateSpace: .local)` で行い、ViewModel の `handleHover` に委譲する。ClockView 最外側を ZStack に切り替え、`EventTooltip` を最前面にオーバーレイ表示する。

**コンテキスト**:
- 参照: plan §4「.onContinuousHover の使い方」、plan §8「ClockView の更新」
- 前提: Task 4 で ViewModel 側の hover state とハンドラが揃っている
- `.onContinuousHover` は macOS 13+、本プロジェクト 14+ なので問題なし
- アニメーション抑制：`.transaction { $0.animation = nil }` でフェード無効化（spec §Non-goals）

**実装内容**:

### ファイル 1: `Sources/Toki/UI/ClockFaceCanvas.swift`（編集）

`onTap` の隣に `onHover` クロージャを追加：

```swift
struct ClockFaceCanvas: View {
    let nowAngle: Double
    let events: [RenderableEvent]
    /// 円弧クリック時に呼ばれる。位置は Canvas のローカル座標。
    var onTap: ((CGPoint, ClockGeometry) -> Void)? = nil
    /// マウスホバー時に呼ばれる。`.active(location)` / `.ended` を受ける。
    var onHover: ((HoverPhase, ClockGeometry) -> Void)? = nil

    var body: some View {
        GeometryReader { proxy in
            Canvas { ctx, size in
                // ... 既存描画
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture(coordinateSpace: .local)
                    .onEnded { value in
                        let geometry = ClockGeometry.standard(in: proxy.size)
                        onTap?(value.location, geometry)
                    }
            )
            .onContinuousHover(coordinateSpace: .local) { phase in
                let geometry = ClockGeometry.standard(in: proxy.size)
                onHover?(phase, geometry)
            }
        }
    }
    // ... 既存メソッド
}
```

注意：既存の `body` 実装（GeometryReader 内の Canvas + gesture）の構造は維持し、`.onContinuousHover` を `.gesture` の **後** に追加する。

### ファイル 2: `Sources/Toki/UI/ClockView.swift`（編集）

最外側を ZStack に切り替え、`viewModel.hoveredTooltip` をオーバーレイ：

```swift
import AppKit
import SwiftUI

struct ClockView: View {
    @ObservedObject var viewModel: ClockViewModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ZStack {
                    ClockFaceCanvas(
                        nowAngle: viewModel.nowAngle,
                        events: viewModel.canvasEvents,
                        onTap: { point, geometry in
                            viewModel.handleArcTap(at: point, geometry: geometry)
                        },
                        onHover: { phase, geometry in
                            viewModel.handleHover(phase: phase, geometry: geometry)
                        }
                    )
                    CurrentEventLabel(state: viewModel.centerState)
                        .allowsHitTesting(false)
                }
                .frame(width: 280, height: 280)

                Divider().frame(height: 0.5)

                NextEventLine(state: viewModel.nextLineState)
                    .frame(height: 40)
            }
            .frame(width: 280, height: 320)
            .background(Color(NSColor.windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
            )

            // ツールチップ最前面オーバーレイ
            if let tooltip = viewModel.hoveredTooltip {
                EventTooltip(timeLabel: tooltip.startEndLabel, title: tooltip.title)
                    .offset(x: tooltip.position.x + 8, y: tooltip.position.y + 8)
                    .allowsHitTesting(false)
                    .transaction { $0.animation = nil }
            }
        }
        .frame(width: 280, height: 320)
    }
}
```

**完了条件**:
- [ ] `swift build` 成功
- [ ] `swift test` で既存 36 ケース全 pass
- [ ] `grep -n "onContinuousHover" Sources/Toki/UI/ClockFaceCanvas.swift` が 1 件マッチ
- [ ] `grep -n "EventTooltip" Sources/Toki/UI/ClockView.swift` が 1 件マッチ
- [ ] `./scripts/build-app.sh` 成功で `.build/Toki.app` 再生成
- [ ] **実機目視確認**：
  - 円弧ホバーでツールチップが即時表示される
  - カーソルが円弧外に出るとツールチップが消える
  - 別の円弧に動かすと内容が切り替わる
  - 時刻 + タイトルの 2 行表示
  - 中央 3 行 / 針 / 円弧の上に描画される

**コミット**:
```bash
git add Sources/Toki/UI/ClockFaceCanvas.swift Sources/Toki/UI/ClockView.swift
git status
git commit -m "feat(ui): ClockFaceCanvas に .onContinuousHover を追加し ClockView でツールチップを表示"
```

**依存**: Task 4

---

## Task 6: クリックで Google Calendar 今日ビューをブラウザで開く

**Commit**: `feat(composition): クリックで Google Calendar 今日ビューをブラウザで開く`

**目的**: Task 1 でスケルトン化した `handleArcTap` に、Google Calendar 今日のビュー URL をブラウザで開く処理を実装する。クリック時にホバーツールチップを即消去する。

**コンテキスト**:
- 参照: plan §6「クリック処理（書き換え）」
- 前提: Task 1 で Calendar.app 統合は撤去済み、Task 5 でホバー機能が動作している
- URL：`https://calendar.google.com/calendar/u/0/r/day/YYYY/MM/DD`（`u/0` 固定）
- イベント開始日（ローカル時刻）を YYYY/MM/DD でフォーマット

**実装内容**:

ファイル: `Sources/Toki/Composition/ClockViewModel.swift`（編集）

### `handleArcTap` を書き換え

```swift
/// イベント円弧のクリックを処理する。
/// 該当イベントの開始日から Google Calendar の今日のビュー URL を組み立て、
/// デフォルトブラウザで開く。Calendar.app は spec 003 で撤去済み。
/// ホバーツールチップは即時消去する（クリックとの UX 競合回避）。
func handleArcTap(at point: CGPoint, geometry: ClockGeometry) {
    guard let event = hitTest(point: point, events: canvasEvents, geometry: geometry) else { return }
    hoveredTooltip = nil
    let urlStr = Self.googleCalendarDayURL(for: event.start, calendar: calendar)
    guard let url = URL(string: urlStr) else { return }
    NSWorkspace.shared.open(url)
}
```

### ヘルパー追加

`// MARK: - クリックハンドラ` セクション内に：

```swift
/// イベント開始日から Google Calendar の day view URL を組み立てる。
/// 形式：https://calendar.google.com/calendar/u/0/r/day/YYYY/MM/DD
/// `u/0` は固定（複数アカウント対応は MVP 範囲外）。
/// ローカルタイムゾーンの暦日を採用（時計表示と整合）。
private static func googleCalendarDayURL(for date: Date, calendar: Calendar) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    let y = c.year ?? 1970
    let m = c.month ?? 1
    let d = c.day ?? 1
    return String(format: "https://calendar.google.com/calendar/u/0/r/day/%04d/%02d/%02d", y, m, d)
}
```

### 暫定コメント削除

Task 1 で入れた `// TODO(spec 003 Task 6): ...` コメントを削除する。

**完了条件**:
- [ ] `swift build` 成功
- [ ] `swift test` で既存 36 ケース全 pass
- [ ] `grep -n "googleCalendarDayURL" Sources/Toki/Composition/ClockViewModel.swift` が 2 件以上マッチ（定義 + 呼び出し）
- [ ] `grep -n "TODO(spec 003 Task 6)" Sources/Toki/Composition/ClockViewModel.swift` が 0 件
- [ ] `grep -rn "ical://" Sources/` が 0 件
- [ ] `grep -rn "NSAppleScript" Sources/` が 0 件
- [ ] `grep -rn "occurrenceURLDateString" Sources/` が 0 件
- [ ] `./scripts/build-app.sh` 成功で `.build/Toki.app` 再生成
- [ ] **実機目視確認**：
  - 円弧クリック → デフォルトブラウザで Google Calendar 今日のビューが開く
  - URL に `/r/day/YYYY/MM/DD` 形式の今日の日付が含まれる
  - クリック直後にホバーツールチップが消える
  - 中央 3 行 / 下部「次の予定」/ メニューバートグル / 終了メニュー / wake は無影響

**コミット**:
```bash
git add Sources/Toki/Composition/ClockViewModel.swift
git status
git commit -m "feat(composition): クリックで Google Calendar 今日ビューをブラウザで開く"
```

**依存**: Task 5

---

## Task 7: SPEC.md の旧クリック挙動を spec 003 に整合

**Commit**: `docs(spec): SPEC.md の旧クリック挙動を spec 003 に整合`

**目的**: SPEC.md に残る `ical://ekevent/...` 例示と「左クリックで純正カレンダー.app を開く」記述を spec 003 反映版に更新する。docs の整合性を保つ。

**コンテキスト**:
- 参照: spec 003 §AC「Calendar.app 統合の撤去」
- 前提: spec 002 までは「クリック → 純正カレンダー.app」が AC として有効だったが、spec 003 で「クリック → Google Calendar ブラウザ起動」に上書き
- SPEC.md は最上位の概要 doc。spec 001 / 002 / 003 と整合性を保つ必要がある
- 該当行（参考、実際の行番号は Read で確認）：
  - §2「インタラクション」近辺の「左クリック：そのイベントを純正カレンダー.app で開く」
  - §7「実装メモ・落とし穴」の「純正カレンダー.app を特定イベントで開く」セクションと `ical://ekevent/...` コード例

**実装内容**:

ファイル: `SPEC.md`（編集）

### 変更箇所 1: §2「インタラクション」

- 変更前：`- **左クリック**：そのイベントを純正カレンダー.appで開く`
- 変更後：`- **左クリック**：そのイベントの日の Google カレンダーをデフォルトブラウザで開く（spec 003 で純正カレンダー.app 連携から変更）`

### 変更箇所 2: §7「純正カレンダー.app を特定イベントで開く」セクション

セクション見出しと内容を spec 003 反映版に更新：

```markdown
### イベント円弧クリック時の挙動（spec 003 で変更）

```swift
let formatted = String(format: "https://calendar.google.com/calendar/u/0/r/day/%04d/%02d/%02d", year, month, day)
let url = URL(string: formatted)!
NSWorkspace.shared.open(url)
```

純正カレンダー.app への `ical://` URL scheme 連携は spec 003 で撤去された。
Google Calendar の繰り返しイベントの `_R<参照日>` suffix で正しい occurrence を
開けない問題が実機検証で判明したため、Google Calendar の web 版（今日のビュー）に
切り替えた。詳細は `specs/003-hover-tooltip-and-browser.md` 参照。
```

### 注意事項

- Read で SPEC.md の現状を確認してから Edit すること
- 該当箇所が複数ある場合は全部更新
- §2「ウィンドウ」/「時計」/「イベント円弧」など spec 002 で更新済みの記述は **変更しない**

**完了条件**:
- [ ] `grep -nE "純正カレンダー\.app" SPEC.md` の出現が「歴史的経緯の説明」のみで、現状仕様としての記述が残らない
- [ ] `grep -nE "ical://ekevent" SPEC.md` が 0 件（コード例から削除）
- [ ] `grep -nE "calendar\.google\.com" SPEC.md` が 1 件以上マッチ（新仕様への参照）
- [ ] `swift build` / `swift test` への影響なし（ドキュメントのみ）

**コミット**:
```bash
git add SPEC.md
git status
git commit -m "docs(spec): SPEC.md の旧クリック挙動を spec 003 に整合"
```

**依存**: Task 6

---

## 全 task 完了後

### 回帰確認

- [ ] `swift test`：Domain 36 ケース全 pass
- [ ] `./scripts/build-app.sh && open .build/Toki.app`：実機目視で spec 003 §AC の 15 項目を walkthrough：
  - 円弧ホバーでツールチップ即時表示
  - 別の円弧に動かすと内容切替（同一円弧内はちらつかない）
  - 円弧外（中央・時計外）で消える
  - 2 行構成（時刻 / タイトル）
  - タイトル長文で `…` 省略
  - z-index：中央テキスト・針・円弧の上
  - クリック → ブラウザに Google Calendar 今日ビュー
  - クリック直後にツールチップ消去
  - 中央 3 行は spec 001 通り
  - 下部「次の予定」は spec 002 通り
  - メニューバートグル / 右クリック終了 / wake / タイマー無影響
  - Calendar.app が起動する経路がない
  - ダーク/ライト両モードで視認性 OK

### コードベース確認（Task 6 完了後と同じ）

- `grep -rn "ical://" Sources/` → 0 件
- `grep -rn "NSAppleScript" Sources/` → 0 件
- `grep -rn "NSAppleEventsUsageDescription" Resources/` → 0 件
- `grep -rn "occurrenceURLDateString" Sources/` → 0 件

### コードレビュー

- `code-reviewer` agent で全体レビュー（依存方向 / 不要な抽象化 / dead code チェック）
