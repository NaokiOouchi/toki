# 029 — Event 個別色対応

参照: spec 002（Visual polish）の補完
ステータス: **完了**（2026-05-27、実機で colorId 反映確認済み）

Google Calendar の event 個別色（`colorId` 1-11）を Toki の円弧描画に反映する。
v1.0 リリース前にユーザー要望で追加（個別色 = 「自分が使うため」優先）。

## 1. 目的

- Google Calendar で event ごとに色を変えると、Toki の円弧色にも反映
- 色なし event は親カレンダー色（既存挙動）

## 2. Google Event Color Palette

API の `colorId`（1-11）と hex 色の対応（Google 公式 fixed palette）：

| colorId | 名前 | Hex |
|---|---|---|
| 1 | Lavender | #7986CB |
| 2 | Sage | #33B679 |
| 3 | Grape | #8E24AA |
| 4 | Flamingo | #E67C73 |
| 5 | Banana | #F6BF26 |
| 6 | Tangerine | #F4511E |
| 7 | Peacock | #039BE5 |
| 8 | Graphite | #616161 |
| 9 | Blueberry | #3F51B5 |
| 10 | Basil | #0B8043 |
| 11 | Tomato | #D50000 |

公式 `colors.get` API を呼ばず、固定値で実装（変更されることはほぼない）。

## 3. 実装

### 3.1 EventColorPalette.swift 新規作成

```swift
struct EventColorPalette {
    static func cgColor(forColorId id: String) -> CGColor? {
        // colorId → hex → CGColor
    }
}
```

### 3.2 GoogleAPIEvent に colorId 追加

```swift
let colorId: String?  // event JSON の "colorId"
```

### 3.3 parseEvent で colorId 取得

```swift
let colorId = item["colorId"] as? String
```

### 3.4 Event に eventColor 追加 + displayColor computed

```swift
let eventColor: CGColor?

var displayColor: CGColor {
    eventColor ?? calendarColor
}
```

### 3.5 GoogleCalendarGateway で colorId → eventColor 変換

```swift
let eventColor = apiEvent.colorId.flatMap { EventColorPalette.cgColor(forColorId: $0) }
```

### 3.6 RenderableEvent / EventArcRenderer で displayColor 使用

既存の `event.calendarColor` 参照箇所を `event.displayColor` に置換。

## 4. テスト

- `EventColorPaletteTests.swift`：colorId 1-11 すべてが正しい hex に変換されるか
- 不正な colorId（"99" 等）は nil

## 5. 完了条件

- [ ] EventColorPalette.swift 作成
- [ ] Event.swift に eventColor + displayColor 追加
- [ ] GoogleAPIEvent + parseEvent に colorId 追加
- [ ] GoogleCalendarGateway で変換
- [ ] RenderableEvent / EventArcRenderer 更新
- [ ] テスト追加
- [ ] swift build / swift test / xcodebuild build 通る
- [ ] 実機で個別色 event が反映される確認
