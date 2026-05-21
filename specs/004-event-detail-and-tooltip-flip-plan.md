# 004 — Google Calendar イベント詳細ジャンプとツールチップ自動反転 技術プラン

`specs/004-event-detail-and-tooltip-flip.md` を技術プランに展開したもの。`/tasks` で atomic task に分解する元となる。

## 0. 確定済み設計判断

ユーザーとの合意事項：

1. **両課題（tooltip 見切れ + 詳細ジャンプ）を spec 004 でまとめて対応**
2. **詳細ジャンプは Google event のみ**：`@google.com` 厳密一致、それ以外は今日のビュー fallback
3. **`eid` 形式**：`base64("<base_uid> <calendar_email>")`、URL-safe、`=` 除去
4. **tooltip 反転**：右端/下端で独立判定、左端/上端は `max(0, ...)` でクランプ
5. **Domain `Event.calendarTitle: String`**（必須非 nil、空文字列許容、Equatable は id ベース維持）
6. **想定 tooltip サイズ固定**：200pt × 40pt、反転オフセット対称 `(-8, -8)`
7. **Domain テスト**：ヘルパに `calendarTitle: String = ""` デフォルト引数追加で 36 ケース無変更 pass
8. **SPEC.md 整合タスク（Task 6）を含める**

## 1. Requirements restatement

spec 003 の実機検証で顕在化した 2 課題に同一 iteration で対応：

1. **ツールチップ自動反転**：右端で `hover_x + 8 + 200 > 280` なら左側へ、下端で `hover_y + 8 + 40 > 320` なら上側へ。X/Y 独立判定、左上は 0 クランプ
2. **Google event 詳細ジャンプ**：`@google.com` 末尾 + `calendarTitle` 非空 → `eid` URL で event detail を開く。非 Google は今日のビュー fallback
3. Domain `Event` に `calendarTitle: String` 追加、Infrastructure / UI / Composition で伝播
4. ホバー実装本体・ヒットテスト・中央 3 行・下部・wake・タイマー・メニューバートグルは無影響
5. 既存 Domain テスト 36 ケース全 pass（ヘルパ引数追加のみ）

## 2. Open Questions — 解決済み

spec 004 の 8 件すべて [CONFIDENT] で着手可能：

1. **反転判定の想定 tooltip サイズ** → 固定 200×40 直書き。GeometryReader 実測は再 layout を呼び `@Published` と同期しづらい
2. **反転オフセット** → 対称 `(-8, -8)`。視覚的に対称、計算もシンプル
3. **Y 軸反転の閾値** → 固定 40pt（2 行ケース安全側）
4. **`eid` 生成失敗時** → 今日のビュー fallback。`googleEventDetailURL` が `nil` を返したら fallback 経路
5. **`@google.com` 以外の Google 系 suffix** → 厳密一致のみ詳細経路。Workspace 独自ドメインは fallback（網羅性は Phase 3）
6. **`u/0` 妥当性** → 固定維持。動的解決は spec §Non-goals 明示
7. **`Event.calendarTitle` の型** → `String`（空文字列許容、required 非 nil）。`EKCalendar.title` は API 上 String 非 nil
8. **Equatable 影響** → id ベース維持（spec 001 の `CGColor` 比較回避方針）

## 3. ファイル別変更計画

| 種別 | パス | 変更概要 | 想定差分 | 公開 API 影響 |
|---|---|---|---|---|
| 編集 | `Sources/Toki/Domain/Event.swift` | `calendarTitle: String` を struct + init に追加 | +3/-1 | failable init signature 拡張 |
| 編集 | `Sources/Toki/Infrastructure/EventKitGateway.swift` | `convert(_:)` で `ek.calendar.title` を渡す | +1 | private のみ |
| 編集 | `Sources/Toki/UI/RenderableEvent.swift` | `calendarTitle: String` 追加 | +3 | VM 側で要更新 |
| 編集 | `Sources/Toki/Composition/ClockViewModel.swift` | `canvasEvents` で伝播、`handleArcTap` 書き換え、helper 3 個追加 | +35/-3 | クリック挙動拡張 |
| 編集 | `Sources/Toki/UI/ClockView.swift` | tooltip 位置反転 helper + 定数 5 個追加 | +15/-1 | なし |
| 編集 | `Tests/TokiTests/EventTests.swift` | `makeEvent` に `calendarTitle` 引数追加 | +1 | ケース本体無変更 |
| 編集 | `Tests/TokiTests/EventStatusTests.swift` | 同上 | +1 | 同上 |
| 編集 | `Tests/TokiTests/DayTimelineTests.swift` | 同上 | +1 | 同上 |
| 編集 | `SPEC.md` | クリック挙動の Google detail URL 仕様追記 | +5〜10 | docs のみ |

**新規ファイルなし**。

## 4. Domain `Event.calendarTitle` 追加

### signature 変更

```swift
struct Event: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let calendarColor: CGColor
    let externalIdentifier: String?
    let calendarTitle: String   // 新規、空文字列許容

    init?(id: String, title: String, start: Date, end: Date,
          calendarColor: CGColor, externalIdentifier: String?,
          calendarTitle: String) {
        guard !id.isEmpty, start < end else { return nil }
        // ... 既存代入 + self.calendarTitle = calendarTitle
    }
}
```

### 不変条件
- 既存：`!id.isEmpty`、`start < end`
- 新規：**なし**（`calendarTitle` 空文字列許容）

### Equatable
- 無変更（id ベース）

### Tests 影響
3 つのテストファイルの `makeEvent` ヘルパに `calendarTitle: String = ""` デフォルト引数を 1 行追加し、`Event(...)` 呼び出しにも `calendarTitle: calendarTitle` を追記。**ケース本体は無変更**、36 ケース全 pass を維持。

## 5. Infrastructure 変更

`EventKitGateway.convert(_:)` の `Event(...)` 呼び出しに 1 行追加：

```swift
return Event(
    // ... 既存
    externalIdentifier: ek.eventIdentifier,
    calendarTitle: ek.calendar.title   // 新規
)
```

`EKCalendar.title` は API 上 `String` 非 nil。空文字列のケースのみ ViewModel 側で fallback に流す。

## 6. UI 層詳細

### 6.1 `RenderableEvent` に `calendarTitle` 追加

```swift
struct RenderableEvent: Identifiable {
    // ... 既存
    let calendarTitle: String   // 新規、Google detail URL の eid 生成用
}
```

`Equatable` は id ベース維持。

### 6.2 `ClockView` ツールチップ位置反転

`ClockView.body` の tooltip 描画ブロックを helper 結果に差し替え：

```swift
if let tooltip = viewModel.hoveredTooltip {
    let position = Self.tooltipDisplayPosition(for: tooltip.position)
    EventTooltip(timeLabel: tooltip.startEndLabel, title: tooltip.title)
        .offset(x: position.x, y: position.y)
        .allowsHitTesting(false)
        .transaction { $0.animation = nil }
}
```

`ClockView` に private static helper を追加：

```swift
extension ClockView {
    private static let tooltipWidth: CGFloat = 200
    private static let tooltipHeight: CGFloat = 40
    private static let tooltipOffset: CGFloat = 8
    private static let canvasWidth: CGFloat = 280
    private static let windowHeight: CGFloat = 320

    /// ホバー位置からツールチップを描画する左上座標を計算する。
    /// X/Y 軸独立に判定：右端/下端を超える側だけ反転、左/上端は 0 クランプ。
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

### 設計判断
- private static で完結（Domain に出さない、テスト不要）
- 想定サイズ + 4 境界定数を 1 箇所集約 → 将来 frame 変更時に追従しやすい
- `EventTooltip.maxWidth` との同期は Phase 2（アクションボタン追加時）に再考

## 7. Composition 層詳細

### 7.1 `canvasEvents` で `calendarTitle` 伝播

```swift
RenderableEvent(
    // ... 既存
    start: ev.start,
    end: ev.end,
    calendarTitle: ev.calendarTitle   // 新規
)
```

### 7.2 `handleArcTap` 書き換え

```swift
func handleArcTap(at point: CGPoint, geometry: ClockGeometry) {
    guard let event = hitTest(point: point, events: canvasEvents, geometry: geometry) else { return }
    hoveredTooltip = nil
    let urlStr = Self.calendarURL(for: event, calendar: calendar)
    guard let url = URL(string: urlStr) else { return }
    NSWorkspace.shared.open(url)
}

/// クリック対象イベントから開くべき URL を決定する。
/// Google event なら detail URL、それ以外（および詳細生成失敗時）は今日のビュー fallback。
private static func calendarURL(for event: RenderableEvent, calendar: Calendar) -> String {
    if let detail = googleEventDetailURL(for: event) {
        return detail
    }
    return googleCalendarDayURL(for: event.start, calendar: calendar)
}

/// Google Calendar の event detail URL を組み立てる。
/// 失敗時は nil → 呼び出し側で今日のビューに fallback。
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

`googleCalendarDayURL(for:calendar:)` は既存実装維持（fallback として呼ばれる）。

### 関数長
- `handleArcTap`: 6 行
- `calendarURL`: 5 行
- `googleEventDetailURL`: 14 行
- `stripRecurrenceSuffix`: 6 行
- 合計：`ClockViewModel.swift` 約 240 行（< 400 行制約クリア）

## 8. 実装フェーズ順序

1 タスク = 1 commit、Conventional Commits + scope。

### Task 1: `feat(domain): Event に calendarTitle を追加`
- 対象：`Event.swift` + 3 つの Test ファイル
- 完了条件：`swift build` 成功、36 ケース全 pass
- 依存：なし
- 想定差分：+6/-1

### Task 2: `feat(infra): EventKitGateway で calendarTitle を伝播`
- 対象：`EventKitGateway.swift`
- 完了条件：`swift build` 成功、36 ケース pass
- 依存：Task 1
- 想定差分：+1

### Task 3: `feat(ui): RenderableEvent と canvasEvents で calendarTitle 伝播`
- 対象：`RenderableEvent.swift` + `ClockViewModel.swift`
- 完了条件：`swift build` 成功、36 ケース pass、ホバー/クリック既存挙動が無変更
- 依存：Task 2
- 想定差分：+4

### Task 4: `feat(composition): クリックで Google event 詳細 URL を組み立てる（fallback 付き）`
- 対象：`ClockViewModel.swift`
- 完了条件：`swift build` + 36 ケース pass + 実機検証（Google event クリック → detail、非 Google → 今日のビュー）
- 依存：Task 3
- 想定差分：+35/-3

### Task 5: `feat(ui): ClockView でツールチップ位置を反転判定する`
- 対象：`ClockView.swift`
- 完了条件：`swift build` + 36 ケース pass + 実機四隅でツールチップ見切れない
- 依存：Task 4
- 想定差分：+15/-1

### Task 6: `docs(spec): SPEC.md にクリック挙動の Google detail URL 仕様を追記`
- 対象：`SPEC.md`
- 完了条件：docs 更新、`swift build` 影響なし
- 依存：Task 5
- 想定差分：+5〜10

## 9. リスク

| リスク | 重大度 | 緩和策 |
|---|---|---|
| Task 1 で Domain テストが大量に壊れる | 低 | ヘルパに `calendarTitle: String = ""` デフォルト引数で吸収、各ケース無変更 |
| Google `eid` 仕様変更で detail URL が壊れる | 中 | spec §Non-goals「検知ロジック作らない」。404 でもユーザーは Google Calendar 自体に到達できる |
| `@google.com` 以外の Google 系 event | 低 | Workspace 独自ドメインは fallback、Phase 3 対応 |
| ツールチップ反転でカーソルにかぶる | 低 | 40pt + 8pt offset で隙間十分、spec §Non-goals 明示済み |
| `EKCalendar.title` 空文字列 | 低 | `googleEventDetailURL` でチェック → fallback |
| ClockView 想定サイズ定数の将来ずれ | 低 | private static で 1 箇所集約、frame 変更時に追従 |

## 10. テスト方針

### Domain テスト
- **新規追加なし**（値の伝播のみで Domain ロジック増えない）
- 3 つのテストファイルの `makeEvent` ヘルパに +1 行ずつで吸収
- 各 task で `swift test` 36 ケース全 pass を確認

### 手動検証チェックリスト

**ツールチップ位置反転（Task 5）**
- [ ] 12 時付近の event ホバー → 左上方向に反転
- [ ] 6 時付近 → 上方向に反転
- [ ] 3 時付近 → 左方向に反転
- [ ] 9 時付近 / 中央上方 → 従来通り `(+8, +8)`
- [ ] 四隅でウィンドウ枠を越えない
- [ ] tooltip 内容（HH:MM-HH:MM / タイトル）は spec 003 通り

**Google event 詳細ジャンプ（Task 4）**
- [ ] Google event（`@google.com` 末尾）クリック → ブラウザで `/r/event?eid=...` の detail
- [ ] 繰り返しイベント（`_RYYYYMMDD...` 付き）でも該当 instance の detail に到達
- [ ] Exchange / iCloud event（`@google.com` で終わらない）→ 今日のビュー
- [ ] `calendarTitle` 空 → 今日のビュー fallback
- [ ] ヒットなし → 何も起きない

**既存挙動の維持**
- [ ] 中央 3 行 / 下部「次の予定」/ 針 / 円弧描画 / リング輪郭 / メニューバートグル / 右クリック終了 / wake / 分タイマーが無影響
- [ ] ホバー表示 / 円弧外で消える挙動が無影響

## 11. Out of scope 確認

spec 004 §Non-goals 再掲：

- ツールチップの完全な配置最適化
- ツールチップの自動リサイズ
- Google Calendar 編集画面遷移
- Outlook / Exchange / iCloud 系の web 詳細ジャンプ
- `eid` URL 形式の崩壊検知 / リトライ
- ツールチップ内アクションボタン
- Google Meet / Zoom リンク自動検出
- イベント編集機能
- 複数 Google アカウントの `u/0` 動的解決
- アニメーション

## 参考ファイル

- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/specs/004-event-detail-and-tooltip-flip.md`
- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/CLAUDE.md`
- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/Sources/Toki/Domain/Event.swift`
- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/Sources/Toki/Infrastructure/EventKitGateway.swift`
- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/Sources/Toki/UI/RenderableEvent.swift`
- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/Sources/Toki/Composition/ClockViewModel.swift`
- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/Sources/Toki/UI/ClockView.swift`
- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/Tests/TokiTests/{EventTests,EventStatusTests,DayTimelineTests}.swift`

次のステップ：`/tasks 004-event-detail-and-tooltip-flip` で atomic task 化 → fresh subagent で 1 commit ずつ実装。
