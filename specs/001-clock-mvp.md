# 001 — 円形時計型カレンダー MVP

## Why

macOS で「今やってる予定 / 次の予定」を確認するために、毎回カレンダーアプリを開きに行くか、メニューバーのドロップダウンを展開する必要がある。視線を移すだけで把握できる、邪魔にならない常時前面表示の UI が欲しい。

既存解の不足：
- Apple Calendar / Fantastical / BusyCal / Notion Calendar：常時前面表示機能を持たない
- メニューバー常駐型（Itsycal / Dato 等）：ドロップダウンで「常時表示」ではない
- Floaty / Rectangle Pro：任意ウィンドウを最前面化できるが、汎用のため Calendar UI が大きすぎる

→ 自分用に「小さい・円形・常時前面・OS カレンダー統合済み」の専用ツールを作る。

## Goal

MVP（Phase 1）完了時に達成する状態：

1. macOS 起動時、メニューバーに Toki アイコンが常駐する
2. アイコンクリックで 280×320px の円形時計ウィンドウが表示される
3. ウィンドウは常に最前面・全 Space で表示される
4. 24 時間アナログ時計の外周に今日のカレンダーイベントが色付き円弧で描画される
5. 現在時刻に針が向き、進行中の予定が中央に表示される
6. 次の予定が時計の下に 1 行で表示される
7. 過去のイベントは薄く、現在は強調、未来は通常の濃度で描画される

## Non-goals

MVP では明示的に作らない：

- **イベント編集機能**：クリックは純正カレンダー.app に飛ばすのみ
- **マウスオーバー時の中央表示切替**：Phase 2
- **イベント重なりの 2 段リング表示**：Phase 3、MVP では開始時刻が早い方を優先
- **設定 UI（対象カレンダー選択など）**：Phase 3
- **ウィンドウ位置記憶**：Phase 2
- **透明度調整**：Phase 3
- **起動時自動オン（LaunchAtLogin）**：Phase 3
- **Windows / Linux 対応**：当面しない

## Acceptance Criteria

EARS 構文。各項目はテスタブルな粒度で記述。

### ウィンドウ・常駐挙動

- When ユーザーが Toki を起動したとき、メニューバーに時計アイコンが表示される
- When ユーザーがメニューバーアイコンをクリックしたとき、時計ウィンドウの表示/非表示がトグルされる
- The 時計ウィンドウは、常に最前面（`NSWindow.level = .floating`）で表示される
- The 時計ウィンドウは、すべての Space で表示される（`collectionBehavior` に `.canJoinAllSpaces` と `.stationary`）
- While 時計ウィンドウが表示されているとき、ユーザーは背景ドラッグでウィンドウを移動できる
- The アプリは Dock に表示されない（`LSUIElement = YES`）

### カレンダー連携

- When アプリが初回起動したとき、EventKit のフルアクセス権限を要求する
- If ユーザーが EventKit 権限を拒否したとき、時計は針と時刻表示のみで動作する（イベント円弧は描画されない）
- When ユーザーが EventKit 権限を許可したとき、今日のすべてのカレンダーのイベントを取得し時計に反映する
- When カレンダー側でイベントが追加・変更・削除されたとき、アプリは `EKEventStoreChanged` 通知を受けて時計表示を更新する

### 時計描画

- The 時計は 24 時間アナログ表示で、0:00 が真上、12:00 が真下、時計回りに進む
- The 時計には 0 / 6 / 12 / 18 の 4 つの時刻マーク数字が表示される
- The 針は現在時刻を指し、中心から外周まで描画される
- When 1 分が経過したとき、針の位置が更新される

### イベント円弧

- The 各イベントは、開始時刻から終了時刻に対応する円弧（annulus segment）として描画される
- The イベントの色は、対応する `EKCalendar` の `cgColor` を使用する
- The 描画時刻はローカルタイムゾーン基準とする（MVP では TZ をまたぐ挙動は対象外）
- If イベントが深夜を跨ぐ（前日 → 今日 / 今日 → 翌日）、then 今日の 0:00–24:00 にクリップして描画する
- If イベントが all-day である、then 円弧描画から除外する（次の予定ラインでの扱いは別途）
- While イベントが過去（`end <= now`）であるとき、円弧は alpha 0.3 で描画される
- While イベントが現在進行中（`start <= now < end`）であるとき、円弧は alpha 1.0 + 0.75px のアウトラインで描画される
- While イベントが未来（`start > now`）であるとき、円弧は alpha 1.0 で描画される
- If 複数のイベントが同じ時間帯に重なっているとき、開始時刻が早い方の円弧のみが表示される

### 中央テキスト

- While 現在進行中のイベントがあるとき、中央には「現在時刻 / イベント名 / 残り XX 分」が表示される
- While 現在進行中のイベントがないとき、中央には「現在時刻 / — / 次まで XX 分」が表示される

### 次の予定ライン

- The 時計の下には、次の予定が「次  HH:MM タイトル」形式で 1 行表示される
- While 今日これ以上予定がないとき、次の予定ラインは非表示になる

### イベントクリック

- When ユーザーがイベント円弧を左クリックしたとき、該当イベントが純正カレンダー.app で開かれる

## Domain Model

```
TimeOfDay (Value Object)
  - hour: Int (0..<24)
  - minute: Int (0..<60)
  - minutesSinceMidnight: Int
  - clockAngle: Double  // 24時間時計上の角度（ラジアン、0:00が-π/2）

Event (Value Object)
  - id: String
  - title: String
  - start: Date
  - end: Date
  - calendarColor: CGColor
  - externalIdentifier: String?  // 純正カレンダーで開くため

EventStatus (Enum)
  - past, current, future
  - Event.status(at: Date) で判定

DayTimeline (Aggregate)
  - date: Date
  - events: [Event]  // start 昇順
  - currentEvent(at: Date) -> Event?
  - nextEvent(after: Date) -> Event?
```

**Invariants（不変条件）**：
- `Event.start < Event.end`（0 分イベントは許可しない）
- `DayTimeline.events` は `start` 昇順、同 `start` の場合は `end` 昇順
- `Event.id` はアプリケーション内で一意（recurring イベントの occurrence ごとに合成）

**変換責務**：
- `EKEvent → Event` の変換は Infrastructure 層の責務
- `Date → TimeOfDay` の変換は Domain 層の純関数

Domain は Foundation のみに依存。EventKit 型（`EKEvent` 等）はここに漏らさない。
実装詳細（型定義の Swift コード、変換ロジック）は `/plan` で `specs/001-clock-mvp-plan.md` に展開する。

## Open Questions

実装着手前に潰しておきたい論点（カテゴリ分け）：

### UX / 体験
1. **EventKit 権限拒否時の UX**：時計だけ動かす（現方針）で OK か？ それとも「権限が必要」表示を出して再要求導線を作るか
2. **初回表示位置**：右上固定？画面中央？前回終了位置？ MVP では位置記憶しないため毎回どこに出すかを決める必要がある
3. **空状態 UX**：今日 0 件・権限なし・全カレンダー OFF、それぞれの中央表示と「次の予定ライン」の見せ方
4. **ウィンドウのダブルクリック挙動**：ハイド？何もしない？ 右クリックメニューはどうする？
5. **長いイベントタイトルの trim 戦略**：truncate / ellipsis / marquee
6. **`EKCalendar.cgColor` のコントラスト保証**：薄い色のカレンダーが背景に溶けるリスクをどう緩和するか

### 描画ルール
7. **針の z-index**：イベント円弧の上に重ねるか下に隠すか（上を推奨だが要確認）
8. **クリック判定の精度**：細い円弧（15 分イベント）のクリックは現実的に当たるか？ ヒットエリアを別途持つ必要があるか
9. **all-day イベントを「次の予定」ラインに含めるか**：朝の時点で「次は終日イベント」と出すのは有用？ ノイズ？

### 技術・実装
10. **`EKEventStoreChanged` の debounce 戦略**：同期中のチラつき防止、500ms 程度の debounce が必要か
11. **タイマーの sleep/wake 復帰**：wake トリガーでの即時更新ロジック
12. **`Event.id` と recurring イベント対応**：`EKEvent.eventIdentifier` は recurring 全 occurrence で同じ ID を持つ、一意性をどう担保するか
13. **ボーダーレスウィンドウの key window 挙動**：`canBecomeKey` を OFF にする（テキスト入力なし、フォーカス奪わない）
14. **針の終端座標**：内リング (110px) で止めるか、外リング (130px) で止めるか、突き抜けるか

## Out of scope / Phase 2 以降

参考：

- **Phase 2**：マウスホバーで中央表示切替、ウィンドウ位置記憶（`UserDefaults`）、右クリックメニュー
- **Phase 3**：重なりイベントの 2 段リング、透明度調整（Option + scroll）、対象カレンダー選択、`LaunchAtLogin`
- **Phase 4+（評価次第）**：他人に配布する場合の検討事項（License、配布形態、有償化、マルチユーザー対応、Windows 対応の是非）— 自分用としての評価が固まってから検討する
