# 006 — Google Calendar API 単独運用

## Why

spec 005 で「EventKit から event 一覧を取り、Google Calendar API で `htmlLink` を補強する」Hybrid 構成を実装したが、実機検証で以下の課題が顕在化：

### 課題 1: 初回 setup が 5 ステップで重い
1. macOS System Settings → Internet Accounts → Google アカウント追加
2. Google アカウントの Calendar 同期 ON
3. Toki 起動時に macOS Calendar 権限ダイアログで許可
4. Google Cloud Console で OAuth Client 作成 + `~/.config/toki/oauth.json` 配置
5. Toki 内「Google Calendar 接続」を押して OAuth フロー実行

個人利用ツールでも「macOS 設定 + Google Cloud Console + Toki アプリ内」の 3 箇所を行き来する setup は明らかに重く、CLAUDE.md の「個人利用 / 邪魔にならない」原則からも乖離。

### 課題 2: OAuth 接続後に event が一時的に表示されない事象
`EventKitGateway.fetchTodayTimeline()` 内で `enrichWithHTMLLinks` を **await** しているため、Google Calendar API のレスポンスが返るまで timeline 全体が公開されない。calendars × events の並列スキャンで数秒〜十数秒かかるケースで「予定が消える」UX 退行が発生（実機確認済み）。

### 課題 3: 実質的に EventKit 経由のメリットが薄い
debug log から、ユーザーの全 event が以下のいずれかであることが判明：
- 純粋な Google event（`@google.com` で終わる iCal UID）
- Workspace 経由の Exchange 互換 event（保存先は Google、UID 形式が Exchange GOID）

両者とも **Google Calendar API の `events.list` で取得可能**。EventKit 経由でしか取れない iCloud / 別ドメインの Exchange / その他 CalDAV は使われていない。

### 結論
本 spec で **Google Calendar API 単独運用に移行**し、EventKit 依存を撤去する。setup は 3 ステップに削減、コードベースも単純化される。Hybrid 由来の競合（cache invalidation の二重化、reload タイミング等）も解消。

## Goal

Phase 1.9（本 iteration 完了時）に達成する状態：

1. **EventKit 依存の完全撤去**：`EventKitGateway` および EventKit 関連の import / Info.plist `NSCalendarsUsageDescription` を削除
2. **Google Calendar API のみで event 取得**：`GoogleCalendarGateway` が `events.list` で今日の event を `timeMin`/`timeMax` 範囲で取得し、Domain `Event` を生成
3. **3 ステップ setup**：(1) Google Cloud Console で OAuth Client 作成、(2) `~/.config/toki/oauth.json` 配置、(3) Toki 内「Google Calendar 接続」
4. **graceful 未接続 state UX**：OAuth 未接続時も時計の針・時刻表示は維持、中央 3 行に「Google Calendar 未接続」を表示、右クリック → 接続への導線を明示
5. **接続後の即時表示**：OAuth 完了後、event 取得 → 時計に円弧表示が即時開始
6. **イベント詳細 URL は常に `htmlLink`**：API レスポンスに含まれる canonical URL を使うため、reverse-engineering 系の不安定さは根絶
7. **既存 UX の維持**：ホバーツールチップ・中央 3 行・下部「次の予定」・メニューバートグル・終了メニュー・wake 復帰・1 分タイマーの挙動は無変更
8. **Domain 層は無変更**：`Event` / `DayTimeline` / `TimeOfDay` / `EventStatus` および 36 ケースのテストは無修正で全 pass
9. **オフライン耐性低下を受容**：起動時にネットアクセス必須、ネット切断時は「未接続 + 接続済み but fetch 失敗」の表示で fallback

## Non-goals

本 iteration では明示的にやらない：

- **iCloud / 非 Google CalDAV の event 取得**：spec 006 で撤去、機能損失として受容
- **複数 Google アカウント並列取得**：MVP は OAuth 1 アカウントのみ、設定 UI も MVP 範囲外
- **オフラインキャッシュ / 永続キャッシュ**：起動時 fetch + EKEventStoreChanged 廃止、`fetch` 失敗時は last-known timeline 維持のみ
- **完全な設定 UI**：client_id 入力は `~/.config/toki/oauth.json` のまま、UI なし
- **編集機能 / Meet 参加ボタン / アクションボタン**：spec 003〜005 の Non-goals を継続
- **`calendar.events` scope（書き込み）**：`calendar.readonly` のみ
- **アニメーション / 接続中スピナー / フェード**：spec 003 の Non-goals を継続
- **イベント変更通知の自動 reload**：EventKit の `EKEventStoreChanged` 通知が使えなくなるため、N 分ポーリング or 手動 reload 相当の仕組みは Phase 2 行き
- **エラーリトライの細かい指数バックオフ**：spec 005 既存の 1 回リトライで継続
- **新規外部ライブラリ追加**：OAuth/REST は引き続き自前

## Acceptance Criteria

### EventKit 撤去
- The `Sources/Toki/Infrastructure/EventKitGateway.swift` が削除されている
- The `Sources/Toki/Infrastructure/` 配下の Swift コードに `import EventKit` が **0 件**
- The `Resources/Info.plist` から `NSCalendarsUsageDescription` キーが削除されている（macOS の Calendar 権限ダイアログが出ない）
- The `Sources/Toki/App/AppDelegate.swift` で `EventKitGateway()` の呼び出しが削除されている
- The 既存の `htmlLinkCache` ロジックは新 Gateway に持ち越し or 不要になっていれば削除

### Google Calendar Gateway
- The 新規 `Sources/Toki/Infrastructure/GoogleCalendarGateway.swift` が `events.list` で今日（ローカルタイムゾーンの 0:00〜翌 0:00）の event を取得する
- When `oauthClient.isAuthorized == false` のとき、`fetchTodayTimeline()` は **空の `DayTimeline`** を返す（権限要求は別 path で対応）
- When `oauthClient.isAuthorized == true` のとき、全 calendar に `events.list?timeMin=...&timeMax=...&singleEvents=true&orderBy=startTime` を並列実行し、結果を Domain `Event` に変換する
- The Domain `Event` への変換時、`htmlLink` を `webURL` にセットする
- The all-day event（`event.start.date` がある event、`dateTime` がない）は spec 001 §AC「all-day は除外」に従い対象外とする
- If API が 401 を返した場合、then OAuth client 側で refresh、それでも失敗時は silent fail（last-known timeline 維持）

### 未接続 UX
- When `OAuthConfig.load()` が nil（設定ファイル無し）or `oauthClient.isAuthorized == false` のとき、`ClockViewModel.centerState` は「Google Calendar 未接続」を示す
- The 中央 3 行：時刻 / 「—」/「右クリックで接続」のような分かりやすい subtitle を表示する
- The 下部「次の予定」ラインは未接続時は **非表示**
- The 時計の針は通常通り現在時刻を指す（時刻表示自体は接続有無に依存しない）
- The 円弧は未接続時は **0 件描画**（event がないため）

### 接続フロー UX
- When ユーザーが右クリック → 「Google Calendar 接続」を選んだとき、ブラウザで OAuth consent → loopback で受領 → token 保存（spec 005 既存）
- When OAuth 完了後、ViewModel が即時に再 fetch を行い、event を timeline に反映する
- When ユーザーが「Google Calendar 切断」を選んだとき、Keychain クリア + timeline を空にする + 中央表示を「未接続」に戻す（spec 005 既存挙動の維持）

### Domain / テスト無影響
- The `Sources/Toki/Domain/Event.swift` / `EventStatus.swift` / `DayTimeline.swift` / `TimeOfDay.swift` は無変更
- The `Tests/TokiTests/` 36 ケースは無変更で全 pass

### クリック挙動
- The 円弧クリックで `event.webURL`（API から取得した `htmlLink`）を `NSWorkspace.shared.open` で開く
- If `webURL` が nil（理論上ない、防御的）、then `googleCalendarDayURL(for:calendar:)` で今日のビュー fallback（spec 003 の挙動を維持）

### 既存挙動の維持
- The ホバーツールチップは spec 003〜005 通り
- The メニューバートグル / 終了メニュー / wake 復帰 / 1 分タイマーは無変更
- The リング描画 / 時刻マーク / 中心ドット / 針は無変更（spec 002 / 003 の polish 結果を維持）

## Domain Model

本 iteration は Domain 層に変更を入れない。Infrastructure 層を大きく入れ替えるのみ。

### 既存 `Event`（無変更）
spec 005 で `webURL: URL?` を追加済み。Google API レスポンスの `htmlLink` を直接ここに入れる。

### 新規 `GoogleCalendarGateway`（Infrastructure 層）

```
GoogleCalendarGateway (final class)
  - oauthClient: GoogleOAuthClient
  - api: GoogleCalendarAPI
  - calendar: Calendar
  - subject: CurrentValueSubject<DayTimeline, Never>
  + var timelineUpdates: AnyPublisher<DayTimeline, Never>
  + func start()
  + func stop()
  + func reload() async  // 手動再 fetch（接続/切断時に呼ぶ）
  - func fetchTodayTimeline() async -> DayTimeline
```

**役割**：
- `events.list` API で今日の event を取得（全 calendar 並列）
- API レスポンスから Domain `Event` に変換（`htmlLink` を `webURL` に格納）
- `oauthClient.isAuthorized == false` のときは空 `DayTimeline` を返す
- 1 分タイマー or wake 通知で `reload()` を呼ぶのは ViewModel 側

**変換責務**：
- Google API event JSON → Domain `Event` の変換は本 Gateway 内
- all-day event の除外
- 重なり除去 / clip / sort は `DayTimeline.make` に委譲（spec 001 通り）

### `GoogleCalendarAPI` 拡張

spec 005 で `fetchHTMLLinks(forICalUIDs:)` を実装済み。spec 006 で追加：

```
+ func fetchTodayEvents(timeMin: Date, timeMax: Date) async throws -> [GoogleAPIEvent]
```

`GoogleAPIEvent` は Infra 層内の中間型で、API の生 JSON を構造化したもの。Gateway がこれを Domain `Event` に変換する。

`fetchHTMLLinks(forICalUIDs:)` は **削除可能**（spec 005 で導入したが、今後は `fetchTodayEvents` のレスポンスに最初から `htmlLink` が含まれるため不要）。

## Open Questions

実装着手前に判断したい論点：

### Gateway 設計
1. **Gateway 名**：`GoogleCalendarGateway` か `EventGateway`（汎用名）か。将来 iCloud 等の追加を見越して汎用名？ MVP は Google 特化なので `GoogleCalendarGateway` 推奨
2. **all-day event の除外場所**：API 取得時点で除外するか、Gateway で `allDayFlags` を作って `DayTimeline.make` に渡すか（spec 001 と整合）
3. **events.list の `timeMin` / `timeMax`**：ローカルタイムゾーンの 0:00 / 翌 0:00 でいいか、UTC で送るのが安全か（Google API は ISO8601 with offset 推奨）
4. **events.list の `orderBy=startTime` + `singleEvents=true`**：これで recurring も occurrence 単位に展開してくれるはず、要実機検証

### EventKit 撤去の段取り
5. **撤去タイミング**：1 commit で一気に撤去するか、新 Gateway 完成後に削除する 2 phase か。後者の方が安全だが commit 数増える
6. **EventKit 関連 cache / notification**：`EKEventStoreChanged` 通知購読が消えるので「外部変更を検知して即時 reload」できなくなる。手動 reload UI を出すか、N 分ポーリングか、何もしないか（**何もしない、メニューバー右クリックで「再読込」を Phase 2 で追加**を推奨）
7. **`Info.plist`**：`NSCalendarsUsageDescription` 削除、何か追加するキーはあるか（OAuth は HTTP のみなので追加不要、ATS でも `https://` は問題なし）

### 未接続 UX
8. **`CenterState` の拡張**：未接続を表す新ケースが必要か、既存 `freeTime(time:subtitle:)` の subtitle で表現するか（**既存 freeTime で「Google Calendar 未接続」「右クリックで接続」を表現** が薄い、しかし spec 001 から CenterState を拡張する範囲を最小化したい）
9. **「右クリックで接続」の表示文言**：spec 005 の挙動と整合させる、文言は短く

### Refresh / リロード戦略
10. **接続/切断時の即時 reload**：`handleConnect` / `handleDisconnect` で `gateway.reload()` を呼ぶか、ViewModel 経由か。AppDelegate から直接呼ぶのが素直
11. **1 分タイマーで毎回 events.list を呼ぶ？**：時刻表示は更新したいが、event は 1 分ごとに変わらない。**1 分タイマーは `now` 更新のみ、event の reload はもっと低頻度（5 分 or 10 分間隔）か、reload UI 経由 manual**

### CLAUDE.md / 既存挙動
12. **`Event.calendarTitle`**：spec 004 で導入、Google API レスポンスのどのフィールドから取るか（`organizer.email` or `creator.email` ではなく、calendar list の `summary` / `id` を計算時に joining）
13. **dryrun / fallback**：OAuth 未設定（`oauth.json` なし）のときも graceful。`oauthClient = nil` の挙動を AppDelegate で OK にする

## Out of scope / Phase 2 以降

参考：

- **Phase 2**：
  - 右クリックメニューに「再読込」項目追加（手動 fetch）
  - 5 分ポーリング or `gcal_id` を Pub/Sub 等で push 通知（Toki が個人利用なので過剰の可能性大、ただ手動が面倒なら検討）
  - 接続時のスピナー / 接続中ラベル
- **Phase 3**：
  - 複数 Google アカウント並列
  - 設定 UI（client_id 入力 / calendar 選択 / 同期間隔）
  - iCloud / Outlook / 他 CalDAV の direct 連携復活（汎用 Gateway 化）
  - 永続キャッシュ（オフライン耐性向上）
- **将来検討**：
  - Google API の代わりに CalDAV 直接実装で複数ベンダー対応
  - Apple Sign In + iCloud Calendar 連携（macOS 限定の別ルート）

---

## 補足：spec 005 との関係

spec 005 で導入したコンポーネントの本 spec での扱い：

| コンポーネント | 扱い |
|---|---|
| `Sources/Toki/Domain/Event.swift`（`webURL` 追加） | **継続使用** |
| `Sources/Toki/UI/RenderableEvent.swift`（`webURL` 追加） | **継続使用** |
| `Sources/Toki/Composition/ClockViewModel.swift`（`handleArcTap` webURL ベース） | **継続使用**、ただし `googleCalendarDayURL` fallback は防御として残す |
| `Sources/Toki/Infrastructure/KeychainStore.swift` | **継続使用** |
| `Sources/Toki/Infrastructure/OAuthConfig.swift` | **継続使用** |
| `Sources/Toki/Infrastructure/LoopbackOAuthReceiver.swift` | **継続使用**（spec 005 後半の continuation 二重 resume fix 含む） |
| `Sources/Toki/Infrastructure/GoogleOAuthClient.swift` | **継続使用** |
| `Sources/Toki/Infrastructure/GoogleCalendarAPI.swift` | **拡張**：`fetchTodayEvents(timeMin:timeMax:)` 追加、`fetchHTMLLinks(forICalUIDs:)` は **削除可** |
| `Sources/Toki/Infrastructure/EventKitGateway.swift` | **削除** |
| `Sources/Toki/App/AppDelegate.swift`（OAuth メニュー） | **継続使用**、Gateway 注入先を入れ替え |
| `Resources/Info.plist` の `NSCalendarsUsageDescription` | **削除** |
| 既存 `htmlLinkCache` / `enrichWithHTMLLinks` | **不要、削除**（fetchTodayEvents が一度で `htmlLink` も返すため） |
