# 004 — event-detail-and-tooltip-flip: Tasks

参照: `specs/004-event-detail-and-tooltip-flip.md` / `specs/004-event-detail-and-tooltip-flip-plan.md`

合計: **6 tasks**

実装順序：上から順に。各 task は fresh subagent に渡して 1 commit ずつ。

Domain / Infrastructure / UI / Composition 全層変更。Window / App 層は無変更。

---

## Task 1: Event に calendarTitle を追加

**Commit**: `feat(domain): Event に calendarTitle を追加`

**目的**: Domain `Event` に `calendarTitle: String` を追加し、Infrastructure 層から渡された calendar 名/メールアドレスを Composition / UI まで通せるようにする。Google event 詳細 URL の `eid` 生成に必要。

**コンテキスト**:
- 参照: spec 004 §AC「Domain / Infrastructure 影響」、plan §4
- 前提: 既存 `Event` は id / title / start / end / calendarColor / externalIdentifier を持つ
- 不変条件は変えない（既存：`!id.isEmpty`、`start < end`）
- 新フィールド `calendarTitle: String` は空文字列許容（required 非 nil）
- `Equatable` は **id ベース維持**（spec 001 の `CGColor` 比較回避方針を踏襲）
- テストヘルパに `calendarTitle: String = ""` デフォルト引数を追加することで 36 ケース無変更 pass

**実装内容**:

### ファイル 1: `Sources/Toki/Domain/Event.swift`（編集）

`externalIdentifier` の直後に `calendarTitle: String` を追加：

```swift
import Foundation
import CoreGraphics

struct Event: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let calendarColor: CGColor
    let externalIdentifier: String?
    /// EKCalendar.title から伝播するカレンダー名（Google の場合はメールアドレス）。
    /// Google event 詳細 URL の eid 生成に必要。空文字列は許容。
    let calendarTitle: String

    init?(id: String, title: String, start: Date, end: Date,
          calendarColor: CGColor, externalIdentifier: String?,
          calendarTitle: String) {
        guard !id.isEmpty, start < end else { return nil }
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.calendarColor = calendarColor
        self.externalIdentifier = externalIdentifier
        self.calendarTitle = calendarTitle
    }
}

extension Event: Equatable {
    static func == (lhs: Event, rhs: Event) -> Bool {
        lhs.id == rhs.id
    }
}
```

### ファイル 2: `Tests/TokiTests/EventTests.swift`（編集）

`makeEvent` ヘルパに `calendarTitle: String = ""` デフォルト引数追加、`Event(...)` 呼び出しに `calendarTitle: calendarTitle` 追記：

```swift
private func makeEvent(id: String = "id-1",
                       title: String = "テスト予定",
                       start: Date = Date(timeIntervalSince1970: 1_700_000_000),
                       end: Date = Date(timeIntervalSince1970: 1_700_003_600),
                       calendarTitle: String = "")
    -> Event? {
    Event(id: id, title: title, start: start, end: end,
          calendarColor: makeColor(), externalIdentifier: "ext-1",
          calendarTitle: calendarTitle)
}
```

### ファイル 3: `Tests/TokiTests/EventStatusTests.swift`（編集）

同様に：

```swift
private func makeEvent(start: Date, end: Date, calendarTitle: String = "") -> Event {
    Event(id: "e1", title: "test", start: start, end: end,
          calendarColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
          externalIdentifier: nil,
          calendarTitle: calendarTitle)!
}
```

### ファイル 4: `Tests/TokiTests/DayTimelineTests.swift`（編集）

同様に：

```swift
private func makeEvent(id: String, start: Date, end: Date, calendarTitle: String = "") -> Event {
    Event(id: id, title: "ev-\(id)", start: start, end: end,
          calendarColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
          externalIdentifier: nil,
          calendarTitle: calendarTitle)!
}
```

各テストファイルの **ケース本体は無変更**。

**完了条件**:
- [ ] `grep -n "let calendarTitle: String" Sources/Toki/Domain/Event.swift` が 1 件マッチ
- [ ] `grep -nE "calendarTitle: String = \"\"" Tests/TokiTests/EventTests.swift Tests/TokiTests/EventStatusTests.swift Tests/TokiTests/DayTimelineTests.swift` が 3 件マッチ
- [ ] `swift build` 成功
- [ ] `swift test` で既存 36 ケース全 pass（テストケース本体は無変更で通る）

**コミット**:
```bash
git add Sources/Toki/Domain/Event.swift Tests/TokiTests/EventTests.swift Tests/TokiTests/EventStatusTests.swift Tests/TokiTests/DayTimelineTests.swift
git status
git commit -m "feat(domain): Event に calendarTitle を追加"
```

**依存**: なし

---

## Task 2: EventKitGateway で calendarTitle を伝播

**Commit**: `feat(infra): EventKitGateway で calendarTitle を伝播`

**目的**: Infrastructure 層の `convert(_:)` で `ek.calendar.title` を `Event.calendarTitle` にコピーする。

**コンテキスト**:
- 参照: spec 004 §AC「Domain / Infrastructure 影響」、plan §5
- 前提: Task 1 で `Event.calendarTitle` が追加され、init signature が拡張されている
- `EKCalendar.title` は EventKit API 上 `String` 非 nil 保証

**実装内容**:

ファイル: `Sources/Toki/Infrastructure/EventKitGateway.swift`（編集）

`convert(_:)` の `Event(...)` 呼び出しに 1 行追加：

```swift
private static func convert(_ ek: EKEvent) -> Event? {
    let baseId = ek.eventIdentifier ?? UUID().uuidString
    let id = "\(baseId)#\(ek.startDate.timeIntervalSince1970)"
    return Event(
        id: id,
        title: ek.title ?? "(無題)",
        start: ek.startDate,
        end: ek.endDate,
        calendarColor: ek.calendar.cgColor,
        externalIdentifier: ek.calendarItemExternalIdentifier,
        calendarTitle: ek.calendar.title   // 新規
    )
}
```

**完了条件**:
- [ ] `grep -n "calendarTitle: ek.calendar.title" Sources/Toki/Infrastructure/EventKitGateway.swift` が 1 件マッチ
- [ ] `swift build` 成功
- [ ] `swift test` で 36 ケース全 pass

**コミット**:
```bash
git add Sources/Toki/Infrastructure/EventKitGateway.swift
git status
git commit -m "feat(infra): EventKitGateway で calendarTitle を伝播"
```

**依存**: Task 1

---

## Task 3: RenderableEvent と canvasEvents で calendarTitle 伝播

**Commit**: `feat(ui): RenderableEvent と canvasEvents で calendarTitle 伝播`

**目的**: UI 層 `RenderableEvent` に `calendarTitle: String` を追加し、ViewModel の `canvasEvents` で Domain `Event.calendarTitle` を伝播する。

**コンテキスト**:
- 参照: plan §6.1、§7.1
- 前提: Task 2 で Domain Event に calendar 名がデータとして入っている
- `RenderableEvent` 初期化は `canvasEvents` の 1 箇所のみ

**実装内容**:

### ファイル 1: `Sources/Toki/UI/RenderableEvent.swift`（編集）

`end: Date` の直後に `calendarTitle: String` を追加：

```swift
struct RenderableEvent: Identifiable {
    let id: String
    let title: String
    let startAngle: Double
    let endAngle: Double
    let color: CGColor
    let status: EventStatus
    let externalIdentifier: String?
    /// イベントの開始時刻。
    let start: Date
    /// イベントの終了時刻。
    let end: Date
    /// イベントが属するカレンダー名（Google の場合はメールアドレス）。
    /// Google event 詳細 URL の eid 生成に必要。
    let calendarTitle: String
}
```

### ファイル 2: `Sources/Toki/Composition/ClockViewModel.swift`（編集）

`canvasEvents` の `RenderableEvent` 初期化に `calendarTitle: ev.calendarTitle` を追加：

```swift
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
    calendarTitle: ev.calendarTitle   // 新規
)
```

**完了条件**:
- [ ] `grep -n "let calendarTitle: String" Sources/Toki/UI/RenderableEvent.swift` が 1 件マッチ
- [ ] `grep -n "calendarTitle: ev.calendarTitle" Sources/Toki/Composition/ClockViewModel.swift` が 1 件マッチ
- [ ] `swift build` 成功
- [ ] `swift test` で 36 ケース全 pass
- [ ] `./scripts/build-app.sh` 成功で `.app` 再生成

**コミット**:
```bash
git add Sources/Toki/UI/RenderableEvent.swift Sources/Toki/Composition/ClockViewModel.swift
git status
git commit -m "feat(ui): RenderableEvent と canvasEvents で calendarTitle 伝播"
```

**依存**: Task 2

---

## Task 4: クリックで Google event 詳細 URL を組み立てる（fallback 付き）

**Commit**: `feat(composition): クリックで Google event 詳細 URL を組み立てる（fallback 付き）`

**目的**: `ClockViewModel.handleArcTap` で Google event の場合は detail URL（`/r/event?eid=...`）を、非 Google event は今日のビュー（spec 003 のまま）を開くように分岐する。

**コンテキスト**:
- 参照: spec 004 §AC「Google Calendar イベント詳細ジャンプ」、plan §7.2
- 前提: Task 3 で `RenderableEvent.calendarTitle` が利用可能
- 既存 `googleCalendarDayURL(for:calendar:)` は維持（fallback として呼ばれる）
- `eid` の中身：`base64("<base_uid> <calendar_email>")`、URL-safe（`+`→`-`、`/`→`_`、`=` 除去）
- `base_uid`：`calendarItemExternalIdentifier` から `_R<digits>T<digits>` suffix を除去
- 失敗条件：`externalIdentifier` が nil または `@google.com` で終わらない、または `calendarTitle` 空、または `utf8` 化失敗 → fallback

**実装内容**:

ファイル: `Sources/Toki/Composition/ClockViewModel.swift`（編集）

### `handleArcTap` を書き換え

```swift
func handleArcTap(at point: CGPoint, geometry: ClockGeometry) {
    guard let event = hitTest(point: point, events: canvasEvents, geometry: geometry) else { return }
    hoveredTooltip = nil
    let urlStr = Self.calendarURL(for: event, calendar: calendar)
    guard let url = URL(string: urlStr) else { return }
    NSWorkspace.shared.open(url)
}
```

### `// MARK: - クリックハンドラ` セクション内に 3 つの helper を追加

```swift
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
```

既存 `googleCalendarDayURL(for:calendar:)` は **削除しない**（fallback として `calendarURL` から呼ばれる）。

**完了条件**:
- [ ] `grep -n "func calendarURL" Sources/Toki/Composition/ClockViewModel.swift` が 1 件マッチ
- [ ] `grep -n "func googleEventDetailURL" Sources/Toki/Composition/ClockViewModel.swift` が 1 件マッチ
- [ ] `grep -n "func stripRecurrenceSuffix" Sources/Toki/Composition/ClockViewModel.swift` が 1 件マッチ
- [ ] `grep -n "calendarURL(for: event" Sources/Toki/Composition/ClockViewModel.swift` が 1 件マッチ（handleArcTap 内呼び出し）
- [ ] `grep -n "func googleCalendarDayURL" Sources/Toki/Composition/ClockViewModel.swift` が 1 件マッチ（既存維持）
- [ ] `swift build` 成功
- [ ] `swift test` で 36 ケース全 pass
- [ ] `./scripts/build-app.sh` 成功
- [ ] **実機目視確認**（必須）：`open .build/Toki.app` で起動し以下を確認
  - Google event（`@google.com` 末尾）クリック → ブラウザで `/r/event?eid=...` が開き、該当イベントの detail に到達する
  - 繰り返しイベント（`_RYYYYMMDD...` 付き）でも該当 instance に到達
  - 非 Google event（Exchange、`@google.com` で終わらない）→ spec 003 と同じ今日のビュー `/r/day/...`
  - ヒットなし領域クリック → 何も起きない（無音）

**コミット**:
```bash
git add Sources/Toki/Composition/ClockViewModel.swift
git status
git commit -m "feat(composition): クリックで Google event 詳細 URL を組み立てる（fallback 付き）"
```

**依存**: Task 3

---

## Task 5: ClockView でツールチップ位置を反転判定する

**Commit**: `feat(ui): ClockView でツールチップ位置を反転判定する`

**目的**: ツールチップがウィンドウ右端 / 下端を超えそうな場合、自動的に反転表示することで見切れを解消する。

**コンテキスト**:
- 参照: spec 004 §AC「ツールチップ位置の自動反転」、plan §6.2
- 前提: Task 5 までの実装でツールチップ自体は表示されている
- 想定 tooltip サイズ：固定 200pt × 40pt（`EventTooltip.maxWidth` と 2 行時の実測高さ）
- 反転オフセット：対称 `(-8, -8)`
- 左端 / 上端は `max(0, ...)` でクランプ

**実装内容**:

ファイル: `Sources/Toki/UI/ClockView.swift`（編集）

### `body` 内の tooltip 描画ブロック書き換え

```swift
// ツールチップ最前面オーバーレイ
// 想定サイズで右端/下端を検知し、X/Y 軸独立に位置を反転する。
// spec §Non-goals「アニメーション無し」のため transaction で animation を抑制。
if let tooltip = viewModel.hoveredTooltip {
    let position = Self.tooltipDisplayPosition(for: tooltip.position)
    EventTooltip(timeLabel: tooltip.startEndLabel, title: tooltip.title)
        .offset(x: position.x, y: position.y)
        .allowsHitTesting(false)
        .transaction { $0.animation = nil }
}
```

### `ClockView` extension に static helper と定数を追加

ファイルの末尾、`struct ClockView { ... }` の外側に：

```swift
extension ClockView {
    /// ツールチップ想定サイズ。EventTooltip.maxWidth と 2 行時の実測高さに合わせる。
    private static let tooltipWidth: CGFloat = 200
    private static let tooltipHeight: CGFloat = 40
    private static let tooltipOffset: CGFloat = 8
    /// ウィンドウサイズ。ClockView.body の .frame と同じ値を使う。
    private static let canvasWidth: CGFloat = 280
    private static let windowHeight: CGFloat = 320

    /// ホバー位置からツールチップを描画する左上座標を計算する。
    /// X/Y 軸独立に判定：右端/下端を超える側だけ反転、左/上端は 0 にクランプ。
    static func tooltipDisplayPosition(for hover: CGPoint) -> CGPoint {
        let x: CGFloat = (hover.x + tooltipOffset + tooltipWidth > canvasWidth)
            ? max(0, hover.x - tooltipOffset - tooltipWidth)
            : hover.x + tooltipOffset
        let y: CGFloat = (hover.y + tooltipOffset + tooltipHeight > windowHeight)
            ? max(0, hover.y - tooltipOffset - tooltipHeight)
            : hover.y + tooltipOffset
        return CGPoint(x: x, y: y)
    }
}
```

**完了条件**:
- [ ] `grep -n "tooltipDisplayPosition" Sources/Toki/UI/ClockView.swift` が 2 件マッチ（定義 + 呼び出し）
- [ ] `grep -n "tooltipWidth.*200" Sources/Toki/UI/ClockView.swift` が 1 件マッチ
- [ ] `grep -nE "\\.offset\\(x: position\\.x, y: position\\.y\\)" Sources/Toki/UI/ClockView.swift` が 1 件マッチ
- [ ] `grep -nE "\\.offset\\(x: tooltip\\.position\\.x \\+ 8" Sources/Toki/UI/ClockView.swift` が 0 件（旧呼び出し削除）
- [ ] `swift build` 成功
- [ ] `swift test` で 36 ケース全 pass
- [ ] `./scripts/build-app.sh` 成功
- [ ] **実機目視確認**（必須）：`open .build/Toki.app` で起動し以下を確認
  - 時計の 12 時付近（右下寄り）の event にホバー → tooltip が左上方向に反転
  - 時計の 6 時付近の event にホバー → tooltip が上方向に反転
  - 時計の 3 時付近の event にホバー → tooltip が左方向に反転
  - 時計の 9 時付近 / 中央上方の event にホバー → tooltip は従来通り `(+8, +8)`
  - 四隅でウィンドウ枠を越えない
  - tooltip 内容は spec 003 と同一

**コミット**:
```bash
git add Sources/Toki/UI/ClockView.swift
git status
git commit -m "feat(ui): ClockView でツールチップ位置を反転判定する"
```

**依存**: Task 4

---

## Task 6: SPEC.md にクリック挙動の Google detail URL 仕様を追記

**Commit**: `docs(spec): SPEC.md にクリック挙動の Google detail URL 仕様を追記`

**目的**: spec 004 で追加された「Google event detail URL ジャンプ」「ツールチップ自動反転」の挙動を `SPEC.md` に反映し、docs の整合性を保つ。

**コンテキスト**:
- 参照: spec 004 §AC「Google Calendar イベント詳細ジャンプ」「ツールチップ位置の自動反転」
- 前提: spec 003 で SPEC.md は「クリック → 今日のビュー」と書かれている（Task 7 で更新済み）
- spec 004 では「Google event は detail、それ以外は今日のビュー」に分岐する旨を追記

**実装内容**:

ファイル: `SPEC.md`（編集）

Read で現状確認し、以下の方向で更新：

### 変更箇所 1: §2「インタラクション」の左クリック記述

- 変更前（spec 003 で更新済み）：
  ```
  - **左クリック**：そのイベントの日の Google カレンダーをデフォルトブラウザで開く（spec 003 で純正カレンダー.app 連携から変更）
  ```
- 変更後：
  ```
  - **左クリック**：そのイベントを Google Calendar で開く（spec 004 で event detail URL に拡張）
    - Google event（`@google.com` 末尾）→ `/r/event?eid=<base64>` で詳細ページ
    - 非 Google event（Exchange / iCloud 等）→ `/r/day/YYYY/MM/DD` の今日のビュー fallback
  ```

### 変更箇所 2: §2「インタラクション」のマウスオーバー記述

- 変更前（spec 003 で更新済み）：
  ```
  - **マウスオーバー**：イベント円弧の上に来ると、ツールチップで時刻 + タイトルが表示される（中央表示は現状維持、spec 003 で変更）
  ```
- 変更後：
  ```
  - **マウスオーバー**：イベント円弧の上に来ると、ツールチップで時刻 + タイトルが表示される（中央表示は現状維持）
    - tooltip 位置はウィンドウ端で自動反転する（spec 004 で追加）
  ```

### 変更箇所 3: §7「イベント円弧クリック時の挙動」セクション

- 変更前（spec 003 で更新済み）：今日のビューを開く `String(format: ...)` のコード例
- 変更後：Google detail URL の `eid` 組み立て例を追記し、fallback の旨を明記

```markdown
### イベント円弧クリック時の挙動（spec 003 / 004）

```swift
// Google event なら detail URL を組み立て、それ以外は今日のビュー fallback。
private static func calendarURL(for event: RenderableEvent, calendar: Calendar) -> String {
    if let detail = googleEventDetailURL(for: event) {
        return detail
    }
    return googleCalendarDayURL(for: event.start, calendar: calendar)
}
```

詳細 URL 形式（Google）：
- `https://calendar.google.com/calendar/u/0/r/event?eid=<URL-safe-base64>`
- eid 中身：`base64("<base_uid> <calendar_email>")`
  - `base_uid` は `calendarItemExternalIdentifier` から `_R<digits>T<digits>` を除去
  - URL-safe：`+`→`-`、`/`→`_`、`=` 除去

今日のビュー URL（非 Google fallback、spec 003 から）：
- `https://calendar.google.com/calendar/u/0/r/day/YYYY/MM/DD`

純正カレンダー.app への `ical://` URL scheme 連携は spec 003 で撤去された。
Google Calendar の繰り返しイベントの `_R<参照日>` suffix で正しい occurrence を
開けない問題が実機検証で判明したため、Google Calendar の web 版に切り替えた。
詳細は `specs/003-hover-tooltip-and-browser.md` および `specs/004-event-detail-and-tooltip-flip.md` 参照。
```

### 注意事項

- Read で SPEC.md の現状を確認してから Edit すること
- §2「ウィンドウ」/「時計」/「イベント円弧」など spec 002 / 003 で更新済みの記述は **変更しない**
- §10「Claude Code への指示」など Phase 2 / Phase 3 言及はそのまま残す

**完了条件**:
- [ ] `grep -nE "spec 004" SPEC.md` が 1 件以上マッチ
- [ ] `grep -nE "/r/event\?eid=" SPEC.md` が 1 件以上マッチ（detail URL 形式）
- [ ] `grep -nE "/r/day/" SPEC.md` が 1 件以上マッチ（今日のビュー fallback）
- [ ] `grep -nE "ツールチップ" SPEC.md` が 2 件以上マッチ（spec 003 と spec 004 両方の言及）
- [ ] `grep -nE "ical://ekevent" SPEC.md` が 0 件（spec 003 で削除済み）
- [ ] `swift build` / `swift test` への影響なし（ドキュメントのみ）

**コミット**:
```bash
git add SPEC.md
git status   # SPEC.md のみがステージされていること
git commit -m "docs(spec): SPEC.md にクリック挙動の Google detail URL 仕様を追記"
```

**依存**: Task 5

---

## 全 task 完了後

### 回帰確認

- [ ] `swift test`：Domain 36 ケース全 pass
- [ ] `./scripts/build-app.sh && open .build/Toki.app`：実機目視で spec 004 §AC の 14 項目を walkthrough：

**ツールチップ位置反転**
- [ ] 12 時付近の event ホバー → 左上方向に反転
- [ ] 6 時付近の event ホバー → 上方向に反転
- [ ] 3 時付近の event ホバー → 左方向に反転
- [ ] 9 時付近 / 中央上方 → 従来通り `(+8, +8)`
- [ ] 四隅でウィンドウ枠を越えない
- [ ] tooltip 内容は spec 003 通り（HH:MM-HH:MM / タイトル）

**Google event 詳細ジャンプ**
- [ ] Google event（`@google.com` 末尾）クリック → ブラウザで `/r/event?eid=...` の detail
- [ ] 繰り返しイベント（`_RYYYYMMDD...` 付き）でも該当 instance に到達
- [ ] 非 Google event → 今日のビュー fallback
- [ ] `calendarTitle` 空 → 今日のビュー fallback
- [ ] ヒットなし → 何も起きない

**既存挙動の維持**
- [ ] 中央 3 行 / 下部「次の予定」/ 針 / 円弧描画 / リング輪郭 / メニューバートグル / 右クリック終了 / wake / 分タイマーが無影響
- [ ] ホバー表示 / 円弧外で消える挙動が無影響

### コードレビュー

- `code-reviewer` agent で全体レビュー（依存方向 / 不要な抽象化 / dead code チェック）
