# 013 — 重なり event のホイール cycle + 終日（24h）event 背景帯化

## Why

実用中に発覚した 2 つの pain：

### Pain 1：重なり event が 1 つしか表示されない

現状の Toki は `DayTimeline.filterOverlaps` で **earliest start wins** ルールにより、重なり event を 1 件残して他を捨てる（SPEC.md §3 / Phase 3「重なりイベントの 2 段リング」候補）。

実用での問題：
- 10:00〜11:00 に 2 件並行 event（例：定例ミーティング + 別チーム MTG）→ 1 件しか見えない
- 「もう 1 件あった気がする」が確認できず、ブラウザで Google Calendar を開く手間
- 「event = タスク」運用ユーザーにとって、並行作業の存在が見えないのは致命的

### Pain 2：終日（24h）event の表示バグ

「今日 0:00 〜 翌 0:00」のような **時刻指定の 24 時間 event**：
- Google Calendar API：`start.dateTime = today 00:00` / `end.dateTime = tomorrow 00:00`
- 現状の Toki：`isAllDay = false` で通常 event 扱い → **円全体を覆う full ring** が描画され、他の event を覆い隠す
- all-day event（`start.date` のみ）は既に除外済みだが、24h timed event は除外されない

実用シーン：
- 1 日丸ごとブロックしたい用途（出張 / 旅行 / 1 日中の研修 / 24h on-call 等）で `0:00 → 翌 0:00` を作る人がいる
- これが他の event を埋もれさせて可視性ゼロになる

## Goal

Phase 3.3（本 iteration 完了時）に達成する状態：

### Pain 1 解決：ホイール cycle 方式

1. **Domain `DayTimeline` を `[OverlapGroup]` 保持に変更**：重なり event を捨てず、グループとして保持
2. **新規 `OverlapGroup` 値オブジェクト**：1 件以上の event を持つ重なりグループ
3. **scroll wheel で重なり cycle**：hover 中のグループに対して scroll → 表示 event を切替
4. **グループごと独立 index**（案 B）：別グループは影響を受けない
5. **視覚 indicator**：
   - **badge `+N`**：重なりがあるグループの弧の外側に「他 N 件」表示
   - **peek 表示**：次 event の色を弧の端に少しはみ出させる（おしゃれ）
6. **任意数の重なりに対応**：2 件 / 3 件 / N 件すべて cycle 可能

### Pain 2 解決：24h 背景帯化

7. **24h event 検出**：`event.start == dayStart && event.end == nextDayStart` を背景帯として扱う
8. **背景帯描画**：通常の event 円弧の **背面** に薄い色で全周描画、前面 event を埋もれさせない
9. **重なり計算から除外**：24h event は OverlapGroup には含めない

### 共通

10. **既存挙動の維持**：今日の予定（重なりなし）/ popover / ホバー / 設定 UI は完全同一動作
11. **Domain テスト**：既存 36 ケースは無変更で全 pass、新規ケースは OverlapGroup / 24h 検出向けに 5〜10 件追加

## Non-goals

本 iteration では明示的にやらない：

- **popover の cycle ナビ**（`← 1/3 →`）：spec 015 候補、本 spec では popover は現在表示中 event のみ表示
- **2 段リング描画**：ホイール cycle で十分なので不要、本 spec では引き続き 1 段
- **scroll 量に応じた連続切替**：1 notch で 1 step（discrete）
- **scroll で透明度操作**：spec 008 Out-of-scope の「scroll で透明度」とは別機能、本 spec では cycle 専用
- **マウスホイール以外の cycle 操作**（上下キー / ボタン）：本 spec では scroll wheel 限定
- **同一グループ内の event を同時表示**（半透明重ね等）：cycle 方式で一覧性を担保
- **背景帯クリックで popover**：背景帯は通常 event 円弧と区別し、クリックは pass-through（後ろの「次の予定」表示 = 中央エリアに遷移しない）
- **24h event を中央テキストに別途表示**：本 spec では背景帯のみ、追加 UI は spec 014 候補
- **複数 24h event の同時背景帯描画**：MVP は「最初の 1 件のみ」描画、複数件対応は別 spec
- **タイムゾーン跨ぎの 24h event**：localTimeZone 前提継承
- **重なりグループの内訳を popover で全件表示**：spec 015 候補

## Acceptance Criteria

### Domain 改修

#### `OverlapGroup` 値オブジェクト（新規）

```
OverlapGroup (Value Object)
  - events: [Event]    // 1 件以上、start 昇順、相互に時間重複
  - id: String         // 安定 ID（events[0].id を流用）

不変条件：!events.isEmpty
```

- The `OverlapGroup` は Identifiable / Equatable（id ベース）/ Hashable
- The `count: Int` computed: `events.count`
- The `isOverlapping: Bool` computed: `events.count > 1`
- The `event(at index: Int) -> Event` computed: `events[index % events.count]` で循環参照

#### `DayTimeline` 改修

```
DayTimeline (Value Object) — 改修
  - date: Date
  - groups: [OverlapGroup]      // 重なりグループの配列、start 昇順
  - backgroundEvents: [Event]   // 24h timed event（背景帯用）
```

- The 既存 `events: [Event]` フィールドは **削除**、computed property で flatten 提供（後方互換）：
  - `var events: [Event] { groups.flatMap { $0.events } }`
- The `DayTimeline.make(date:rawEvents:allDayFlags:calendar:)` ファクトリは：
  1. all-day（`allDayFlags == true`）を除外
  2. 24h timed event（`start == dayStart && end == nextDayStart`）を `backgroundEvents` に分離
  3. 残りを clip して `groupOverlaps` で `[OverlapGroup]` 構築
- The `groupOverlaps` ロジック：start 昇順で走査、直前グループの最大 end と次の event の start を比較、重なれば同グループに追加、なければ新グループ
- The `currentEvent(at:)` / `nextEvent(after:)` の挙動は維持（events flat を内部で使用）

#### 24h event 検出

- The `event.start == calendar.startOfDay(for: event.start) && event.end == calendar.date(byAdding: .day, value: 1, to: event.start)` を背景帯候補とする
- The 検出は `DayTimeline.make` で実施し `backgroundEvents` に分離
- The MVP では `backgroundEvents.first` のみ背景帯描画、複数件は ignore（spec §Non-goals）

### Composition 改修

#### `ClockViewModel` 拡張

- The `@Published var overlapIndices: [String: Int]`（key = OverlapGroup.id）を追加
- The `canvasGroups: [RenderableOverlapGroup]` computed property を新設：
  - `DayTimeline.groups` を `RenderableOverlapGroup`（UI 表示用）に変換
  - 各グループから「現 index の event」を `current: RenderableEvent`、「次 index の event」を `peek: RenderableEvent?` として保持（peek 用）
- The `canvasBackgroundEvent: RenderableEvent?` computed property を新設：背景帯描画用、`DayTimeline.backgroundEvents.first` を変換
- The `handleScroll(deltaY: CGFloat, hoverPoint: CGPoint?, geometry: ClockGeometry)` メソッドを追加：
  - hover 中のグループ特定 → overlapIndices[groupID] += sign(deltaY)
  - hover 外 / 重なりなしグループでは no-op
- The 既存 `canvasEvents: [RenderableEvent]` は廃止 or 後方互換のため computed property で flatten 提供（後者推奨）
- The hover / click ハンドラは「現 index の event」を対象に動作する（既存 hit-test 流用、グループ単位）

### UI 改修

#### 新規 `RenderableOverlapGroup`

```swift
struct RenderableOverlapGroup: Identifiable, Equatable {
    let id: String                // groupID
    let current: RenderableEvent  // 現在表示中
    let next: RenderableEvent?    // 次 event（peek 用、重なりなしなら nil）
    let extraCount: Int           // 重なり追加件数（badge 表示用、0 = 重なりなし）
}
```

#### `ClockFaceCanvas` 拡張

- The 入力を `events: [RenderableEvent]` → `groups: [RenderableOverlapGroup]` に変更
- The `backgroundEvent: RenderableEvent?` を追加引数として受け取る
- The 描画順：
  1. 背景帯（`backgroundEvent` あれば全周薄色塗り）
  2. 各グループの `current` の event 円弧（既存描画パターン踏襲）
  3. **peek**：`next` がある場合、`current` の弧の終端付近に `next.color` を 5〜8pt（角度比約 3〜5%）はみ出させる
  4. **badge**：`extraCount > 0` のグループは弧の外側に `+N` テキスト + 小さな背景で描画
  5. hand / 時刻マーク / 中心ドット（既存通り最前面）

#### `ClockView` 拡張

- The `ClockFaceCanvas` の `onScroll` callback を追加：`onScroll: (CGFloat, CGPoint?, ClockGeometry) -> Void`
- The `viewModel.handleScroll(deltaY:hoverPoint:geometry:)` に接続
- The 既存 onTap / onHover は維持（current event 対象、内部で current event を取り出して既存 handleArcTap / handleHover を呼ぶ）

#### Scroll handler 実装方針

- The macOS SwiftUI で scroll wheel を扱うため `NSViewRepresentable` ベースの薄いラッパー、または `.onContinuousHover` + AppKit `NSEvent.localEvents` で受ける
- The 1 notch（discrete scroll）で 1 step cycle、連続 scroll は debounce / 集計（200ms 内の複数 notch は 1 とカウント等）
- The 推奨：`NSView` を subclass して `scrollWheel(with:)` をオーバーライド、`scrollDirection: vertical` のみ受ける

### 既存挙動の維持

- The 重なりなし event（単独グループ）の表示・クリック・ホバー・popover は完全同一
- The OAuth / 設定 UI 11 軸 / リサイズ / 位置記憶 / 最終更新 / 次未来 event 表示は無変更
- The ホバーツールチップは current event 1 件のみ表示（重なりがあっても、cycle 結果を反映）
- The popover は current event 1 件のみ表示（spec 015 候補で cycle ナビ追加検討）

### Domain テスト

- The 既存 36 ケースは **無変更で全 pass**：`DayTimeline` の `events` を computed property 化して後方互換維持
- The 新規ケース（5〜10 件想定）：
  - OverlapGroup 単一 event
  - 2 件重なりグループ
  - 3 件重なりグループ
  - 隣接非重なり（端接触）→ 別グループ
  - 24h timed event の検出と背景分離
  - all-day event は背景分離されない（既存除外ロジック維持）

## Open Questions

実装着手前に判断したい論点：

### Domain
1. **OverlapGroup の ID**：`events[0].id` を流用 vs UUID 生成。**`events[0].id` 流用** 推奨：[CONFIDENT]、安定 / 同一性追跡可能
2. **`events` 廃止 vs computed**：既存テスト無変更維持のため **computed property で flatten** 推奨：[CONFIDENT]
3. **重なり判定**：「端接触 `prev.end == next.start`」は別グループ扱い（既存 filterOverlaps と同じ）：[CONFIDENT]
4. **背景帯候補の検出条件**：`start == dayStart && end == nextDayStart`（exact match）：[CONFIDENT]
5. **all-day と 24h timed の併存**：all-day は除外、24h timed は背景帯化。両方ある日でも独立処理：[CONFIDENT]

### Composition / UI
6. **scroll 方向**：上スクロール = 次 event vs 前 event。**上 = 次**（macOS の reverse scrolling 直感、natural scroll ON でも違和感少）推奨：[CONFIDENT]
7. **scroll sensitivity**：1 notch で 1 step。連続スクロールは 200ms 内の複数 notch を 1 として集計（macOS の trackpad での連続 scroll を考慮）：[CONFIDENT]
8. **hover 外で scroll**：no-op（無視）vs 最後に hover したグループを操作。**no-op** 推奨：[CONFIDENT]、誤操作防止
9. **重なりなしグループで scroll**：no-op：[CONFIDENT]
10. **peek の角度割合**：弧の角度幅の何 % か。例：5%（最大）/ 8pt（最小）の min 採用。**MVP は 5%**：[CONFIDENT]
11. **peek の描画位置**：弧の終端（時計回り進行方向）vs 開始端。**終端**（次の event が時間的に「次」なので進行方向に出すのが直感的）：[CONFIDENT]
12. **badge `+N` のフォントと位置**：弧の外側、フォント 9pt、薄い背景円。**SF Symbol 不使用、Text のみ**：[CONFIDENT]
13. **背景帯の色**：24h event の calendar 色 × opacity 0.15 程度。**MVP は 0.15**：[CONFIDENT]
14. **背景帯クリック**：pass-through（クリックを通す）vs popover を出す。**pass-through** 推奨：[CONFIDENT]、UX 一貫性（背景帯はあくまで「informational」）
15. **複数 24h event**：MVP は `backgroundEvents.first` のみ表示、追加 UI は spec 014 候補：[CONFIDENT]

### スクロールハンドラ実装
16. **NSViewRepresentable vs 既存 SwiftUI Gesture**：scrollWheel は SwiftUI の `.gesture` で取れないため **NSViewRepresentable + NSView.scrollWheel(with:) override**：[CONFIDENT]
17. **scroll handler の置き場所**：`Sources/Toki/UI/ScrollCatcher.swift`（新規）として薄く実装：[CONFIDENT]

[NEEDS INPUT] は最大 3 件以下に絞る → 0 件、すべて [CONFIDENT] で着手可能。

## Out of scope / Phase 3 以降

参考：

- **spec 014 候補**：表示するカレンダー選択（元 spec 013 候補から繰り下げ）
- **spec 015 候補**：
  - popover に cycle ナビ（`← 1/3 →`）
  - 複数 24h event の背景帯重ね描画（多階層 opacity）
  - 重なりグループの内訳を popover で全件表示
  - scroll で透明度操作（spec 008 §Phase 3 候補）
  - キーボードショートカット（`↑↓` で cycle）
- **長期 Phase 3**：
  - 重なり event の半透明重ね描画
  - 並行 calendar の色分け詳細表示
  - 24h event の中央テキスト補足

## 補足：UI イメージ

### 重なり 3 件のグループ（10:00〜11:00 に A / B / C）

```
（初期状態：index = 0）
円弧 10-11 時の位置：[━━━━━━━━━━]┤  +2
                    └ A の色      └ B の色 (peek)

（scroll 1 回後：index = 1）
円弧 10-11 時の位置：[━━━━━━━━━━]┤  +2
                    └ B の色      └ C の色 (peek)

（scroll 1 回後：index = 2）
円弧 10-11 時の位置：[━━━━━━━━━━]┤  +2
                    └ C の色      └ A の色 (peek、循環)
```

### 24h 背景帯 + 通常 event

```
円全体に薄い色（出張の calendar 色 × 0.15）が背景帯として描画され、
その上に通常の event 円弧（10-11, 14-15 等）が前面に出る。
```
