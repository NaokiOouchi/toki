# 007 — spec 006 完了後のレビュー後片付け

## Why

spec 006 完了後の `code-reviewer` agent による全体レビューで **HIGH 5 件**の改善点が抽出された。CRITICAL は無く現状でもマージ可能だが、放置するとレガシー化や潜在バグの温床になる：

### H1: refresh 失敗時の UI 復旧経路が抜け
`GoogleOAuthClient.refresh()` は失敗時に Keychain を自動削除する（`GoogleOAuthClient.swift:158-160`）が、`GoogleCalendarGateway.fetchTodayTimeline()` は API 失敗時に `subject.value`（last-known timeline）を返すだけで、`isAuthorized` の変化を ViewModel に通知しない。
結果：refresh token 失効後も `ClockViewModel.accessGranted = true` のまま残り、中央テキストに「右クリックで接続」が **表示されない**。spec 006 §AC「未接続 UX」と矛盾。

### H2 + H3: dead field（`Event.calendarTitle` / `Event.externalIdentifier`）
- `Event.calendarTitle` は spec 004 で reverse-engineered eid 生成のため導入したが、spec 005/006 でクリック挙動が `webURL` 単独になり **どこからも読まれない**
- `Event.externalIdentifier` も同様、`@google.com` 判定や `_R<date>` 解析で使われていたが spec 006 で不要化
- `grep -rn` で読み出し側ゼロを確認、伝播のみのフィールド = Domain 負債

### H4: HTTP status 未検査と 401 retry 抜け
`GoogleCalendarAPI.fetchEvents` 内で 401/403/5xx でも JSON parse を試み、`items` が無ければ空配列で silent fail。`getValidAccessToken` で大半救えるが、API 呼び出し中の token 失効や scope 不足の 403 はキャプチャされず、デバッグが困難。

### H5: `revoke()` の空 if 文
`GoogleOAuthClient.revoke()` で `if let http = ..., !(200...299).contains(http.statusCode) { }` の中身が空。コメントだけ「Keychain は必ず削除する」と書かれているが、コードとしては何もしていない空ブロック = ノイズ。

### 補足：SPEC.md と Event 定義の乖離
SPEC.md §5 の Event 定義には `calendarTitle` / `webURL` が載っていないが、現コードには両方ある。本 spec で `calendarTitle` を削除し、`webURL` だけ SPEC.md に追記する形で整合させる。

## Goal

Phase 1.10（本 iteration 完了時）に達成する状態：

1. **`isAuthorized` の変化が ViewModel に伝わる**：refresh 失敗 / revoke 後にも `accessGranted` が自動同期され、中央テキストが「右クリックで接続」に切り替わる
2. **Domain `Event` から `calendarTitle` 削除**：reading なし → field 不要
3. **Domain `Event` から `externalIdentifier` 削除**：reading なし → field 不要
4. **`RenderableEvent` から `calendarTitle` / `externalIdentifier` 削除**：伝播もろとも撤去
5. **`GoogleCalendarAPI.fetchEvents` で HTTP status を検査**：401 → 1 回 retry、それ以外は log + 空配列
6. **`GoogleOAuthClient.revoke()` の空 if 文を log 1 行に置換**：意図を残しつつコードを綺麗に
7. **SPEC.md §5 を整合**：`calendarTitle` 削除、`webURL` 追記
8. **Domain テスト 36 ケースは無変更で全 pass**（ヘルパから引数を削除するだけ）

## Non-goals

本 iteration では明示的にやらない：

- **Phase 2 機能**：右クリック「再読込」、ウィンドウ位置 `UserDefaults` 記憶、接続中スピナー
- **新規 protocol 切り出し**（CLAUDE.md「protocol を念のため切らない」継続）
- **新規外部ライブラリ追加**
- **追加 UI 変更**（時計描画 / ホバー / メニュー構造は無変更）
- **OAuth フロー全体の見直し**（PKCE 実装は spec 005 のまま継続）
- **エラー再試行の指数バックオフ等高度化**：H4 は単純な 1 回 retry まで
- **新規 Domain テスト追加**：webURL 等の値伝播テスト追加は MEDIUM、本 spec では対象外
- **`print` → `os_log` への置換**：MEDIUM の M1 は本 spec では対象外（Phase 2 で）
- **コードレビュー M2〜M6 / LOW 全件**：本 spec の対象外、必要なら spec 008 以降

## Acceptance Criteria

### isAuthorized 同期（H1）
- The `GoogleCalendarGateway` が `isAuthorized` の変化を 1 系統で公開する（`@Published` プロパティ or Publisher）
- When `GoogleOAuthClient.refresh()` が Keychain クリアした直後、ViewModel の `accessGranted` が **次の reload サイクル内**に `false` に同期される
- When ユーザーが OAuth 切断した直後（`AppDelegate.handleDisconnect` 完了後）、同じく `accessGranted = false` になり中央テキストが「右クリックで接続」に切り替わる
- The 既存の `gateway?.timelineUpdates` 購読は維持

### Event から dead field 削除（H2 + H3）
- The `Sources/Toki/Domain/Event.swift` から `calendarTitle: String` および `externalIdentifier: String?` が削除されている
- The `init?(id:title:start:end:calendarColor:webURL:)` の引数から `calendarTitle` / `externalIdentifier` が削除されている
- The `Equatable` は id ベース維持（無変更）
- The `Sources/Toki/UI/RenderableEvent.swift` からも `calendarTitle` / `externalIdentifier` が削除されている
- The `ClockViewModel.canvasEvents` の `RenderableEvent` 初期化からも該当引数が削除されている
- The `Sources/Toki/Infrastructure/GoogleCalendarGateway.convert(_:)` の `Event(...)` 呼び出しからも該当引数が削除されている
- The `Sources/Toki/Domain/DayTimeline.swift` の `clip(_:)` 内 `Event(...)` 呼び出しからも該当引数が削除されている
- The 3 つのテストファイル（`EventTests.swift` / `EventStatusTests.swift` / `DayTimelineTests.swift`）の `makeEvent` ヘルパから `calendarTitle: String = ""` / `externalIdentifier: String? = nil` 引数が削除されている
- The 既存 Domain テスト 36 ケースは無変更で全 pass する

### GoogleCalendarAPI HTTP status 検査（H4）
- The `Sources/Toki/Infrastructure/GoogleCalendarAPI.swift` の `fetchEvents(in:timeMin:timeMax:token:)` で HTTP status が 200 系でない場合 log 出力する
- If status が **401** のとき、then `getValidAccessToken()` を再度呼んで新しい token で **1 回だけ retry** する
- If retry も 200 系以外、then 空配列 + log で silent fail
- The 既存の network error catch（do/catch）は維持

### revoke 空 if 文整理（H5）
- The `Sources/Toki/Infrastructure/GoogleOAuthClient.swift` の `revoke()` の空 if 文を削除
- 代わりに status code が 200 系でない場合は `print` で 1 行 log
- Keychain クリアは引き続き必ず実行（成功 / 失敗どちらでも）

### SPEC.md 整合
- The `SPEC.md` §5「ドメインモデル」の Event 定義から `calendarTitle` を削除
- The Event 定義に `webURL: URL?` を追記
- The `externalIdentifier` の記述も削除（元から SPEC.md には記載があったが、本 spec で実コードから消すため）

### 既存挙動の維持
- The 時計描画 / ホバーツールチップ / クリック → ブラウザ / メニューバートグル / 終了メニュー / wake / タイマーは無変更
- The ファイル長 < 400 行 / 関数長 < 50 行
- The CLAUDE.md 禁止事項を遵守（protocol 不要切り出し、外部ライブラリ追加、UI/Infra テスト追加なし）

## Domain Model

本 iteration では Domain `Event` を **削減**する：

```
Event (Value Object)
  - id: String
  - title: String
  - start: Date
  - end: Date
  - calendarColor: CGColor
  - calendarTitle: String  ← 削除
  - externalIdentifier: String?  ← 削除
  - webURL: URL?
```

不変条件は変えない（`!id.isEmpty`、`start < end`）。`Equatable` も id ベース維持。

`RenderableEvent` も同じく `calendarTitle` / `externalIdentifier` を削除。

## Open Questions

実装着手前に判断したい論点：

### H1 設計
1. **`isAuthorized` の公開方式**：`@Published var isAuthorized: Bool` を `GoogleCalendarGateway` に持たせるか、別 Publisher を生やすか。後者の方が現在の状態と通知を分けられて綺麗だが、前者の方がシンプル。**前者推奨**
2. **同期トリガー**：`reload()` 完了時に `isAuthorized` を再評価する形か、`Timer.publish` 経由でポーリングするか。**reload() 内で再評価** が現在の挙動と整合
3. **AppDelegate の `viewModel?.refreshAuthorizationState()` 呼び出し**：上記設計で不要になるか、保険として残すか。**保険として残す**（明示性向上）

### H2 + H3 削除
4. **`SPEC.md` の Event 定義の更新**：本 spec で SPEC.md を変える範囲はどこまでか。`calendarTitle` 削除と `webURL` 追記だけにとどめて、`externalIdentifier` 削除も明記する。**3 件すべて明記**
5. **将来 calendar 別の色分けや filter で `calendarTitle` を使う可能性**：今は不要だが将来 Phase 3 で「対象 calendar 選択 UI」を作る時に必要。**Phase 3 で再導入** すれば良いので spec 007 では削除して OK

### H4 retry 設計
6. **401 retry の getValidAccessToken 呼び出し回数**：spec の通り 1 回まで。それでも 401 なら token 失効と判定、refresh は GoogleOAuthClient 内部で 1 回試みる。**1 回 retry のみ**
7. **retry 中の並列他 calendar の影響**：`fetchTodayEvents` の `withTaskGroup` で各 calendar 並列実行中に 1 つで token 失効 → 他の calendar も再試行すべきか。MVP は **個別に 1 回 retry**、複雑化を避ける

## Out of scope / Phase 2 以降

参考：

- **Phase 2**（spec 006 §Out of scope 継続）：右クリック「再読込」、ウィンドウ位置記憶、接続中スピナー
- **Phase 2+**：`print` → `os_log` 共通化（コードレビュー M1）、ISO8601Formatter のキャッシュ（M3）、ClockView 定数の集約（M5）
- **Phase 3**：複数 Google アカウント並列、設定 UI（client_id 入力 / calendar 選択）、`calendarTitle` を「対象 calendar 選択 UI」のために再導入
- **将来検討**：webURL 値伝播の Domain テスト追加、parseQuery の堅牢化、HTTP retry の指数バックオフ
