# 010 — event-preview: Tasks

参照: `specs/010-event-preview.md` / `specs/010-event-preview-plan.md`

合計: **11 tasks**

実装順序：上から順に。各 task は fresh subagent に渡して 1 commit ずつ。

新規 Domain 1 ファイル + 新規 UI 1 ファイル + 既存 10 ファイル編集。Domain テスト 36 ケース無変更で全 pass 維持。

---

## Task 1: Attendee / ResponseStatus を新規追加

**Commit**: `feat(domain): Attendee / ResponseStatus 値オブジェクトを新規追加`

**目的**: 参加者情報を表す Value Object と参加可否ステータス enum を Domain に追加。Foundation のみ依存、Equatable / Hashable 自動合成。

**実装**:

ファイル: `Sources/Toki/Domain/Attendee.swift`（新規）

```swift
import Foundation

/// イベント参加者を表す Value Object。
/// Google Calendar API の `attendees[]` 1 件分に相当。
/// `email` を実質 id として扱い、Hashable で Set 重複排除を可能にする。
struct Attendee: Equatable, Hashable {
    let email: String
    let displayName: String?
    let responseStatus: ResponseStatus

    /// 表示用名前。displayName 優先、無ければ email を返す。
    var displayLabel: String {
        if let name = displayName, !name.isEmpty { return name }
        return email
    }
}

/// 参加可否ステータス。Google API の `responseStatus` 文字列に対応。
/// 値：accepted / declined / tentative / needsAction / unknown。
enum ResponseStatus: String, Equatable {
    case accepted
    case declined
    case tentative
    case needsAction
    case unknown

    /// API 文字列から enum を解決する。nil / 未知値は `.unknown`。
    static func from(apiString: String?) -> ResponseStatus {
        guard let s = apiString else { return .unknown }
        return ResponseStatus(rawValue: s) ?? .unknown
    }
}
```

**完了条件**:
```bash
grep -n "struct Attendee" Sources/Toki/Domain/Attendee.swift
# → 1 件

grep -n "enum ResponseStatus" Sources/Toki/Domain/Attendee.swift
# → 1 件

grep -n "static func from(apiString:" Sources/Toki/Domain/Attendee.swift
# → 1 件

swift build  # 成功
swift test   # 36 ケース pass
```

**コミット**:
```bash
git add Sources/Toki/Domain/Attendee.swift
git commit -m "feat(domain): Attendee / ResponseStatus 値オブジェクトを新規追加"
```

**依存**: なし

---

## Task 2: Event に location / note / attendees / meetURL を追加

**Commit**: `feat(domain): Event に location / note / attendees / meetURL を追加`

**目的**: Domain `Event` に in-app preview に必要な 4 フィールドを追加。既存呼び出しはデフォルト引数で吸収、不変条件 / Equatable は維持。

**実装**:

ファイル: `Sources/Toki/Domain/Event.swift`（編集）

Read で現状確認後、`webURL` フィールドの直後に 4 フィールドを追加：

```swift
struct Event: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let calendarColor: CGColor
    /// Google Calendar API で取得した event detail URL（`htmlLink`）。
    let webURL: URL?
    /// 場所文字列（API の `location`）。
    let location: String?
    /// description（API の `description`、`CustomStringConvertible.description` 衝突回避で `note`）。
    let note: String?
    /// 参加者リスト。空配列は「参加者なし」、nil は使わない。
    let attendees: [Attendee]
    /// Meet URL（`hangoutLink` 優先、`conferenceData.entryPoints[type=video].uri` fallback）。
    let meetURL: URL?

    init?(id: String, title: String, start: Date, end: Date,
          calendarColor: CGColor,
          webURL: URL? = nil,
          location: String? = nil,
          note: String? = nil,
          attendees: [Attendee] = [],
          meetURL: URL? = nil) {
        guard !id.isEmpty, start < end else { return nil }
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.calendarColor = calendarColor
        self.webURL = webURL
        self.location = location
        self.note = note
        self.attendees = attendees
        self.meetURL = meetURL
    }
}
```

Equatable extension は無変更（id ベース維持）。

**完了条件**:
```bash
grep -n "let location: String?" Sources/Toki/Domain/Event.swift
grep -n "let note: String?" Sources/Toki/Domain/Event.swift
grep -n "let attendees: \[Attendee\]" Sources/Toki/Domain/Event.swift
grep -n "let meetURL: URL?" Sources/Toki/Domain/Event.swift
# → 各 1 件

swift build
swift test  # 36 ケース pass（既存呼び出しはデフォルト引数で吸収）
```

**コミット**:
```bash
git add Sources/Toki/Domain/Event.swift
git commit -m "feat(domain): Event に location / note / attendees / meetURL を追加"
```

**依存**: Task 1

---

## Task 3: DayTimeline.clip で新フィールド継承

**Commit**: `feat(domain): DayTimeline.clip で新フィールド継承`

**目的**: `clip(_:toDayOf:calendar:)` で日跨ぎ event を切り詰めた際も、新フィールド 4 つを失わず保持する。

**実装**:

ファイル: `Sources/Toki/Domain/DayTimeline.swift`（編集）

Read で `clip(_:toDayOf:calendar:)` を確認、内部の `Event(...)` 呼び出しに 4 引数を追加：

```swift
return Event(id: event.id,
             title: event.title,
             start: newStart,
             end: newEnd,
             calendarColor: event.calendarColor,
             webURL: event.webURL,
             location: event.location,
             note: event.note,
             attendees: event.attendees,
             meetURL: event.meetURL)
```

**完了条件**:
```bash
grep -nE "location: event\.location" Sources/Toki/Domain/DayTimeline.swift
grep -nE "note: event\.note" Sources/Toki/Domain/DayTimeline.swift
grep -nE "attendees: event\.attendees" Sources/Toki/Domain/DayTimeline.swift
grep -nE "meetURL: event\.meetURL" Sources/Toki/Domain/DayTimeline.swift
# → 各 1 件

swift build
swift test  # 36 ケース pass
```

**コミット**:
```bash
git add Sources/Toki/Domain/DayTimeline.swift
git commit -m "feat(domain): DayTimeline.clip で新フィールド継承"
```

**依存**: Task 2

---

## Task 4: Domain test helper の makeEvent に新引数を追加

**Commit**: `chore(test): Domain test helper の makeEvent に新引数を追加`

**目的**: 3 つのテストファイルの `makeEvent` ヘルパに `location` / `note` / `attendees` / `meetURL` をデフォルト引数で追加し、既存 36 ケースを無変更で pass 維持。

**実装**:

3 ファイルの `makeEvent` private helper にデフォルト引数を追加：

- `Tests/TokiTests/EventTests.swift`
- `Tests/TokiTests/EventStatusTests.swift`
- `Tests/TokiTests/DayTimelineTests.swift`

各ファイルの `makeEvent` シグネチャに以下を追加（順序は既存末尾）：

```swift
location: String? = nil,
note: String? = nil,
attendees: [Attendee] = [],
meetURL: URL? = nil
```

Event init 呼び出しにも対応した引数を渡す：

```swift
Event(id: ..., title: ..., start: ..., end: ...,
      calendarColor: ..., webURL: webURL,
      location: location, note: note,
      attendees: attendees, meetURL: meetURL)
```

既存ケース本体は触らない。

**完了条件**:
```bash
grep -c "location: String? = nil" Tests/TokiTests/EventTests.swift Tests/TokiTests/EventStatusTests.swift Tests/TokiTests/DayTimelineTests.swift
# → 各 1 件

swift build
swift test  # 36 ケース pass
```

**コミット**:
```bash
git add Tests/TokiTests/EventTests.swift Tests/TokiTests/EventStatusTests.swift Tests/TokiTests/DayTimelineTests.swift
git commit -m "chore(test): Domain test helper の makeEvent に新引数を追加"
```

**依存**: Task 2

---

## Task 5: GoogleAPIEvent / GoogleAPIAttendee を拡張、parseEvent で抽出

**Commit**: `feat(infra): GoogleAPIEvent / GoogleAPIAttendee を拡張、parseEvent で抽出`

**目的**: API レスポンスから `location` / `description` / `attendees` / `hangoutLink` / `conferenceData.entryPoints[type=video]` を抽出して中間型に保持。

**実装**:

ファイル: `Sources/Toki/Infrastructure/GoogleCalendarAPI.swift`（編集）

### Step 1: `GoogleAPIEvent` 拡張

既存 struct の末尾に 5 フィールド追加：

```swift
struct GoogleAPIEvent {
    // 既存
    let location: String?               // 新規
    let description: String?            // 新規（API 由来名、Domain では note にマップ）
    let attendees: [GoogleAPIAttendee]  // 新規
    let hangoutLink: URL?               // 新規
    let conferenceVideoURL: URL?        // 新規（conferenceData fallback）
}
```

### Step 2: 新規 `GoogleAPIAttendee` 中間型

```swift
struct GoogleAPIAttendee {
    let email: String
    let displayName: String?
    let responseStatus: String?  // raw 文字列、Domain 変換時に enum 化
}
```

### Step 3: `parseEvent` で抽出

既存 `parseEvent(_:calendar:)` 内に追加：

```swift
let location = item["location"] as? String
let description = item["description"] as? String
let hangoutLink = (item["hangoutLink"] as? String).flatMap { URL(string: $0) }

let attendeesRaw = (item["attendees"] as? [[String: Any]]) ?? []
let attendees: [GoogleAPIAttendee] = attendeesRaw.compactMap { dict in
    guard let email = dict["email"] as? String, !email.isEmpty else { return nil }
    return GoogleAPIAttendee(
        email: email,
        displayName: dict["displayName"] as? String,
        responseStatus: dict["responseStatus"] as? String
    )
}

// conferenceData.entryPoints[type=video].uri を fallback として抽出
let conferenceVideoURL: URL? = {
    guard let conf = item["conferenceData"] as? [String: Any],
          let entries = conf["entryPoints"] as? [[String: Any]] else { return nil }
    let videoEntry = entries.first { ($0["entryPointType"] as? String) == "video" }
    return (videoEntry?["uri"] as? String).flatMap { URL(string: $0) }
}()
```

`GoogleAPIEvent(...)` 呼び出しに 5 つの追加引数を渡す。

`parseEvent` が 50 行を超えそうなら、`parseAttendees(_:)` / `parseConferenceVideoURL(_:)` を private static helper として切り出す。

**完了条件**:
```bash
grep -n "let location: String?" Sources/Toki/Infrastructure/GoogleCalendarAPI.swift
grep -n "let attendees: \[GoogleAPIAttendee\]" Sources/Toki/Infrastructure/GoogleCalendarAPI.swift
grep -n "let hangoutLink: URL?" Sources/Toki/Infrastructure/GoogleCalendarAPI.swift
grep -n "let conferenceVideoURL: URL?" Sources/Toki/Infrastructure/GoogleCalendarAPI.swift
grep -n "struct GoogleAPIAttendee" Sources/Toki/Infrastructure/GoogleCalendarAPI.swift
grep -n "conferenceData" Sources/Toki/Infrastructure/GoogleCalendarAPI.swift
# → 各 1 件以上

swift build
swift test  # 36 ケース pass
```

**コミット**:
```bash
git add Sources/Toki/Infrastructure/GoogleCalendarAPI.swift
git commit -m "feat(infra): GoogleAPIEvent / GoogleAPIAttendee を拡張、parseEvent で抽出"
```

**依存**: なし（Domain には触らず Infrastructure 中間型のみ）

---

## Task 6: GoogleCalendarGateway.convert で新フィールドを Domain Event に詰める

**Commit**: `feat(infra): GoogleCalendarGateway.convert で新フィールドを Domain Event に詰める`

**目的**: `GoogleAPIEvent` → Domain `Event` 変換時に `location` / `note` / `attendees` / `meetURL` を設定。busy block 判定はそのまま、新フィールドは busy block でも valid なので伝播。

**実装**:

ファイル: `Sources/Toki/Infrastructure/GoogleCalendarGateway.swift`（編集）

Read で `convert(_:)` を確認、以下を追加：

```swift
private static func convert(_ ge: GoogleAPIEvent) -> (Event, Bool)? {
    let isAllDay = ge.start.dateTime == nil
    guard let start = ge.start.dateTime ?? ge.start.date,
          let end = ge.end.dateTime ?? ge.end.date else { return nil }
    let id = "\(ge.id)#\(start.timeIntervalSince1970)"

    // busy block 判定（既存）
    let busyTitles: Set<String> = ["予定あり", "Busy", ""]
    let trimmedSummary = ge.summary.trimmingCharacters(in: .whitespacesAndNewlines)
    let isBusyBlock = (ge.visibility == "private") || busyTitles.contains(trimmedSummary)
    let effectiveWebURL = isBusyBlock ? nil : ge.htmlLink

    // 新規：attendees 変換 / Meet URL 解決
    let attendees: [Attendee] = ge.attendees.map { a in
        Attendee(email: a.email,
                 displayName: a.displayName,
                 responseStatus: ResponseStatus.from(apiString: a.responseStatus))
    }
    let meetURL: URL? = ge.hangoutLink ?? ge.conferenceVideoURL

    guard let event = Event(id: id,
                            title: ge.summary,
                            start: start, end: end,
                            calendarColor: ge.calendarColor,
                            webURL: effectiveWebURL,
                            location: ge.location,
                            note: ge.description,
                            attendees: attendees,
                            meetURL: meetURL) else { return nil }
    return (event, isAllDay)
}
```

**完了条件**:
```bash
grep -n "ResponseStatus.from(apiString:" Sources/Toki/Infrastructure/GoogleCalendarGateway.swift
grep -n "let meetURL: URL?" Sources/Toki/Infrastructure/GoogleCalendarGateway.swift
grep -n "location: ge.location" Sources/Toki/Infrastructure/GoogleCalendarGateway.swift
grep -n "note: ge.description" Sources/Toki/Infrastructure/GoogleCalendarGateway.swift
# → 各 1 件以上

swift build
swift test  # 36 ケース pass
```

**コミット**:
```bash
git add Sources/Toki/Infrastructure/GoogleCalendarGateway.swift
git commit -m "feat(infra): GoogleCalendarGateway.convert で新フィールドを Domain Event に詰める"
```

**依存**: Task 1, 2, 5

---

## Task 7: RenderableEvent に新フィールド伝播 + ClockViewModel.canvasEvents 更新

**Commit**: `feat(ui): RenderableEvent に新フィールド伝播 + ClockViewModel.canvasEvents 更新`

**目的**: Popover が必要とするフィールドを UI 層まで伝播する。RenderableEvent struct に 4 フィールド追加 + canvasEvents で詰める。

**実装**:

### ファイル 1: `Sources/Toki/UI/RenderableEvent.swift`（編集）

```swift
struct RenderableEvent: Identifiable {
    // 既存
    let location: String?      // 新規
    let note: String?          // 新規
    let attendees: [Attendee]  // 新規
    let meetURL: URL?          // 新規
}
```

Equatable は引き続き id ベース、自動合成。

### ファイル 2: `Sources/Toki/Composition/ClockViewModel.swift`（編集）

`canvasEvents` の `RenderableEvent(...)` 初期化に 4 引数追加：

```swift
RenderableEvent(
    id: ev.id, title: ev.title,
    startAngle: ..., endAngle: ...,
    color: ev.calendarColor,
    status: ev.status(at: now),
    start: ev.start, end: ev.end,
    webURL: ev.webURL,
    location: ev.location,    // 新規
    note: ev.note,            // 新規
    attendees: ev.attendees,  // 新規
    meetURL: ev.meetURL       // 新規
)
```

**完了条件**:
```bash
grep -n "let location: String?" Sources/Toki/UI/RenderableEvent.swift
grep -n "let attendees: \[Attendee\]" Sources/Toki/UI/RenderableEvent.swift
grep -n "let meetURL: URL?" Sources/Toki/UI/RenderableEvent.swift
grep -n "note: ev.note" Sources/Toki/Composition/ClockViewModel.swift
# → 各 1 件以上

swift build
swift test  # 36 ケース pass
./scripts/build-app.sh
```

**コミット**:
```bash
git add Sources/Toki/UI/RenderableEvent.swift Sources/Toki/Composition/ClockViewModel.swift
git commit -m "feat(ui): RenderableEvent に新フィールド伝播 + ClockViewModel.canvasEvents 更新"
```

**依存**: Task 2, 6

---

## Task 8: EventPreviewPopover を新規追加

**Commit**: `feat(ui): EventPreviewPopover を新規追加`

**目的**: popover overlay 本体の純粋 presentation View を新規追加。整形済みデータとアクションコールバックを受け取り、Liquid Glass 背景で描画する。

**実装**:

ファイル: `Sources/Toki/UI/EventPreviewPopover.swift`（新規）

```swift
import SwiftUI

/// 円弧クリック時に表示される event 詳細 popover の presentation View。
/// 整形済み文字列とアクションコールバックを受け取り描画のみ行う（純粋 View）。
struct EventPreviewPopover: View {
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

    /// 参加者表示の上限。超過分は「他 N 名」表示。
    private static let attendeeDisplayLimit = 5

    /// note の最大文字数 / 行数。超過時は省略 `...`。
    private static let noteMaxChars = 200
    private static let noteMaxLines = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            titleSection
            if let location, !location.isEmpty { locationSection(location) }
            if !attendees.isEmpty { attendeesSection }
            if let note, !note.isEmpty { noteSection(note) }
            actionButtons
        }
        .padding(12)
        .frame(minWidth: 200, idealWidth: 280, maxWidth: 400,
               minHeight: 140, maxHeight: 500, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .tokiGlassBackground(cornerRadius: 12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
    }

    private var header: some View {
        HStack {
            Text(timeLabel)
                .font(.system(size: 11 * textScale))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14 * textScale))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
    }

    private var titleSection: some View {
        Text(title)
            .font(.system(size: 13 * textScale, weight: .medium))
            .lineLimit(2)
            .truncationMode(.tail)
    }

    private func locationSection(_ location: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 10 * textScale))
                .foregroundStyle(.secondary)
            Text(location)
                .font(.system(size: 11 * textScale))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var attendeesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("参加者")
                .font(.system(size: 10 * textScale))
                .foregroundStyle(.tertiary)
            ForEach(Array(attendees.prefix(Self.attendeeDisplayLimit).enumerated()), id: \.offset) { _, attendee in
                HStack(spacing: 4) {
                    Image(systemName: Self.statusSymbolName(attendee.responseStatus))
                        .font(.system(size: 10 * textScale))
                        .foregroundStyle(.secondary)
                    Text(attendee.displayLabel)
                        .font(.system(size: 11 * textScale))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            if attendees.count > Self.attendeeDisplayLimit {
                Text("他 \(attendees.count - Self.attendeeDisplayLimit) 名")
                    .font(.system(size: 10 * textScale))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func noteSection(_ note: String) -> some View {
        Text(Self.truncatedNote(note))
            .font(.system(size: 11 * textScale))
            .foregroundStyle(.secondary)
            .lineLimit(Self.noteMaxLines)
            .truncationMode(.tail)
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if hasMeetURL {
                Button(action: onOpenMeet) {
                    Label("Meet で開く", systemImage: "video.fill")
                        .font(.system(size: 11 * textScale))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if hasCalendarURL {
                Button(action: onOpenCalendar) {
                    Label("Calendar で開く", systemImage: "calendar")
                        .font(.system(size: 11 * textScale))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Spacer()
        }
    }

    /// 200 文字 / 3 行で note をトリム。
    private static func truncatedNote(_ text: String) -> String {
        if text.count <= noteMaxChars { return text }
        let endIndex = text.index(text.startIndex, offsetBy: noteMaxChars)
        return String(text[..<endIndex]) + "…"
    }

    /// ResponseStatus に対応する SF Symbol 名。
    private static func statusSymbolName(_ status: ResponseStatus) -> String {
        switch status {
        case .accepted: return "checkmark.circle.fill"
        case .declined: return "xmark.circle.fill"
        case .tentative: return "questionmark.circle.fill"
        case .needsAction, .unknown: return "circle"
        }
    }
}
```

**完了条件**:
```bash
grep -n "struct EventPreviewPopover" Sources/Toki/UI/EventPreviewPopover.swift
grep -n "var onOpenMeet" Sources/Toki/UI/EventPreviewPopover.swift
grep -n "keyboardShortcut(.escape" Sources/Toki/UI/EventPreviewPopover.swift
grep -n "tokiGlassBackground" Sources/Toki/UI/EventPreviewPopover.swift
# → 各 1 件以上

# ファイル長 < 200 行
wc -l Sources/Toki/UI/EventPreviewPopover.swift

swift build
swift test  # 36 ケース pass
```

**コミット**:
```bash
git add Sources/Toki/UI/EventPreviewPopover.swift
git commit -m "feat(ui): EventPreviewPopover を新規追加"
```

**依存**: Task 1, 7

---

## Task 9: ClockViewModel.handleArcTap を popover 表示に変更 + close/openMeet/openCalendar

**Commit**: `feat(composition): ClockViewModel.handleArcTap を popover 表示に変更 + close/openMeet/openCalendar`

**目的**: 既存のブラウザ即起動を popover 表示に切り替え、busy block 時の今日ビュー fallback は維持。アクションコールバック（Meet / Calendar 起動 + 自動 close）を追加。

**実装**:

ファイル: `Sources/Toki/Composition/ClockViewModel.swift`（編集）

### Step 1: @Published 追加

`hoveredTooltip` の近くに：

```swift
/// 円弧クリックで表示される event preview popover の対象 event。
/// nil で popover 非表示。背景クリック / ESC / × ボタン / アクション後に closePreview で nil に戻す。
@Published private(set) var previewedEvent: RenderableEvent? = nil
```

### Step 2: `handleArcTap` 改修

```swift
func handleArcTap(at point: CGPoint, geometry: ClockGeometry) {
    guard let event = hitTest(point: point, events: canvasEvents, geometry: geometry) else { return }
    hoveredTooltip = nil
    if event.webURL != nil {
        // webURL あり：popover を開く（busy block 以外）
        previewedEvent = event
    } else {
        // busy block：今日のビュー fallback（既存挙動）
        guard let dayURL = URL(string: Self.googleCalendarDayURL(for: event.start, calendar: calendar)) else { return }
        NSWorkspace.shared.open(dayURL)
    }
}
```

### Step 3: 新規メソッド 3 つ + computed property

```swift
/// popover を閉じる。背景クリック / ESC / × ボタン / アクションボタン押下後に呼ばれる。
func closePreview() {
    previewedEvent = nil
}

/// "Meet で開く" アクション。meetURL を NSWorkspace で開いて popover を閉じる。
func openMeet() {
    guard let url = previewedEvent?.meetURL else { return }
    NSWorkspace.shared.open(url)
    closePreview()
}

/// "Calendar で開く" アクション。webURL を NSWorkspace で開いて popover を閉じる。
func openCalendarURL() {
    guard let url = previewedEvent?.webURL else { return }
    NSWorkspace.shared.open(url)
    closePreview()
}

/// popover ヘッダーに表示する時刻範囲文字列 "HH:MM - HH:MM"。
var previewTimeLabel: String? {
    guard let ev = previewedEvent else { return nil }
    return Self.formatTimeRange(ev.start, ev.end, calendar: calendar)
}
```

`formatTimeRange` の visibility は必要に応じて `private static` のまま OK（同 class 内呼び出し）。

**完了条件**:
```bash
grep -n "@Published private(set) var previewedEvent" Sources/Toki/Composition/ClockViewModel.swift
grep -n "func closePreview" Sources/Toki/Composition/ClockViewModel.swift
grep -n "func openMeet" Sources/Toki/Composition/ClockViewModel.swift
grep -n "func openCalendarURL" Sources/Toki/Composition/ClockViewModel.swift
grep -n "var previewTimeLabel" Sources/Toki/Composition/ClockViewModel.swift
# → 各 1 件

# handleArcTap が popover 表示に変わってる
grep -nA 3 "func handleArcTap" Sources/Toki/Composition/ClockViewModel.swift | grep "previewedEvent = event"
# → 1 件

swift build
swift test  # 36 ケース pass
```

**コミット**:
```bash
git add Sources/Toki/Composition/ClockViewModel.swift
git commit -m "feat(composition): ClockViewModel.handleArcTap を popover 表示に変更 + close/openMeet/openCalendar"
```

**依存**: Task 7

---

## Task 10: ClockView に popover overlay + 透明 backdrop + ESC 配線

**Commit**: `feat(ui): ClockView に popover overlay + 透明 backdrop + ESC 配線`

**目的**: ViewModel の `previewedEvent` を購読し、popover overlay と透明 backdrop を ClockView の ZStack に追加。背景クリック / × ボタン / ESC で close。

**実装**:

ファイル: `Sources/Toki/UI/ClockView.swift`（編集）

Read で現状の overlay 配置を確認、tooltip overlay の **直前** に popover overlay を追加：

```swift
// popover 表示中：透明 backdrop（外側クリックで close）+ popover 本体
if let preview = viewModel.previewedEvent {
    // 透明 backdrop。allowsHitTesting(true) で外側クリックを拾う
    Color.clear
        .contentShape(Rectangle())
        .onTapGesture { viewModel.closePreview() }
    
    // popover 本体。位置計算は Task 11 で精緻化、ここでは仮の中央配置
    EventPreviewPopover(
        timeLabel: viewModel.previewTimeLabel ?? "",
        title: preview.title,
        location: preview.location,
        attendees: preview.attendees,
        note: preview.note,
        hasMeetURL: preview.meetURL != nil,
        hasCalendarURL: preview.webURL != nil,
        textScale: textScale.factor,
        onOpenMeet: { viewModel.openMeet() },
        onOpenCalendar: { viewModel.openCalendarURL() },
        onClose: { viewModel.closePreview() }
    )
    .transaction { $0.animation = nil }
}
```

位置計算は Task 11 で `previewDisplayPosition(for:)` を追加して `.offset` で配置。本 task では中央 or 仮位置で OK（動作確認重視）。

tooltip overlay は既存通り、popover の **上** に重ねる（最前面）か **下** に置くかは UX 判断：
- popover 表示中はホバー tooltip 抑止が綺麗 → ViewModel 側で `hoveredTooltip = nil` を `handleArcTap` で実施済み
- もし popover 表示中の hover が tooltip を出してしまう場合は、ClockView 側で `if viewModel.previewedEvent == nil` ガードを追加

**完了条件**:
```bash
grep -n "viewModel.previewedEvent" Sources/Toki/UI/ClockView.swift
grep -n "EventPreviewPopover(" Sources/Toki/UI/ClockView.swift
grep -n "viewModel.closePreview" Sources/Toki/UI/ClockView.swift
# → 各 1 件以上

swift build
swift test  # 36 ケース pass
./scripts/build-app.sh
```

実機目視（test では確認不能）：
- 円弧クリックで popover が表示される
- 外側クリックで popover 閉じる
- × ボタンクリックで popover 閉じる
- ESC キーで popover 閉じる
- busy block クリックで popover 出ず今日ビュー fallback

**コミット**:
```bash
git add Sources/Toki/UI/ClockView.swift
git commit -m "feat(ui): ClockView に popover overlay + 透明 backdrop + ESC 配線"
```

**依存**: Task 8, 9

---

## Task 11: popover サイズ / 位置計算（min/max クランプ、画面端反転）

**Commit**: `feat(ui): popover サイズ / 位置計算（min/max クランプ、画面端反転）`

**目的**: popover をクリックされた円弧の位置近くに表示し、画面端にはみ出る場合は反転 / クランプする。tooltip と同じ流儀を継承。

**実装**:

ファイル: `Sources/Toki/UI/ClockView.swift`（編集）

### Step 1: ViewModel 側で click 位置を保持

`ClockViewModel` に：

```swift
/// 直近のクリック位置（popover 配置基準）。
@Published private(set) var lastTapLocation: CGPoint? = nil
```

`handleArcTap` 冒頭に `lastTapLocation = point` を追加。`closePreview` で nil に戻す。

### Step 2: ClockView extension に位置計算 helper 追加

既存の `tooltipDisplayPosition(for:)` の近くに：

```swift
extension ClockView {
    /// popover 想定サイズ（最大）。EventPreviewPopover の maxWidth / 一般的な高さに合わせる。
    private static let popoverWidth: CGFloat = 280
    private static let popoverHeight: CGFloat = 280
    private static let popoverOffset: CGFloat = 8

    /// ホバー位置から popover を描画する左上座標を計算する。
    /// X/Y 軸独立に判定：右端/下端を超える側だけ反転、左/上端は 0 にクランプ。
    /// canvas / window のサイズは tooltipDisplayPosition と同じ定数を流用（spec 011 で動的化候補）。
    static func popoverDisplayPosition(for tap: CGPoint) -> CGPoint {
        let x: CGFloat = (tap.x + popoverOffset + popoverWidth > canvasWidth)
            ? max(0, tap.x - popoverOffset - popoverWidth)
            : tap.x + popoverOffset
        let y: CGFloat = (tap.y + popoverOffset + popoverHeight > windowHeight)
            ? max(0, tap.y - popoverOffset - popoverHeight)
            : tap.y + popoverOffset
        return CGPoint(x: x, y: y)
    }
}
```

### Step 3: body で `.offset` 適用

```swift
if let preview = viewModel.previewedEvent {
    Color.clear
        .contentShape(Rectangle())
        .onTapGesture { viewModel.closePreview() }
    
    let tap = viewModel.lastTapLocation ?? CGPoint(x: 140, y: 140)
    let position = Self.popoverDisplayPosition(for: tap)
    
    EventPreviewPopover(...)
        .offset(x: position.x, y: position.y)
        .transaction { $0.animation = nil }
}
```

**完了条件**:
```bash
grep -n "popoverDisplayPosition" Sources/Toki/UI/ClockView.swift
grep -n "lastTapLocation" Sources/Toki/Composition/ClockViewModel.swift
# → 各 2 件以上（定義 + 利用）

swift build
swift test  # 36 ケース pass
./scripts/build-app.sh
```

実機目視：
- 円弧の位置に応じて popover が表示される
- 右端の event クリックで popover が左に反転表示
- 下端の event クリックで popover が上に反転表示
- リサイズ後の表示位置はある程度ズレる可能性あり（spec 011 候補）

**コミット**:
```bash
git add Sources/Toki/UI/ClockView.swift Sources/Toki/Composition/ClockViewModel.swift
git commit -m "feat(ui): popover サイズ / 位置計算（min/max クランプ、画面端反転）"
```

**依存**: Task 10

---

## 全 task 完了後

### 回帰確認

- [ ] `swift test`：Domain 36 ケース全 pass
- [ ] `./scripts/build-app.sh && open .build/Toki.app`：実機目視で spec 010 §AC walkthrough

### 手動チェックリスト（spec 010 plan §12 ベース）

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
| 9 | note 200 文字超 | 省略 `…` |
| 10 | Meet ボタン（meetURL 有り）| URL 起動 + popover 閉じる |
| 11 | Meet ボタン（meetURL 無し）| ボタン非表示 |
| 12 | Calendar ボタン | webURL 起動 + popover 閉じる |
| 13 | Liquid Glass / Material fallback | 適切に切替 |
| 14 | textScale 反映 | 文字サイズ追従 |
| 15 | ホバーツールチップ | 無変更 |
| 16 | 既存 UI（中央 / 下部 / 設定 / メニュー）| 無変更 |

### コードレビュー（任意）

- `code-reviewer` agent で spec 010 全体レビュー
