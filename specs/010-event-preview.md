# 010 — In-app event preview

## Why

spec 003 以降、円弧クリックは「Google Calendar の event detail を新しいブラウザタブで開く」挙動。spec 005/006 で webURL 取得が安定し確実に詳細ページに到達できるようになったが、**毎回ブラウザにフォーカスを奪われる摩擦**が残っている。

実用中の典型シーン：
- ENEOS の Meet に参加したい → クリック → ブラウザに遷移 → Meet URL 探す → クリック → Meet 起動。**3 ステップ**
- 「定例会、場所どこだっけ？」 → クリック → ブラウザに遷移 → 確認 → アプリに戻る。**集中が切れる**
- 「次の会議、誰参加するんだっけ？」 → 同上、集中が切れる

これを **in-app の popover でその場で確認・行動**できるようにすることで：
- **Meet 参加が 2 クリック**（円弧クリック → Meet ボタン）
- 場所 / 参加者 / 短い description を **アプリ内で完結**確認
- 必要なときだけブラウザに飛ぶ（ボタンで明示的に）

spec 008 plan §Non-goals で「in-app event preview は spec 009 候補」と明示されていた項目。spec 009 は設定 UI 後追い化で使ったため、本 spec で正式実装する。

## Goal

Phase 2.6（本 iteration 完了時）に達成する状態：

1. **円弧クリックで popover overlay 表示**：従来のブラウザ即起動を置き換え
2. **popover 内容**：時刻範囲 / タイトル / 場所 / 参加者リスト / description 要約
3. **アクションボタン**：「Meet で開く」（`hangoutLink` あれば）/ 「Google Calendar で開く」（既存挙動）
4. **閉じる**：外側クリック / ESC キー / 右上 × ボタン
5. **全 event で popover 表示**（実装中に方針変更）：busy block / 共有 event を含めて常に popover を開き、Calendar ボタンは `webURL` 非 nil なら detail、nil なら day view fallback で開く。当初仕様の「popover 非表示で day view 直行」より UX 一貫性を優先（commit `7ad9f12` で変更）
6. **Liquid Glass material 適用**（macOS 26+、25 以下は `.regularMaterial` fallback）
7. **ホバーツールチップは無変更**：軽い情報はホバー、詳細はクリック、という階層
8. **Domain `Event` 拡張**：`attendees` / `location` / `description` / `meetURL` フィールド追加
9. **Domain テスト 36 ケース全 pass**：既存テストはヘルパに `attendees:` 等のデフォルト引数追加で吸収、ロジックは無変更

## Non-goals

本 iteration では明示的にやらない：

- **参加可否操作**（accept / decline / tentative）：`calendar.events` write scope への昇格 + OAuth 再認可が必要、Phase 3
- **description のリッチテキスト表示**：HTML / Markdown レンダリングは過剰、plain text で先頭 N 文字のみ
- **添付ファイル一覧表示**：Phase 3
- **通知 / アラーム設定 / 編集**：Phase 3
- **複数日 navigation**（C2）：別 spec
- **重なりイベントの 2 段リング**（C3）：別 spec
- **LaunchAtLogin**（C4）：別タスクで軽く対応
- **複数 Google アカウント並列**（C5）：Phase 3
- **popover 内 event の編集機能**：CLAUDE.md 禁止事項「イベント編集機能の実装」
- **popover の位置記憶**：常にクリック位置近くに表示
- **会議参加 URL を popover 内で直接埋め込み表示**：Meet ボタンで NSWorkspace.open のみ

## Acceptance Criteria

### 表示制御

#### popover の開閉
- When 円弧をクリック（既存 `handleArcTap`）したとき、event 種別に関わらず popover overlay を表示する（commit `7ad9f12` で全 event に統一）
- When `webURL` が nil（busy block / 共有 event）のとき、Calendar ボタンは day view fallback を開き、Meet ボタンは非表示
- When 外側クリックしたとき、popover を閉じる
- When ESC キー押下したとき、popover を閉じる
- When popover 内の × ボタンをクリックしたとき、popover を閉じる
- When 別の円弧をクリックしたとき、現在の popover を閉じて新しい event の popover を開く

#### popover の位置
- The popover はクリックされた円弧の方向（時計の中心から外側）に向けて配置される
- The popover が画面外にはみ出る場合は、ClockView 内に収まるよう X/Y 軸独立に位置反転する（既存 tooltip と同じロジック流用）
- The popover サイズは横 280pt 程度、縦は内容に応じて可変（最大 400pt）

### 表示内容

#### 必須要素
- The 時刻範囲（"14:00 - 15:00" 形式、ホバーツールチップと同じ）
- The タイトル（最大 2 行、3 行目以降は省略）
- The 場所（あれば、最大 1 行）
- The 参加者リスト（あれば、最大 5 名、超過時は「他 N 名」）
- The description（あれば、最大 3 行 / 200 文字、超過時は省略）

#### アクションボタン
- The 「Meet で開く」ボタン（`event.meetURL` が非 nil のときのみ表示）：クリックで `NSWorkspace.shared.open(meetURL)`
- The 「Google Calendar で開く」ボタン（既存挙動の踏襲）：クリックで `NSWorkspace.shared.open(webURL)`、両ボタンクリック後は popover を閉じる
- The 右上 × ボタン：popover を閉じる

#### スタイル
- The 背景は Liquid Glass（macOS 26+）/ `.regularMaterial`（macOS 25 以下）
- The 角丸 12pt、ボーダー `themeColor.opacity(0.5) / 0.75pt`（既存 ClockView と整合）
- The shadow（既存 EventTooltip と同様）
- The 設定 UI で導入した `textScale` を反映

### Domain 拡張

#### `Event` への追加フィールド
```
Event (Value Object)
  + location: String?              // 場所文字列
  + description: String?           // event description（plain text、改行込み）
  + attendees: [Attendee]          // 参加者リスト（空配列許容、nil は非対応）
  + meetURL: URL?                  // hangoutLink から抽出
```

不変条件は変えない（`!id.isEmpty`、`start < end`）。`Equatable` は id ベース維持。

#### `Attendee` 新規 Value Object
```
Attendee (Value Object)
  - email: String
  - displayName: String?
  - responseStatus: ResponseStatus  // .accepted / .declined / .tentative / .needsAction / .unknown
```

#### `ResponseStatus` enum
- `.accepted` / `.declined` / `.tentative` / `.needsAction` / `.unknown`
- Google API の `responseStatus` 文字列（`accepted` / `declined` / `tentative` / `needsAction`）から変換
- UI で簡易アイコン表示

### Infrastructure

#### `GoogleAPIEvent` 拡張
- `location: String?` 追加
- `description: String?` 追加
- `attendees: [GoogleAPIAttendee]` 追加
- `hangoutLink: URL?` 追加（`event.hangoutLink` から）
- 追加で `conferenceData.entryPoints[type=video].uri` も meetURL fallback として参照（任意）

#### `GoogleCalendarAPI.parseEvent` 拡張
- 上記フィールドを JSON から抽出
- attendees 配列のパース

#### `GoogleCalendarGateway.convert` 拡張
- `GoogleAPIEvent` → `Event` 変換時に新フィールドをセット

### UI

#### 新規 `EventPreviewPopover`（仮）
- `Sources/Toki/UI/EventPreviewPopover.swift` 新規
- 必須要素 + アクションボタン + close button
- Liquid Glass background ヘルパ流用
- `textScale` 受け取り
- close callback（外側クリック / ESC / × ボタンのハンドラ）

#### `ClockView` 拡張
- `@State previewedEvent: RenderableEvent?` 追加
- 既存 tooltip overlay と同階層で popover overlay を表示
- 外側クリック検出のため透明 backdrop（`Color.clear.contentShape(Rectangle()).onTapGesture`）
- ESC キーは `keyboardShortcut(.escape)` をボタンに付けるか、`onKeyPress(.escape)` を使う

#### `ClockViewModel.handleArcTap` 変更
- 既存：`NSWorkspace.shared.open(url)` を即時実行
- 新規：`webURL` 非 nil なら `previewedEvent = event` を ViewModel に保存（@Published）→ View が popover を開く
- `webURL` nil なら従来通り今日のビュー fallback

### 既存挙動の維持

- The ホバーツールチップは既存通り（時刻 + タイトル、軽い表示）
- The 円弧クリックは popover に置き換わるが、busy block は今日のビュー fallback で挙動同等
- The OAuth フロー / メニュー / リサイズ / 透過率 / テーマカラー等の設定 UI 11 軸は無変更
- The Google API ポーリング 2 分、focus reload、最終更新表示は維持

## Domain Model

### 拡張版 `Event`

```swift
struct Event: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let calendarColor: CGColor
    let webURL: URL?
    let location: String?         // 新規
    let description: String?      // 新規
    let attendees: [Attendee]     // 新規（空配列許容）
    let meetURL: URL?             // 新規

    init?(id:title:start:end:calendarColor:webURL:location:description:attendees:meetURL:)
}
```

### 新規 `Attendee`

```swift
struct Attendee: Equatable {
    let email: String
    let displayName: String?
    let responseStatus: ResponseStatus
}

enum ResponseStatus: String, Equatable {
    case accepted, declined, tentative, needsAction, unknown
}
```

## Open Questions

実装着手前に判断したい論点：

### popover 設計
1. **popover 実装方式**：SwiftUI `.popover()` / `NSPopover` / カスタム overlay（既存 tooltip 流儀）。**カスタム overlay 推奨**：Canvas クリックを起点にする都合上、anchor view が無い。tooltip と同じ流儀で実装
2. **背景クリックで閉じる検出**：透明 backdrop View を popover の後ろに配置、`onTapGesture` で close。**採用推奨**
3. **ESC キー検出**：popover 内 button に `keyboardShortcut(.escape)` / `onKeyPress(.escape)` modifier。macOS 14+ の SwiftUI API を活用
4. **popover のサイズ**：固定 vs 内容可変。**内容可変** 推奨、ただし min 200x140 / max 400x500

### 表示内容
5. **参加者の表示数上限**：5 名 / 7 名 / 10 名。**5 名 + 「他 N 名」表示** 推奨
6. **description の長さ**：先頭 N 文字 / N 行。**3 行 or 200 文字、いずれか早い方** 推奨
7. **過去 event でも preview 表示するか**：過去でも見たいことはある。**全 status で表示** 推奨
8. **会議の status アイコン**：参加可否（accepted / declined / tentative）を SF Symbol で表示するか。**MVP は文字 / アイコン表示**（責任分けて、操作はしない）

### Domain 拡張
9. **Attendee の Equatable / id**：email を id 扱い / 別 id フィールド。**email を実質 id として使う、struct Hashable で Set 利用可** 推奨
10. **空 attendees 配列の扱い**：nil vs 空配列。**常に配列、空配列は「参加者なし」**。Optional は避ける
11. **`Event.description` フィールド名と SwiftUI / `CustomStringConvertible.description` の衝突**：プロパティ名は `description` で良いか / 別名（`note` 等）にするか。**別名 `note` 推奨**：`CustomStringConvertible.description` と紛らわしい

### Infrastructure
12. **Meet URL の取得源**：`event.hangoutLink` / `event.conferenceData.entryPoints[type=video].uri` のどちら優先か。**hangoutLink を主、無ければ entryPoints fallback** 推奨
13. **API レスポンスサイズの肥大化**：description / attendees を毎回取ると bandwidth 増。**現状の 2 分ポーリングなら問題なし**。気になるなら events.list の `fields` パラメータで取得項目絞り込み

[NEEDS INPUT] は最大 3 件以下に絞る → 0 件、すべて [CONFIDENT] で着手可能。

## Out of scope / Phase 3 以降

参考：

- **Phase 3**：
  - 参加可否操作（`calendar.events` write scope 昇格 + OAuth 再認可）
  - description のリッチテキスト（HTML / Markdown レンダリング）
  - 添付ファイル一覧表示
  - 通知 / アラーム設定
  - 編集機能（タイトル / 時刻 / 場所変更）
  - リマインダー連携
- **将来検討**：
  - Meet 参加履歴 / 直前ジャンプ
  - Meet 起動時にカメラ / マイク状態をプリチェック
  - 添付 Slack / Notion 等のリンクアイコン化
