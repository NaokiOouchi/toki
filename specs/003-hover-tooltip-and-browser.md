# 003 — ホバー詳細表示と Google Calendar ブラウザ起動

## Why

spec 001 で実装したイベント円弧クリック→純正カレンダー.app 起動は、Google Calendar の繰り返しイベントで信頼性が低い問題が判明した。

具体的な不具合：
- Google の繰り返しイベントは `calendarItemExternalIdentifier` が `<baseUID>_R<参照日>@google.com` 形式で、`_R<参照日>` 部分が series の起点を示す（例：`b7ru16r58op25kb1nlvn6993hq_R20251106T120000@google.com`）
- `ical://ekevent/<eventIdentifier>?method=show` URL scheme は identifier に焼き込まれた起点日（去年）にジャンプしてしまう
- URL の path / query に occurrence date を追加しても Calendar.app は無視する（実機検証で確認済み）
- AppleScript 経由（`view calendar at <date>` + `whose uid is <UID>`）も、Calendar.app の `event.uid` プロパティが EventKit の identifier と一致しないうえ、Google CalDAV イベントは AppleScript dict から見えないことが判明（実機検証で「Google アカウントの calendar の events プロパティが空配列を返す」）

並行して spec 001 §「Open Questions」#1 で先送りした「マウスオーバーで予定が見られる UX」の需要が、Calendar.app 撤去と合わせて顕在化。

→ **「Toki ウィンドウ内で予定詳細をホバー閲覧、外部詳細はブラウザで」** に切り替える。

## Goal

Phase 1.6（本 iteration 完了時）に達成する状態：

1. ユーザーがイベント円弧にカーソルを乗せると、**ツールチップ風の小さなオーバーレイ**で「開始時刻 終了時刻」+「タイトル」が表示される
2. カーソルが円弧から離れると、ツールチップは自動的に消える
3. イベント円弧の左クリックで、**Google Calendar の今日のビュー** がデフォルトブラウザで開く
4. Calendar.app への URL scheme / AppleScript 経由のリンクは **完全に削除**される（信頼性が低いため）
5. `Info.plist` の `NSAppleEventsUsageDescription` も不要になったため削除
6. 中央 3 行テキスト（時刻 / 現在の予定 / 残り or 次まで）は **MVP の挙動を維持**（ホバーで切り替わらない）
7. Domain・Infrastructure 層は無変更

## Non-goals

本 iteration では明示的にやらない：

- **中央テキストのホバー切替**：中央は現在状況のままで固定（タイトルとの分離を維持）
- **ツールチップ内のアクションボタン**（「ブラウザで開く」「Meet 参加」等）：将来検討、本 iteration はクリックでブラウザ起動のみ
- **Google Calendar API 直接連携 / OAuth フロー**：EventKit からのデータ供給で十分、外部詳細はブラウザの本物の UI に委ねる
- **Google Meet / Zoom リンクの自動検出と参加ボタン**：ツールチップ内の「描画のみ」にとどめる
- **イベント編集機能**：spec 001 から引き続き対象外
- **複数イベント重なり時のツールチップ切替 UI**：MVP では「ヒットテストで最初に見つかった 1 件」を表示
- **ツールチップの自動位置調整（画面端で反転 等）**：MVP では固定位置（カーソル右上等）
- **アニメーション**：フェードイン/アウトは無し、即時表示/消去
- **Phase 1 で導入した `ical://` / `ical://ekevent/` URL の保持**：完全に撤去
- **Calendar.app を fallback として起動する経路**：撤去
- **Exchange / iCloud / その他カレンダー用の特別な分岐**：ブラウザは Google Calendar の day view 一択（汎用 fallback として機能する）

## Acceptance Criteria

### ホバー検出
- When カーソルがイベント円弧の範囲内に入ったとき、ツールチップが表示される
- When カーソルがイベント円弧の範囲から出たとき、ツールチップが消える
- The ツールチップのヒット範囲は、左クリックのヒット範囲（`hitTest(point:events:geometry:)`）と一致する
- If カーソルが時計盤の中心領域（中央テキスト）にあるとき、then ツールチップは表示されない
- If カーソルが複数の円弧の重なる位置にあるとき、then `hitTest` で最初に見つかったイベントのツールチップが表示される

### ツールチップ表示内容
- The ツールチップは最低 2 行を表示する：
  - 1 行目：開始時刻 - 終了時刻（例：`14:00 - 15:00`）
  - 2 行目：イベントタイトル
- The タイトルが長い場合は末尾省略（`.tail` truncation）
- The ツールチップの位置はカーソル位置基準（具体的位置は Open Questions）

### ブラウザ起動
- When ユーザーがイベント円弧を左クリックしたとき、デフォルトブラウザで Google Calendar の今日のビュー URL が開く
- The URL は `https://calendar.google.com/calendar/u/0/r/day/YYYY/MM/DD` 形式（YYYY/MM/DD はイベントの開始日）
- If ユーザーがリング外（中心領域や時計外）をクリックしたとき、then 何も起きない（無音）

### Calendar.app 統合の撤去
- The `ical://` / `ical://ekevent/` URL scheme を使うコードが Toki に存在しない
- The `NSAppleScript` を使うコードが Toki に存在しない
- The `Info.plist` から `NSAppleEventsUsageDescription` キーが削除されている

### 既存挙動の維持
- The 中央 3 行テキストは spec 001 通りの挙動（時刻 / 現在の予定 / 残り or 次まで or 予定なし）
- The 下部「次の予定」ラインは spec 002 通りの挙動（2 行 wrap 可）
- The 円弧クリックによる外部起動以外の機能（タイマー、wake 対応、メニューバートグル、右クリック終了）は無変更
- The Domain / Infrastructure 層は無変更（テスト 36 ケース全 pass を維持）

## Domain Model

本 iteration は UI + Composition 層の変更が中心で、Domain には変更なし。

UI 層に追加されるツールチップ表示状態の型：

```
TooltipState (UI 層 Value Object)
  - startEndLabel: String  // "14:00 - 15:00" 形式
  - title: String
  - position: CGPoint      // 表示位置（Canvas のローカル座標）
```

ホバー検出は `ClockFaceCanvas` 内で SwiftUI の `.onContinuousHover` または同等のジェスチャ修飾子で行う（実装詳細は plan で）。

**Invariants（不変条件）**：
- ツールチップは「ホバー中のイベントが存在する」場合のみ非 nil
- `startEndLabel` は HH:MM - HH:MM の固定フォーマット
- 終日イベントは `RenderableEvent` の生成元で既に除外済み（spec 001 §DayTimeline.make 通り）のためツールチップ対象外

**変換責務**：
- Event の開始/終了 Date → "HH:MM - HH:MM" 文字列は ViewModel 側の純関数で行う（Domain 層を巻き込まない）

## Open Questions

実装着手前に判断したい論点：

### UX
1. **ツールチップ位置**：カーソル右下、右上、上、それとも円弧の外側（時計の外周方向）固定？ MVP は「カーソル位置のオフセット 8pt 右下」と置いて、画面端での反転は後送りで OK か
2. **ツールチップのスタイル**：システム標準のツールチップ風（半透明背景＋角丸）か、Toki 独自スタイル（黒背景＋白文字 等）か。SwiftUI の `.help()` modifier も検討対象
3. **ホバー判定のレスポンス時間**：即時表示 vs 100ms 等のディレイ。即時の方が直感的だが連続ホバーで点滅するリスク
4. **クリック後の挙動**：ブラウザ起動だけで OK か、Toki ウィンドウを minimize/隠す等の追加挙動が必要か（恐らく不要、現状維持で OK）

### 描画
5. **ツールチップの z-index**：時計盤の上、針の上、もちろん中央テキストの上で描画されるべき → ZStack の最前面で OK か
6. **ツールチップがウィンドウ端で見切れる場合**：MVP では見切れ許容、Phase 2 で反転？

### 技術
7. **ホバー検出方式**：`.onContinuousHover { phase in ... }` で `phase.location` を取り、`hitTest` する形が SwiftUI 14+ で素直。代替案として `NSTrackingArea` + `NSHostingView` の組み合わせもあり
8. **複数イベント重なり時の優先順位**：`hitTest` の現実装（配列順で最初に当たったもの）に従う方針で OK か。spec 001 §「earliest start wins」フィルタで重なりが 1 段に正規化されているため、現実には複数当たることは少ないはず
9. **URL の `/u/0/`（アカウントインデックス）の扱い**：ユーザーが複数 Google アカウントを使っている場合、`u/0` ではなく `u/0/`（自動選択）で問題ないか。MVP は固定値で OK か
10. **ホバー中にクリックが発生した場合の挙動**：ツールチップを消してからブラウザ起動 vs そのまま並行。前者の方が UX 的に綺麗

## Out of scope / Phase 2 以降

- **Phase 2**：ツールチップ内のアクションボタン（「ブラウザで開く」「Meet 参加」「コピー」等）、Google Meet 自動検出、画面端でのツールチップ位置反転
- **Phase 3**：Outlook / Exchange イベント用の web URL（`outlook.office.com` 等）の対応、ユーザーがブラウザ起動先を選択できる設定 UI
- **将来検討**：Google Calendar API での直接連携（OAuth フロー、より詳細な情報取得）、編集機能
