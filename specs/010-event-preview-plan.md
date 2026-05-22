# 010 — In-app event preview 技術プラン

`specs/010-event-preview.md` を技術プランに展開したもの。`/tasks` で atomic task に分解する元となる。

## 0. 確定済み設計判断

13 項目すべて [CONFIDENT]：

1. **popover 実装方式**：カスタム overlay（tooltip 流儀）。Canvas クリック起点で anchor view 無し
2. **背景クリック検出**：透明 backdrop View + `.onTapGesture`
3. **ESC キー検出**：popover 内 close button に `.keyboardShortcut(.escape)`
4. **popover サイズ**：内容可変、min 200x140 / max 400x500
5. **参加者表示数**：5 名 + 「他 N 名」
6. **description 長さ**：3 行 or 200 文字、いずれか早い方
7. **過去 event の preview 表示**：全 status で表示
8. **status アイコン**：SF Symbol + 文字ラベル、操作なし（read-only）
9. **Attendee Equatable / id**：email を実質 id、`struct Hashable`
10. **空 attendees**：常に配列、空配列は「参加者なし」、Optional 避ける
11. **Domain プロパティ名**：`note`（`description` 衝突回避）
12. **Meet URL 取得**：`hangoutLink` 優先、`conferenceData.entryPoints[type=video].uri` fallback
13. **API レスポンスサイズ**：現状 2 分ポーリングで OK、`fields` 絞り込みは Phase 3

## 1. Requirements restatement

円弧クリック時の挙動を「ブラウザで Google Calendar event detail を開く」から「アプリ内 popover overlay で詳細を即時表示」に置き換える。popover では時刻範囲 / タイトル / 場所 / 参加者 / note を一覧でき、Meet ボタンと Google Calendar で開くボタンから明示的にブラウザ遷移できる。Domain `Event` に `location` / `note` / `attendees` / `meetURL` 4 フィールドを追加し、`Attendee` / `ResponseStatus` を新規 Value Object として導入。Liquid Glass + textScale 反映、外側クリック / ESC / × ボタンで閉じる。busy block（`webURL == nil`）は従来通り今日ビュー fallback。

## 2. Open Questions — 解決済み

| # | 論点 | 確定値 |
|---|---|---|
| 1 | popover 実装方式 | カスタム overlay（tooltip 流儀） |
| 2 | 背景クリック検出 | 透明 backdrop View + `.onTapGesture` |
| 3 | ESC キー検出 | popover 内 close button に `.keyboardShortcut(.escape)` |
| 4 | popover サイズ | 内容可変、min 200x140 / max 400x500 |
| 5 | 参加者表示数 | 5 名 +「他 N 名」 |
| 6 | description 長さ | 3 行 or 200 文字、いずれか早い方 |
| 7 | 過去 event の preview 表示 | 全 status で表示 |
| 8 | status アイコン | SF Symbol + 文字ラベル、操作なし |
| 9 | Attendee Equatable / id | email を実質 id、`struct Hashable` |
| 10 | 空 attendees | 常に配列、空配列は「参加者なし」 |
| 11 | Domain プロパティ名 | `note` |
| 12 | Meet URL 取得 | `hangoutLink` 優先、`conferenceData` fallback |
| 13 | API レスポンスサイズ | 現状 OK、絞り込みは Phase 3 |

## 3. ファイル別変更計画

### 新規（2 ファイル）
| パス | 概要 | 想定行数 |
|---|---|---|
| `Sources/Toki/Domain/Attendee.swift` | `Attendee` struct + `ResponseStatus` enum | 35 |
| `Sources/Toki/UI/EventPreviewPopover.swift` | popover 本体 View | 180 |

### 編集
| パス | 変更概要 | 想定差分 |
|---|---|---|
| `Sources/Toki/Domain/Event.swift` | 4 フィールド追加 + init 拡張 | +12/-2 |
| `Sources/Toki/Domain/DayTimeline.swift` | `clip` で新フィールド継承 | +4 |
| `Sources/Toki/Infrastructure/GoogleCalendarAPI.swift` | GoogleAPIEvent / GoogleAPIAttendee 拡張、parseEvent 拡張 | +60 |
| `Sources/Toki/Infrastructure/GoogleCalendarGateway.swift` | convert で新フィールド設定 | +25 |
| `Sources/Toki/UI/RenderableEvent.swift` | 4 フィールド伝播 | +8 |
| `Sources/Toki/Composition/ClockViewModel.swift` | `@Published previewedEvent`、handleArcTap 改修、closePreview / openMeet / openCalendarURL / previewTimeLabel 追加、canvasEvents 拡張 | +35/-3 |
| `Sources/Toki/UI/ClockView.swift` | popover overlay + 透明 backdrop + ESC 配線 | +50 |
| `Tests/TokiTests/EventTests.swift` | makeEvent ヘルパに引数追加 | +5/-1 |
| `Tests/TokiTests/EventStatusTests.swift` | 同上 | +3/-1 |
| `Tests/TokiTests/DayTimelineTests.swift` | 同上 | +5/-1 |

合計：**新規 2 / 編集 10 / 計 12 ファイル**

## 4. Domain 拡張詳細

### 4.1 新規 `Attendee` / `ResponseStatus`

```swift
struct Attendee: Equatable, Hashable {
    let email: String
    let displayName: String?
    let responseStatus: ResponseStatus

    var displayLabel: String {
        if let name = displayName, !name.isEmpty { return name }
        return email
    }
}

enum ResponseStatus: String, Equatable {
    case accepted, declined, tentative, needsAction, unknown

    static func from(apiString: String?) -> ResponseStatus {
        guard let s = apiString else { return .unknown }
        return ResponseStatus(rawValue: s) ?? .unknown
    }
}
```

### 4.2 `Event` 拡張

`location: String?` / `note: String?` / `attendees: [Attendee]` / `meetURL: URL?` を追加。init signature に**デフォルト引数**として追加（既存呼び出し無影響）。不変条件 / Equatable は維持。

### 4.3 `DayTimeline.clip` 拡張

clip で日跨ぎ event を切り詰めた際も新フィールドを保持：

```swift
return Event(id: event.id, title: event.title,
             start: newStart, end: newEnd,
             calendarColor: event.calendarColor,
             webURL: event.webURL,
             location: event.location,
             note: event.note,
             attendees: event.attendees,
             meetURL: event.meetURL)
```

## 5. Infrastructure 拡張詳細

### 5.1 `GoogleAPIEvent` 拡張
```swift
struct GoogleAPIEvent {
    // 既存
    let location: String?
    let description: String?  // API は description、Domain では note にマップ
    let attendees: [GoogleAPIAttendee]
    let hangoutLink: URL?
    let conferenceVideoURL: URL?
}

struct GoogleAPIAttendee {
    let email: String
    let displayName: String?
    let responseStatus: String?
}
```

### 5.2 `parseEvent` 拡張
- `location` / `description` を String? として抽出
- `attendees` 配列をパース（空 email は除外）
- `hangoutLink` を URL に変換
- `conferenceData.entryPoints` から `type=video` を抽出して `conferenceVideoURL` に格納

### 5.3 `GoogleCalendarGateway.convert` 拡張
- `GoogleAPIAttendee` → `Attendee` 変換（`ResponseStatus.from(apiString:)` 使用）
- `meetURL` = `hangoutLink ?? conferenceVideoURL`
- 既存 busy block 判定はそのまま、新フィールドは busy block でも詰める（情報自体は valid）

## 6. UI 拡張詳細

### 6.1 新規 `EventPreviewPopover`

責務：純粋 presentation View。整形済み文字列とアクションコールバックを受け取り描画のみ。

入力：
```swift
let timeLabel: String           // "14:00 - 15:00"
let title: String
let location: String?
let attendees: [Attendee]
let note: String?
let hasMeetURL: Bool
let hasCalendarURL: Bool
var textScale: CGFloat = 1.0

let onOpenMeet: () -> Void
let onOpenCalendar: () -> Void
let onClose: () -> Void
```

レイアウト（VStack alignment .leading, spacing 8）：
1. ヘッダー行：時刻 + spacer + × ボタン
2. タイトル（最大 2 行、13 * scale, .medium）
3. 場所行（SF Symbol `mappin.and.ellipse` + 1 行、11 * scale, secondary）
4. 参加者セクション（先頭 5 名 + 「他 N 名」、status SF Symbol 付き）
5. note セクション（200 文字 / 3 行でトリム）
6. アクションボタン Row（Meet / Calendar、`hasMeetURL` / `hasCalendarURL` で表示制御）

サイズ：`frame(minWidth: 200, maxWidth: 400, minHeight: 140, maxHeight: 500)` + `fixedSize(horizontal: false, vertical: true)`

スタイル：`.padding(12)` → `.tokiGlassBackground(cornerRadius: 12)` → border stroke → shadow

ESC：× ボタンに `.keyboardShortcut(.escape, modifiers: [])`

status アイコン：
- `.accepted` → "checkmark.circle.fill"
- `.declined` → "xmark.circle.fill"
- `.tentative` → "questionmark.circle.fill"
- `.needsAction` / `.unknown` → "circle"

ファイル長 < 200 行を目指す。`body` 内 sub-view は computed property に分割（`header` / `attendeesSection` / `actionButtons`）。

### 6.2 `ClockView` overlay

既存 tooltip overlay の直後に popover overlay を追加：

```swift
if let preview = viewModel.previewedEvent {
    // 透明 backdrop（外側クリックで close）
    Color.clear
        .contentShape(Rectangle())
        .onTapGesture { viewModel.closePreview() }
    
    // popover 本体
    let position = Self.previewDisplayPosition(...)
    EventPreviewPopover(...)
        .offset(...)
}
```

位置計算は tooltip と同じ流儀（右端 / 下端で反転、左 / 上で 0 クランプ）。constants は spec 008 由来の固定 280x320 を流用（spec 011 候補で動的化）。

### 6.3 `RenderableEvent` 拡張

`location` / `note` / `attendees` / `meetURL` を追加。`ClockViewModel.canvasEvents` で詰める。

## 7. Composition 詳細

### 7.1 `ClockViewModel` 拡張

```swift
@Published private(set) var previewedEvent: RenderableEvent? = nil

func handleArcTap(at point: CGPoint, geometry: ClockGeometry) {
    guard let event = hitTest(point: point, events: canvasEvents, geometry: geometry) else { return }
    hoveredTooltip = nil
    if event.webURL != nil {
        previewedEvent = event
    } else {
        guard let dayURL = URL(string: Self.googleCalendarDayURL(for: event.start, calendar: calendar)) else { return }
        NSWorkspace.shared.open(dayURL)
    }
}

func closePreview() { previewedEvent = nil }

func openMeet() {
    guard let url = previewedEvent?.meetURL else { return }
    NSWorkspace.shared.open(url)
    closePreview()
}

func openCalendarURL() {
    guard let url = previewedEvent?.webURL else { return }
    NSWorkspace.shared.open(url)
    closePreview()
}

var previewTimeLabel: String? {
    guard let ev = previewedEvent else { return nil }
    return Self.formatTimeRange(ev.start, ev.end, calendar: calendar)
}
```

別の円弧クリック → `previewedEvent` 上書きで自然に置換。

## 8. 実装フェーズ順序

**11 タスク**：

1. `feat(domain): Attendee / ResponseStatus 値オブジェクトを新規追加`
2. `feat(domain): Event に location / note / attendees / meetURL を追加`
3. `feat(domain): DayTimeline.clip で新フィールド継承`
4. `chore(test): Domain test helper の makeEvent に新引数を追加`
5. `feat(infra): GoogleAPIEvent / GoogleAPIAttendee を拡張、parseEvent で抽出`
6. `feat(infra): GoogleCalendarGateway.convert で新フィールドを Domain Event に詰める`
7. `feat(ui): RenderableEvent に新フィールド伝播 + ClockViewModel.canvasEvents 更新`
8. `feat(ui): EventPreviewPopover を新規追加`
9. `feat(composition): ClockViewModel.handleArcTap を popover 表示に変更 + close/openMeet/openCalendar`
10. `feat(ui): ClockView に popover overlay + 透明 backdrop + ESC 配線`
11. `feat(ui): popover サイズ / 位置計算（min/max クランプ、画面端反転）`

依存：Task 1 → 2 → 3 / 4 → 5 → 6 → 7 → 8 / 9 → 10 → 11

## 9. リスク

| # | リスク | 重大度 | 緩和策 |
|---|---|---|---|
| R1 | popover overlay と tooltip overlay の hit-testing 競合 | Medium | 透明 backdrop は popover の後ろ、`allowsHitTesting(true)`。tooltip は既存通り `allowsHitTesting(false)` |
| R2 | ESC キーが popover 内ボタンにフォーカスないと反応しない | Medium | `.keyboardShortcut(.escape)` で発火、必要なら `.focusable(true)` を popover ルートに追加 |
| R3 | 多数 attendees でレイアウト崩れ | Low | 5 名上限 + maxHeight 500 クランプ |
| R4 | `hangoutLink` / `conferenceData` 両方無し | Low | `meetURL = nil` → Meet ボタン非表示で degrade |
| R5 | Domain テスト 36 ケース全 pass | Low | Task 4 でヘルパに新引数追加（デフォルト値）で吸収 |
| R6 | 固定 canvas 280x320 ベースの位置計算が rsize 時にズレる | Medium | spec 011 候補として残置、本 spec では tooltip と同じ妥協 |
| R7 | Liquid Glass の popover 内部レイアウトで material 干渉 | Low | EventTooltip と同じ stroke + shadow パターン踏襲 |
| R8 | description 衝突 | Low | `note` で解決済み |
| R9 | popover 表示中の再描画チラつき | Low | RenderableEvent.id ベース Equatable で no-op、必要なら `transaction { $0.animation = nil }` |
| R10 | popover 表示中の他円弧ホバー tooltip 同時表示 | Low | 現状許容（spec 010 §Non-goals に明示なし） |

## 10. テスト方針

### 自動
- Domain 36 ケース無変更で全 pass
- 新規 Domain テスト追加なし（自動合成 Equatable で挙動単純）

### 手動チェックリスト
| # | 項目 | 期待 |
|---|---|---|
| 1 | 円弧クリック（webURL 有り）| popover 表示 |
| 2 | 円弧クリック（busy block）| popover 出ず今日ビュー fallback |
| 3 | 外側クリック | popover 閉じる |
| 4 | ESC キー | popover 閉じる |
| 5 | × ボタン | popover 閉じる |
| 6 | 別円弧クリック | 新 event の popover に置換 |
| 7 | 時刻 / タイトル / 場所 / 参加者 / note 表示 | 期待通り |
| 8 | attendees 6 名超 | 「他 N 名」表示 |
| 9 | note 200 文字超 | 省略 `...` |
| 10 | Meet ボタン（meetURL 有り）| URL 起動 + popover 閉じる |
| 11 | Meet ボタン（meetURL 無し）| ボタン非表示 |
| 12 | Calendar ボタン | webURL 起動 + popover 閉じる |
| 13 | Liquid Glass / Material fallback | 適切に切替 |
| 14 | textScale 反映 | 文字サイズ追従 |
| 15 | ホバーツールチップ | 無変更 |
| 16 | 既存 UI（中央 / 下部 / 設定 / メニュー）| 無変更 |

## 11. Out of scope

spec 010 §Non-goals 再掲：
- 参加可否操作（write scope 昇格、Phase 3）
- リッチテキスト / 添付 / 通知 / 編集（Phase 3）
- 複数日 navigation / 重なり 2 段 / LaunchAtLogin / 複数アカウント（別 spec）
- 編集機能（CLAUDE.md 禁止）
- popover 位置記憶
- Meet URL 埋め込み表示
- ClockView 定数集約（spec 011 候補）
- `Attendee` Domain テストケース追加

## 参考ファイル

- `specs/010-event-preview.md`
- `specs/008-ux-refresh-and-window-plan.md`

次のステップ：`/tasks 010-event-preview` で 11 atomic task ファイル化 → fresh subagent で 1 commit ずつ実装。
