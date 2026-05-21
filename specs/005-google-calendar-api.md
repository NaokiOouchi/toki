# 005 — Google Calendar API 経由の event detail URL 取得

## Why

spec 003 でクリック → Google Calendar 今日ビューを実装、spec 004 で event detail URL（`/r/event?eid=<base64>`）を reverse-engineering で構築する形に強化したが、**実機検証で限界が判明**した：

### 解決済み（spec 004）
- 純粋な Google event（`@google.com` で終わる iCal UID）の detail URL 生成
- 繰り返しイベントの `_R<date>` suffix 除去
- Exchange 風 `/RID=<digits>` suffix 除去
- `authuser` パラメータでアカウント切り替え
- URL form を `www.google.com/calendar/event?eid=...&authuser=...`（canonical share URL）に統一

### 残った問題
- **Workspace アカウント（例：`naoki.ouchi@pokotech.dev`）の event** で `event not found` エラー or リダイレクト
- Google 側が「この予定は見つかりませんでした」を返す
- ユーザーが手動で確認した「動く URL」では eid の中身が **`_<base32hex(binary_GOID)>_<UTCdate>Z <email>`** という特殊なエンコード形式
- これは Exchange/Outlook 経由で同期された event を Google 側が独自エンコードした URL であり、Google API へのアクセスなしで再現不可能

### 業界の解決方法
Chrome 拡張「Checker Plus for Google Calendar」のソース解析（v45.1）で判明：
- `manifest.json` に `oauth2` block：`client_id` + `scopes`（`auth/calendar` 等）
- 各 event の URL は **`event.htmlLink`**（API レスポンス内のフィールド）を直接使う
- 自前で eid を組み立てる箇所はゼロ
- → **Google Calendar API 経由が業界標準で、reverse-engineering 不要**

### 本 spec の意義
EventKit ベースで取得した event のうち、**Google 系 event のみ Google Calendar API で `htmlLink` を引き、確実な detail URL を取得**する。非 Google event は spec 003 / 004 のまま今日のビュー fallback。

## Goal

Phase 1.8（本 iteration 完了時）に達成する状態：

1. 初回起動時、ユーザーがブラウザで Google OAuth consent → アクセストークン取得 → Keychain 保存
2. 起動後の event 取得時、EventKit から得た「@google.com で終わる externalIdentifier を持つ event」に対して、Google Calendar API でその event の `htmlLink` を引いて Domain `Event` に保持
3. 円弧クリック時：
   - `htmlLink` があればそれを `NSWorkspace.shared.open`
   - なければ非 Google event とみなして今日のビュー fallback（spec 003 挙動）
4. ENEOS 等の Workspace+Exchange ハイブリッド event でも、API 経由の `htmlLink` で **確実に detail に到達**できる
5. spec 004 で構築した eid ロジック（`googleEventDetailURL` / `normalizeGoogleUID` 等）は削除（API 経路に置き換え）
6. 既存 Domain テスト 36 ケースは pass を維持（Domain 層のフィールド追加は許容）
7. 外部ライブラリ追加なし（CLAUDE.md 遵守）。OAuth + REST を URLSession + Security Framework で自前実装
8. Token のリフレッシュ・期限切れ・revoke を最小限ハンドリング

## Non-goals

本 iteration では明示的にやらない：

- **全 event の API 取得**：時計表示の event list は EventKit が source of truth、API は detail URL 取得の補助のみ
- **イベント編集機能**：spec 001 から引き続き対象外、`htmlLink` で Google 側に委譲
- **複数 Google アカウントの並列対応**：MVP は **OAuth は 1 アカウント分のみ**保持、複数アカウント切り替え UI は Phase 3 以降
- **設定 UI**：OAuth 接続/解除のための minimal な menu item 程度に留める、フルの設定 view は Phase 3
- **非 Google event の web 詳細**（Outlook / iCloud 等）：今日のビュー fallback のまま
- **Google Tasks / その他 Google サービス**：scope は `calendar.readonly` のみ
- **キャッシュの最適化**：シンプルな in-memory cache のみ、永続キャッシュは Phase 3
- **GoogleSignIn / GoogleAPIClientForREST 等の SDK 採用**：自前 OAuth + URLSession
- **複数の calendar スコープ**：`calendar.readonly` だけで足りる、`calendar.events` 等は不要
- **OAuth client_id の hard-code ビルド配布**：本ツールは個人利用、ユーザー自身が Google Cloud Console で OAuth Client を作成する想定。client_id は Keychain or 設定ファイル経由で注入

## Acceptance Criteria

### OAuth 設定とフロー

- The アプリは macOS Keychain に Google OAuth の access token と refresh token を保持できる
- When ユーザーがメニューバーの右クリックメニューから「Google Calendar 接続」を選んだとき、デフォルトブラウザで Google OAuth consent URL が開く
- The OAuth フローは **loopback redirect**（`http://localhost:<port>`）で code を受け取る方式を採用する
- When consent 完了後、アプリは code を access token / refresh token に交換し Keychain に保存する
- If access token が期限切れの場合、then アプリは refresh token で自動更新する
- When ユーザーがメニューバーから「Google Calendar 切断」を選んだとき、Keychain から token を削除する
- The OAuth client_id と client_secret は **コードに hard-code せず**、初回起動時にユーザーが設定（例：`~/.config/toki/oauth.json` or 設定 UI 経由）

### API 経由の htmlLink 取得

- When EventKit から event を取得した直後、`externalIdentifier` が `@google.com` を含む event に対して Google Calendar API で `events.list` または `events.get` を呼び出し `htmlLink` を取得する
- The API 呼び出しは event の **`iCalUID` をキーに照合**する（Google API は `iCalUID` パラメータをサポート）
- If API が認証エラー（401）を返した場合、then refresh token で再試行する
- If 再試行も失敗した場合、then `htmlLink` を nil のままにして fallback 経路に流す
- The API 呼び出しは **EventKit fetch ごとに 1 回**まとめて行い、N+1 問題を避ける（複数 event を一括取得 or 短時間内のリクエストはローカルキャッシュ）

### Domain 影響

- The `Event` Domain type に `webURL: URL?` を追加（API から取得した `htmlLink`、非 Google event は nil）
- The `RenderableEvent` UI 型にも `webURL: URL?` を伝播
- The `Event.failable init` の不変条件は変えない
- The 既存 Domain テスト 36 ケースは無変更で全 pass する

### クリック挙動

- When ユーザーが円弧をクリックしたとき：
  - If `event.webURL` が nil でない、then その URL をブラウザで開く（Google event の確実な detail URL）
  - else, 今日のビュー（`/r/day/YYYY/MM/DD`）にフォールバック（spec 003 / 004 挙動を維持）
- The spec 004 で導入した `googleEventDetailURL` / `normalizeGoogleUID` / `utcOccurrenceDateString` は **削除**（API 経路に置き換え）
- The `googleCalendarDayURL` は **維持**（fallback として使用）

### 既存挙動の維持

- The OAuth 未接続時、アプリは spec 004 の挙動を維持（reverse-engineered eid URL）
- The OAuth 接続後、Google event は `htmlLink` 経由、それ以外は今日のビュー fallback
- The 時計の表示・ホバーツールチップ・中央 3 行・下部「次の予定」・メニューバートグル・終了メニューは無影響

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
  - calendarTitle: String
  + webURL: URL?    // 新規：Google API の htmlLink、非 Google event は nil
```

**Invariants**：既存通り。新規制約なし。

### `RenderableEvent`（既存、フィールド追加）
```
RenderableEvent (UI 層 VO)
  - 既存フィールド
  + webURL: URL?
```

### `GoogleOAuthClient`（Infrastructure 層、新規）

```
GoogleOAuthClient (final class)
  - クライアント設定（client_id, client_secret, scopes, redirect_uri）
  + isAuthorized: Bool
  + beginAuthorization() async throws -> URL  // ブラウザで開く URL を返す
  + completeAuthorization(code: String) async throws  // code → token 交換
  + getValidAccessToken() async throws -> String  // 期限切れなら自動 refresh
  + revoke() async throws  // Keychain から削除
```

### `GoogleCalendarAPI`（Infrastructure 層、新規）

```
GoogleCalendarAPI (final class)
  - oauthClient: GoogleOAuthClient
  + fetchHTMLLinks(forICalUIDs uids: [String]) async throws -> [String: URL]
    // 複数 iCalUID を一括検索、{iCalUID: htmlLink} のマップを返す
```

### `EventKitGateway`（既存、振る舞い拡張）

`fetchTodayTimeline()` の挙動：
1. EventKit から `EKEvent` 配列取得（既存）
2. `convert(_:)` で `Event` 変換（既存、`webURL: nil` で初期化）
3. **新規**：`@google.com` を含む `externalIdentifier` の event を集めて `GoogleCalendarAPI.fetchHTMLLinks(forICalUIDs:)` を呼ぶ
4. **新規**：取得した `htmlLink` を該当 event の `webURL` に詰めなおして返す（new struct でラップ）
5. `DayTimeline.make` に渡す（既存）

**設計判断**：
- Domain `Event` には `webURL` のセッターを生やさない（immutable）。Gateway 内で「API 結果を反映した新 Event を作る」形にする
- API 失敗は silent fail（webURL = nil）、ログのみ出力。clock 表示は止まらない

## Open Questions

実装着手前に判断したい論点：

### OAuth 設計
1. **client_id / client_secret の保管**：ユーザーが Google Cloud Console で OAuth Client（Desktop アプリ）を作成する前提。アプリは初回起動時に **`~/.config/toki/oauth.json`** に書く形か、**メニューバー設定 UI で入力** させる形か
2. **redirect_uri**：loopback `http://localhost:<port>` で良いか。ポート番号は固定（例：`8081`）か動的取得か
3. **token 保存先**：macOS Keychain（Security Framework）を直接使うか、Apple Keychain が面倒なら一旦 `UserDefaults` でも MVP として可とするか（**Keychain 推奨**）
4. **OAuth フロー中の UX**：ブラウザで consent → loopback で受領中に Toki ウィンドウはどう振る舞うか。「接続中…」のラベル表示？

### API 呼び出し設計
5. **`events.list` vs `events.get`**：events.list は `iCalUID` でフィルタ可能（1 リクエストで全 calendar 横断）、events.get は calendar_id + event_id が必要で N 回呼ぶ。**events.list 推奨**だが calendar が多いと遅い可能性
6. **多 calendar 跨ぎ**：1 ユーザーが複数 calendar を購読しているケース。`calendars.list` で全 calendar 取得 → 各 calendar に対して `events.list` を呼ぶか、全 calendar スパンでサーチできる方法があるか（要 API 仕様調査）
7. **API レート制限**：Google Calendar API は 1秒10リクエスト / 1日100万リクエストが目安。MVP 範囲なら問題ないが、念のため retry/backoff を入れるか
8. **キャッシュ**：iCalUID → htmlLink マップを memory にキャッシュして、`EKEventStoreChanged` 通知時のみ再取得するか、N 分間隔か

### Domain / UI 影響
9. **`Event.webURL: URL?` の Optional**：webURL が nil のときに今日のビュー fallback、というルールを Composition / UI どっちで判定するか（**ViewModel 内 `handleArcTap` 推奨**）
10. **OAuth 未接続時の UX**：「ホバー時のツールチップ右上に「Google 接続未」アイコン表示？」「メニューバー右クリックで「接続」項目が出るだけ」が MVP に妥当か
11. **複数アカウント対応**：ユーザーが複数の Google アカウントを持ち、それぞれ別の calendar を見たい場合の対応は Phase 3 で良いか

### CLAUDE.md 抵触
12. **「外部ライブラリ追加禁止」**：OAuth + REST を自前で書く方針で問題ないか。AppAuth-iOS など使うと楽だが規約抵触
13. **「設定 UI は Phase 3」**：OAuth 接続のためには最小限の入力 UI が必要（client_id 入力など）。MVP として許容するか or `~/.config/toki/oauth.json` 経由で UI なしで済ますか

## Out of scope / Phase 2 以降

参考：

- **Phase 2**：複数 Google アカウントの並列対応、OAuth 接続状態の UI（ツールチップ等で「未接続」インジケータ）、永続キャッシュ
- **Phase 3**：完全な設定 UI（client_id 入力 / 接続管理 / calendar 選択）、Outlook / iCloud event 用の web 詳細 URL 対応、token revoke の自動化（長期未起動時）
- **将来検討**：Toki 配布パッケージ用の OAuth client_id 統合（個人利用前提で先送り）、Apple Sign In 統合（不要のはず）、Google Calendar API rate limit のグローバル管理
