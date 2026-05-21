# 004 — Google Calendar イベント詳細ジャンプとツールチップ自動反転

## Why

spec 003 で実装した「ホバー → ツールチップ / クリック → Google Calendar 今日のビュー」が稼働した結果、実機検証で 2 つの UX 課題が顕在化：

### 課題 1: ツールチップの見切れ
spec 003 §Open Question #6 で「MVP では見切れ許容、Phase 2 で反転」と明記したが、実機ではウィンドウ右下寄りの円弧（例：12 時付近の予定）にホバーするとツールチップがウィンドウ下端から大きくはみ出して読めない。`280×320` の小さなウィンドウかつ tooltip 最大幅 200pt のため固定オフセット `(+8, +8)` だと頻発する。

### 課題 2: クリック先がイベント詳細でなく「今日のビュー」止まり
spec 003 ではブラウザ起動先を `/r/day/YYYY/MM/DD` 固定としたが、ユーザーは「**該当イベントの詳細まで開いてほしい**」と希望。Google Calendar の web 版には event detail を直接開く URL があり（`/r/event?eid=<base64>` 形式）、`calendarItemExternalIdentifier`（iCal UID）と calendar のメールアドレスから組み立てられる。

→ **両者を「実機検証から得た UX 改善」としてまとめて spec 004 で対応する**。

## Goal

Phase 1.7（本 iteration 完了時）に達成する状態：

1. ツールチップがウィンドウ右端を超える場合、自動的にカーソル左側に表示される
2. ツールチップがウィンドウ下端を超える場合、自動的にカーソル上側に表示される
3. Google Calendar 系イベント（`calendarItemExternalIdentifier` が `@google.com` で終わる）のクリックで、**該当イベントの detail ページ**がブラウザで開く
4. 非 Google 系イベント（Exchange / iCloud 等）のクリックでは、spec 003 と同じ **今日のビュー** にフォールバック
5. Domain / Infrastructure 層への必要最小限の変更（calendar 名の追加伝播）を許容、テスト 36 ケース全 pass を維持
6. spec 003 で実装したホバーツールチップ、`onContinuousHover`、`hoveredTooltip` 状態管理などのコア機能は無変更（位置計算ロジックのみ強化）

## Non-goals

本 iteration では明示的にやらない：

- **ツールチップの完全な配置最適化**（左右上下の全反転、ウィンドウ外配置）：シンプルに「右端なら左、下端なら上」の 2 軸独立判定のみ
- **ツールチップの自動リサイズ**：固定 max 200pt 幅は維持、可変幅化はしない
- **Google Calendar の編集画面（`/r/eventedit/...`）への直接遷移**：詳細表示画面（`/r/event?eid=...`）に統一する。編集は Google Calendar の本物 UI 内で操作してもらう前提
- **Outlook / Exchange / iCloud 系の web 詳細ジャンプ対応**：今日のビュー fallback のみ。各サービス専用 URL の対応は Phase 3 行き
- **`eid` URL 形式の崩壊検知やリトライ**：Google 内部の reverse-engineered な URL のため、将来変わった場合は fallback に流す。検知ロジックは作らない
- **ツールチップへのアクションボタン**（「ブラウザで開く」「Meet 参加」等）：spec 003 §Non-goals 通り、引き続き対象外
- **Google Meet / Zoom リンクの自動検出**：spec 003 §Non-goals 通り対象外
- **イベント編集機能**：spec 001 から引き続き対象外
- **複数 Google アカウントでの `u/0` 動的解決**：固定 `u/0` 維持、設定 UI は Phase 3 行き
- **アニメーション**：ツールチップの位置変化を含めて、アニメーションなし（spec 003 と同様）

## Acceptance Criteria

### ツールチップ位置の自動反転

- While カーソルが時計の右半分にあり、`hover_x + 8 + tooltip_max_width > 280` のとき、ツールチップはカーソル左側（`hover_x - 8 - tooltip_max_width`）に表示される
- While カーソルが時計の下半分にあり、`hover_y + 8 + tooltip_max_height > 320` のとき、ツールチップはカーソル上側（`hover_y - 8 - tooltip_max_height`）に表示される
- The 反転判定は X 軸と Y 軸で **独立** に行う（右上 / 左下 / 右下 など全 4 象限で適切な位置になる）
- The 反転後の位置でもウィンドウ左端 / 上端を割り込まない（左端 / 上端が 0 を下回る場合は 0 にクランプ）
- The ツールチップの幅・高さ・スタイルは spec 003 のまま（max 200pt 幅、2 行表示、角丸 6pt）

### Google Calendar イベント詳細ジャンプ

- When ユーザーがイベント円弧をクリックしたとき、そのイベントが Google Calendar 系（`externalIdentifier` が `@google.com` で終わる）であれば、デフォルトブラウザで Google Calendar の event detail URL が開く
- The Google event detail URL は `https://calendar.google.com/calendar/u/0/r/event?eid=<base64>` 形式
- The `eid` の中身は `base64("<base_event_uid> <calendar_email>")`：
  - `base_event_uid` は `calendarItemExternalIdentifier` から `_R<digits>T<digits>` suffix を除去したもの
  - `calendar_email` は `ek.calendar.title`（Domain Event に新規追加するフィールド）
- The base64 は URL-safe（`+` → `-`、`/` → `_`、`=` パディング除去）
- When ユーザーがイベント円弧をクリックしたとき、そのイベントが非 Google 系（`externalIdentifier` が `@google.com` で終わらない、または nil）であれば、spec 003 と同じ今日のビュー（`/r/day/YYYY/MM/DD`）にフォールバック
- If `calendar_email` が空文字列であれば、then Google event でも今日のビューへフォールバック（防御的）

### Domain / Infrastructure 影響

- The `Event` Domain type に `calendarTitle: String` が追加される（カレンダー名 / メールアドレス、必須非 nil）
- The `EventKitGateway.convert(_:)` で `ek.calendar.title` を `calendarTitle` にコピーする
- The `Event.failable init` の不変条件は変えない（既存 `start < end`、`id` 非空のみ）。`calendarTitle` の空文字列は許容（防御は ViewModel 側で行う）
- The 既存 Domain テスト 36 ケースは無変更で全 pass する
- The `RenderableEvent` に `calendarTitle: String` を伝播させる（spec 003 で `start` / `end` を追加した時と同じパターン）

### 既存挙動の維持

- The ホバーツールチップの表示・消去・内容（HH:MM - HH:MM / タイトル）は無変更
- The Calendar.app 起動経路は引き続き存在しない（spec 003 で撤去済み）
- The 中央 3 行テキスト / 下部「次の予定」/ 針 / 円弧描画 / メニューバートグル / 右クリック終了 / wake / タイマーは無影響

## Domain Model

### `Event`（既存、フィールド追加）

```
Event (Value Object)
  - id: String
  - title: String
  - start: Date
  - end: Date
  - calendarColor: CGColor
  - externalIdentifier: String?
  + calendarTitle: String  // 新規：EKCalendar.title をコピー、空文字列は許容
```

**Invariants（不変条件）**：
- 既存：`start < end`、`id` 非空
- 新規：`calendarTitle` は空文字列を許容（required 非 nil だが空 OK）

**変換責務**：
- `EKEvent.calendar.title → Event.calendarTitle` の変換は Infrastructure 層（`EventKitGateway.convert`）

### `RenderableEvent`（既存、フィールド追加）

```
RenderableEvent (UI 層 Value Object)
  - id / title / startAngle / endAngle / color / status / externalIdentifier / start / end
  + calendarTitle: String  // 新規、Event から伝播
```

### `TooltipState`（既存、無変更）

spec 003 で定義済み。`position: CGPoint` の解釈は変えない（カーソル位置）。位置の反転計算は `ClockView` 側で行う（presentation の責務）。

**`TooltipState` を不変条件として変更しないことの理由**：position は「ホバー位置」の意味で本質的、表示位置の計算はビューの責務に閉じ込めた方がレイヤー責務が綺麗。

## Open Questions

実装着手前に判断したい論点：

### 位置反転
1. **反転判定で使う tooltip 想定サイズ**：固定値（幅 200pt / 高さ 40pt）を直書きするか、SwiftUI `GeometryReader` で実測するか。固定値の方がシンプルだが、タイトル短いときに過剰反転する可能性
2. **反転オフセット**：右側表示時は `(+8, +8)`、左側表示時は `(-8, -8)` で対称にするか、視覚的に最適なオフセットを別途決めるか
3. **Y 軸反転の閾値**：ツールチップ高さは title 1 行で 28pt 程度、2 行で 40pt 程度。固定 40pt で計算するのが安全だが、1 行のケースで早めに反転しすぎる懸念

### Google URL
4. **`eid` 生成失敗時の挙動**：base64 エンコード自体は失敗しないが、`calendar_email` が空 or 無効な文字を含む場合のハンドリング。今日のビュー fallback で良いか
5. **`@google.com` 以外の Google 系 suffix**：Google Workspace の独自ドメインカレンダー（`@<domain>.com`）の場合、`eid` 生成が正常に動くか。実機検証で `@google.com` だけ確認できているため、それ以外は fallback に流すのが安全
6. **`u/0` の妥当性**：複数 Google アカウントを browser にログインしているユーザーが「`u/0` でないアカウントの予定」をクリックしたとき、正しい detail に飛ぶか。Google 側で `eid` から適切なアカウントを推定してくれる挙動を期待するが、要実機検証

### Domain 影響
7. **`Event.calendarTitle` の型**：空文字列許容の `String` か、`String?`（nil 許容）か。実装では `ek.calendar.title` が常に非 nil の `String` を返すため `String` で良い。空文字列も EventKit 仕様上ありえないが、防御的に空チェックする
8. **`Event.calendarTitle` の `Equatable` 影響**：spec 001 で `Event.Equatable` は **`id` ベース限定** に決めた経緯あり。新フィールド追加で挙動変えない方針（id ベースのまま）で OK か

## Out of scope / Phase 2 以降

参考：

- **Phase 2**：ツールチップに「ブラウザで開く」「Meet 参加」「コピー」等のアクションボタン
- **Phase 3**：Outlook（`outlook.office.com/calendar/...`）/ iCloud（unknown）系の web 詳細 URL 対応、複数アカウント自動解決（`u/0` 動的）、ツールチップの完全な配置最適化（4 象限以上の自動位置決め）
- **将来検討**：Google `eid` 仕様が変わった場合の検知・リカバリ、Google Workspace ドメイン対応の網羅性向上、event ID 同期遅延への対応
