# 003 — ホバー詳細表示と Google Calendar ブラウザ起動 技術プラン

`specs/003-hover-tooltip-and-browser.md` を技術プランに展開したもの。`/tasks` で atomic task に分解する元となる。

## 0. 確定済み設計判断

ユーザーとの合意事項：

1. **Calendar.app 統合を完全撤去**：`ical://` 系の URL、`NSAppleScript`、`occurrenceURLDateString` ヘルパーを削除
2. **クリック → Google Calendar 今日のビュー** をデフォルトブラウザで開く（`https://calendar.google.com/calendar/u/0/r/day/YYYY/MM/DD`、`u/0` 固定）
3. **ホバー → ツールチップ**（Toki ウィンドウ内のオーバーレイ）で「HH:MM - HH:MM」+「タイトル」の 2 行表示
4. **中央 3 行は据え置き**（ホバーで切り替わらない、spec 001 通り）
5. **ツールチップ位置**：カーソル位置から `(+8, +8)` の右下オフセット（画面端反転は Phase 2）
6. **Task 7（SPEC.md 整合）も実施**：旧クリック挙動の記述を spec 003 に合わせて更新

## 1. Requirements restatement

spec 003 のゴール：

1. イベント円弧にカーソルを乗せると Toki ウィンドウ内に「開始-終了時刻 / タイトル」を 2 行で示すツールチップ風オーバーレイを表示し、離れたら消す
2. イベント円弧の左クリックで Google Calendar の今日のビューをデフォルトブラウザで開く
3. Calendar.app 統合（`ical://` URL、`NSAppleScript`、Info.plist `NSAppleEventsUsageDescription`）をコードベースから完全撤去
4. 中央 3 行テキスト・下部「次の予定」ライン・タイマー・wake 対応・メニューバートグル・右クリック終了などの既存挙動は無変更
5. Domain / Infrastructure 層は触らず、テスト 36 ケース全 pass を維持

## 2. Open Questions — 解決済み

spec 003 の 10 件すべて [CONFIDENT] で着手可能：

### UX
1. **ツールチップ位置** → カーソル右下 `(+8, +8)`。画面端反転は spec で Phase 2 明示済み
2. **スタイル** → 角丸 6pt + `Color(NSColor.controlBackgroundColor)` + 0.5pt secondary 枠線 + 薄影。`.help()` は `LSUIElement` で挙動が不安定なため不採用。フォント 11pt（時刻）+ 12pt medium（タイトル）
3. **表示ディレイ** → 即時表示。`Equatable` で同値スキップして点滅防止
4. **クリック後の挙動** → ウィンドウ minimize/hide は spec 001「常時前面」原則に反するため不要

### 描画
5. **z-index** → ClockView 最外側 ZStack の最前面、`.allowsHitTesting(false)`
6. **ウィンドウ端見切れ** → MVP では見切れ許容（spec で Phase 2 明示済み）

### 技術
7. **ホバー検出方式** → SwiftUI `.onContinuousHover(coordinateSpace: .local)`（macOS 13+、本プロジェクト 14+ なので OK）。`NSTrackingArea` は Canvas との座標統合が煩雑
8. **複数イベント重なり時の優先順位** → 既存 `hitTest` の挙動（配列順最初に当たったもの）。Domain で `earliest start wins` 済みなので実害なし
9. **URL の `/u/0/` 扱い** → 固定。複数アカウント分岐は設定 UI 必須で MVP 範囲外
10. **ホバー中のクリック発生時** → クリックハンドラ冒頭で `hoveredTooltip = nil` → ブラウザ起動

## 3. ファイル別変更計画

### 新規

| ファイル | 概要 | 想定行数 |
|---|---|---|
| `Sources/Toki/UI/EventTooltip.swift` | SwiftUI View。time と title を受けて 2 行表示する presentation-only View | 約 40 行 |
| `Sources/Toki/UI/TooltipState.swift` | UI 層 Value Object（`startEndLabel: String`、`title: String`、`position: CGPoint`）、`Equatable` 準拠 | 約 20 行 |

### 編集

| ファイル | 変更内容 | 想定差分 |
|---|---|---|
| `Composition/ClockViewModel.swift` | クリック書き換え、hover 状態追加、`occurrenceURLDateString` 削除 | +60 / -30 |
| `UI/ClockFaceCanvas.swift` | `.onContinuousHover` + `onHover` クロージャ追加 | +15 |
| `UI/ClockView.swift` | 最外側 ZStack 化、`EventTooltip` オーバーレイ | +20 |
| `UI/RenderableEvent.swift` | `end: Date` を 1 行追加 | +3 |
| `SPEC.md` | §17 / §73 / §222 / §319-324 のクリック関連記述を spec 003 整合に更新 | +10 / -10 |

### 削除

- `ClockViewModel.handleArcTap` 内の `ical://` URL 構築ロジック
- `ClockViewModel.occurrenceURLDateString(_:)` メソッド全体
- `ical:` フォールバック経路

### 依存方向の確認
- 新規 `EventTooltip.swift` と `TooltipState.swift` は UI 層に置く（SwiftUI / Foundation / CoreGraphics のみ依存、Domain 影響なし）
- ViewModel が UI 層の `TooltipState` を `@Published` で持つのは、既存 `CenterState` / `NextLineState` と同じパターン（CLAUDE.md の `Composition → UI → Domain` 方向に整合）

## 4. ホバー検出の詳細

### `.onContinuousHover` の使い方

`ClockFaceCanvas` の GeometryReader 内、既存 `.gesture` と同レベルで：

```swift
.onContinuousHover(coordinateSpace: .local) { phase in
    let geometry = ClockGeometry.standard(in: proxy.size)
    onHover?(phase, geometry)
}
```

- `phase` は `HoverPhase` enum：`.active(CGPoint)` / `.ended`
- `.active` 中はマウス移動で連続発火 → ViewModel 側で `TooltipState: Equatable` 比較で同値スキップ
- `.ended` で `hoveredTooltip = nil`

### ViewModel `handleHover` の挙動

```swift
func handleHover(phase: HoverPhase, geometry: ClockGeometry) {
    switch phase {
    case .active(let location):
        if let event = hitTest(point: location, events: canvasEvents, geometry: geometry) {
            let tooltip = TooltipState(
                startEndLabel: Self.formatTimeRange(event.start, event.end, calendar: calendar),
                title: event.title,
                position: location
            )
            if hoveredTooltip != tooltip { hoveredTooltip = tooltip }
        } else if hoveredTooltip != nil {
            hoveredTooltip = nil
        }
    case .ended:
        if hoveredTooltip != nil { hoveredTooltip = nil }
    }
}
```

### `event.end` の取り方

現状の `RenderableEvent` は `start: Date` のみ。ツールチップで `HH:MM - HH:MM` を出すため **`end: Date` を追加**（Task 3）。

理由：`RenderableEvent` は既に `start` を持っており、`end` 追加は自然な拡張。lookup マップ方式より再描画コストが少なく、責務もフラットなまま。

## 5. ツールチップ View の詳細

### `EventTooltip.swift`

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

### `TooltipState.swift`

```swift
import CoreGraphics
import Foundation

/// UI 層 Value Object。ホバー中のイベントから組み立てる表示状態。
struct TooltipState: Equatable {
    let startEndLabel: String   // "HH:MM - HH:MM"
    let title: String
    let position: CGPoint       // Canvas ローカル座標、ツールチップ左上の基準点
}
```

`Equatable` で `@Published` の同値時 no-op を可能にする（チラつき防止）。

## 6. クリック処理（書き換え）

### 新 `handleArcTap`

```swift
func handleArcTap(at point: CGPoint, geometry: ClockGeometry) {
    guard let event = hitTest(point: point, events: canvasEvents, geometry: geometry) else { return }
    hoveredTooltip = nil  // OQ #10: クリックでツールチップ即消去
    let urlStr = Self.googleCalendarDayURL(for: event.start, calendar: calendar)
    guard let url = URL(string: urlStr) else { return }
    NSWorkspace.shared.open(url)
}
```

### `googleCalendarDayURL` ヘルパー

```swift
/// イベント開始日から Google Calendar の day view URL を組み立てる。
private static func googleCalendarDayURL(for date: Date, calendar: Calendar) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    let y = c.year ?? 1970
    let m = c.month ?? 1
    let d = c.day ?? 1
    return String(format: "https://calendar.google.com/calendar/u/0/r/day/%04d/%02d/%02d", y, m, d)
}
```

## 7. ViewModel 状態追加

### プロパティ
```swift
@Published private(set) var hoveredTooltip: TooltipState? = nil
```

### メソッド `handleHover`
§4 参照。

### ヘルパー `formatTimeRange`
```swift
private static func formatTimeRange(_ start: Date, _ end: Date, calendar: Calendar) -> String {
    "\(formatHHMM(start, calendar: calendar)) - \(formatHHMM(end, calendar: calendar))"
}
```

既存 `formatHHMM` をそのまま再利用。

## 8. ClockView の更新

最外側を ZStack に切り替え、`viewModel.hoveredTooltip` をオーバーレイ：

```swift
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
                .transaction { $0.animation = nil }  // spec §Non-goals: アニメーション無し
        }
    }
    .frame(width: 280, height: 320)
}
```

## 9. 実装フェーズ順序

1 タスク = 1 commit、Conventional Commits + scope。期待値：7 task（最後の SPEC.md 整合含む）。

### Task 1: `refactor(composition): ClockViewModel から Calendar.app 統合（ical:// 連携）を撤去`
- 対象：`Sources/Toki/Composition/ClockViewModel.swift`
- 作業：`handleArcTap` 中身を「hitTest だけ」のスケルトン化、`occurrenceURLDateString` 削除、暫定コメントを残す
- 完了条件：`swift build` / `swift test` pass、Calendar.app が起動しない
- 依存：なし
- 想定差分：-25 / +5

### Task 2: `feat(ui): TooltipState と EventTooltip View を新規作成`
- 対象：`Sources/Toki/UI/TooltipState.swift`、`Sources/Toki/UI/EventTooltip.swift`
- 作業：§5 のコードをそのまま起こす
- 完了条件：`swift build` 通過
- 依存：なし
- 想定差分：+60

### Task 3: `feat(ui): RenderableEvent に end: Date を追加`
- 対象：`Sources/Toki/UI/RenderableEvent.swift`、`Composition/ClockViewModel.swift`
- 作業：`end: Date` を `RenderableEvent` に追加、`canvasEvents` 組み立てで `end: ev.end` を 1 行追加
- 完了条件：`swift build` / `swift test` pass
- 依存：なし
- 想定差分：+3

### Task 4: `feat(composition): ClockViewModel に hover state と handleHover を追加`
- 対象：`Sources/Toki/Composition/ClockViewModel.swift`
- 作業：`@Published hoveredTooltip`、`handleHover(phase:geometry:)`、`formatTimeRange` 追加
- 完了条件：`swift build` / `swift test` pass、ViewModel から `TooltipState` 観測可能
- 依存：Task 2、Task 3
- 想定差分：+30

### Task 5: `feat(ui): ClockFaceCanvas に .onContinuousHover を追加し ClockView でツールチップを表示`
- 対象：`Sources/Toki/UI/ClockFaceCanvas.swift`、`Sources/Toki/UI/ClockView.swift`
- 作業：`onHover` クロージャ追加、ClockView 最外側 ZStack 化、tooltip overlay
- 完了条件：`swift build` / 実機ホバー動作確認
- 依存：Task 4
- 想定差分：+35 / -5

### Task 6: `feat(composition): クリックで Google Calendar 今日ビューをブラウザで開く`
- 対象：`Sources/Toki/Composition/ClockViewModel.swift`
- 作業：`handleArcTap` を §6 の最終形に書き換え、`googleCalendarDayURL` 追加、Task 1 暫定コメント削除
- 完了条件：`swift build` / 実機クリック動作確認
- 依存：Task 5
- 想定差分：+15

### Task 7: `docs(spec): SPEC.md の旧クリック挙動を spec 003 に整合`
- 対象：`SPEC.md`
- 作業：`ical://` 例示と Phase 2 のインタラクション記述を spec 003 反映版に更新
- 完了条件：grep で `ical://` ヒット 0
- 依存：Task 6
- 想定差分：+10 / -10

## 10. リスク

| # | リスク | 影響度 | 緩和策 |
|---|---|---|---|
| R1 | `.onContinuousHover` 連続発火で再描画コスト大 | 中 | `TooltipState: Equatable` で同値スキップ |
| R2 | 30 分未満の細い円弧でホバーがチラつく | 低 | 同上 + hitTest 結果が同 event id なら early return |
| R3 | ウィンドウ右端・下端でツールチップ見切れ | 低 | spec §Non-goals 明示済み、Phase 2 行き |
| R4 | `.onContinuousHover` バージョン互換性 | 極低 | macOS 14+ で API 提供（macOS 13+ サポート） |
| R5 | Domain テスト 36 ケース回帰 | 極低 | Domain 無変更、各 task で `swift test` ゲート |
| R6 | `NSWorkspace.shared.open` ブラウザ未起動失敗 | 極低 | `https://` の default handler は必ず存在 |
| R7 | spec 002 の旧 AC（クリック→Calendar.app）docs 上に残存 | 中 | Task 7 で SPEC.md 整合、spec 003 が上書きする旨を本ファイルが明示済み |

## 11. テスト方針

### 自動テスト
- `swift test` で Domain 36 ケース全 pass を各タスク完了時に確認
- 本 iteration では Domain 無変更、テスト追加・修正ゼロ

### 手動目視チェックリスト（Task 5, 6 完了後）
- [ ] 円弧ホバーでツールチップ即時表示
- [ ] 別の円弧に動かすと内容切替（同一円弧内はちらつかない）
- [ ] 円弧外（中央・時計外）で消える
- [ ] 2 行構成（時刻 / タイトル）
- [ ] タイトル長文で `…` 省略
- [ ] z-index：中央テキスト・針・円弧の上
- [ ] クリック → ブラウザに Google Calendar 今日ビュー
- [ ] クリック直後にツールチップ消去
- [ ] 中央 3 行は spec 001 通り
- [ ] 下部「次の予定」は spec 002 通り
- [ ] メニューバートグル / 右クリック終了 / wake / タイマー無影響
- [ ] Calendar.app が起動する経路がない
- [ ] ダーク/ライト両モードで視認性 OK

### コードベース確認（Task 6 完了後）
- `grep -rn "ical://" Sources/` → 0 件
- `grep -rn "NSAppleScript" Sources/` → 0 件
- `grep -rn "NSAppleEventsUsageDescription" Resources/` → 0 件
- `grep -rn "occurrenceURLDateString" Sources/` → 0 件

## 12. Out of scope 確認

spec 003 §Non-goals 再掲：

- 中央テキストのホバー切替なし
- ツールチップ内アクションボタン（将来 Phase 2）
- Google Calendar API / OAuth 連携なし
- Meet / Zoom リンク自動検出なし
- イベント編集機能なし
- 複数イベント重なり時の切替 UI なし
- ツールチップの自動位置調整（画面端反転、Phase 2）
- アニメーション（フェード）なし
- `ical://` 経路の保持なし（完全撤去）
- Calendar.app fallback 起動経路なし
- Exchange / iCloud 用の特別分岐なし

## 参考ファイル

- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/specs/003-hover-tooltip-and-browser.md`
- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/CLAUDE.md`
- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/Sources/Toki/Composition/ClockViewModel.swift`
- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/Sources/Toki/UI/ClockFaceCanvas.swift`
- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/Sources/Toki/UI/ClockView.swift`
- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/Sources/Toki/UI/EventArcRenderer.swift`
- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/Sources/Toki/UI/RenderableEvent.swift`

次のステップ：`/tasks 003-hover-tooltip-and-browser` で atomic task ファイル化 → fresh subagent で 1 commit ずつ実装。
