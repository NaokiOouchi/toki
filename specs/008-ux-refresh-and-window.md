# 008 — データ鮮度 + ウィンドウ調整 + Liquid Glass

## Why

spec 007 完了後の実用フェーズで蓄積された UX pain と、SPEC.md §6 Phase 2 で持ち越された項目を 1 iteration で解決する。あわせて Apple の新デザイン言語 Liquid Glass を視覚レイヤーに導入し、UI の表現力を底上げする。

### 観察された pain

#### データ鮮度の問題（最重要）
- **5 分ポーリング**：Google Calendar 側で event を編集・追加・キャンセルしても、最大 5 分間 Toki に反映されない。会議直前の変更が拾えず、信頼性に欠ける
- **状態が見えない**：いま fetch 中なのか、何分前のデータなのか分からない
- **手動更新の手段が無い**：右クリックメニューには接続切替と終了のみ
- **OAuth 接続中の進捗不明**：「接続」を押した後にブラウザに飛ぶが、Toki 自身が何をしているか分からない

#### ウィンドウの自由度不足
- **背景が透けない**：裏のアプリの内容が見えず、常時前面なのに邪魔に感じる瞬間がある
- **サイズ固定**：280x320 固定、ディスプレイによっては大きすぎ / 小さすぎ
- **透過率調整不能**：他の TUI ツール（aerospace 等）にあるような「少し透けさせる」ができない
- **位置記憶なし**：起動のたびに画面中央付近にリセットされる

#### 共有 event 起動時の挙動
- 他人のカレンダーから共有されている「予定あり」（visibility: `private` または `default` + free/busy 公開）の event をクリックすると、Google Calendar が **"予定あり" のみ表示**するページに飛ぶ。情報が得られず無意味なクリックになる

### Liquid Glass の導入意義

macOS 26 (Tahoe) で導入された Apple 公式の新デザイン言語。Toki のような常時前面型のウィンドウは透過感を活かしやすく、Liquid Glass との相性が良い。SwiftUI の `.glassEffect()` 系 API を活用し、Material 系より自然な視覚効果を実現する。

## Goal

Phase 2.1（本 iteration 完了時）に達成する状態：

### データ鮮度
1. **ポーリング短縮**：5 分 → 1〜2 分に短縮（個人 API 利用量に余裕あり）
2. **手動再読込**：右クリックメニューに「再読込」項目追加、即時 fetch
3. **最終更新表示**：「最終更新 X 分前」を控えめに表示（下部ライン or ツールチップ）
4. **focus reload**：ウィンドウがフォアグラウンドに来た / ユーザーがホバーした瞬間に reload trigger（適度に debounce）
5. **接続中スピナー**：OAuth consent → loopback 受領中に進捗を視覚化

### ウィンドウ調整
6. **背景透過**：ウィンドウ背景を透明 / 半透明にする
7. **ウィンドウサイズ可変**：min / max を設定した上でユーザーがリサイズ可能
8. **透過率調整**：軽量設定 UI（メニューから「設定…」）でスライダー的に調整
9. **ウィンドウ位置記憶**：`UserDefaults` に保存、起動時に復元

### 共有 event 対応
10. **"予定あり" 検出**：API レスポンスの `visibility` フィールド or `summary` のパターンで判定
11. **fallback**：該当 event のクリックは Google Calendar 今日ビュー（spec 003 の挙動）へ

### Liquid Glass
12. **ウィンドウ背景**：Liquid Glass material 適用
13. **ツールチップ**：popover 風 glass 背景
14. **設定パネル**：軽量の glass-style 設定 UI

### 既存挙動の維持
15. **円形時計の描画**：spec 001〜007 の Canvas 描画（リング / 円弧 / 針 / 中心ドット）は無変更
16. **クリック → ブラウザ**：spec 006 の `htmlLink` 経路は維持、共有 event 検出時のみ fallback
17. **OAuth フロー**：spec 005〜007 の loopback PKCE は無変更
18. **Domain テスト 36 ケース**：無変更で全 pass

## Non-goals

本 iteration では明示的にやらない：

- **in-app event preview**：popover で event 詳細表示 + 参加可否操作 + Meet 起動 → **spec 009 で対応**
- **複数日 navigation**：マウスホイール / 横スクロールで前後日 → **Phase 3**
- **OAuth scope 追加**：`calendar.events`（書き込み）は不要、`calendar.readonly` のまま
- **完全な設定 UI**：client_id 入力 UI、calendar 選択は対象外（透過率 / サイズ のみ）
- **複数 Google アカウント並列**：MVP 維持
- **永続キャッシュ / オフラインモード**：起動時 fetch、ネット切断時は last-known
- **EventKit 再導入**：spec 006 撤去継続
- **macOS 25 以下のサポート**：Liquid Glass は macOS 26 必須、25 以下では fallback（既存 Material）
- **ダークモード / ライトモード切替**：OS 設定に追従
- **アクセシビリティ拡張（VoiceOver 等）**：Phase 3

## Acceptance Criteria

### データ鮮度

#### ポーリング短縮（Goal 1）
- The `GoogleCalendarGateway.start()` の Timer interval が **120 秒**（=2 分）に変更されている
- The 既存の 5 分タイマーから短縮されたコメントが残っている

#### 手動再読込（Goal 2）
- The `AppDelegate.showContextMenu` に「再読込」項目が追加されている
- The 「再読込」項目は OAuth 接続済み（`oauthClient.isAuthorized == true`）のときのみ enabled
- When ユーザーが「再読込」をクリックしたとき、`gateway.reload()` が await される
- The 再読込中は項目を一時的に disabled にしても良い（任意）

#### 最終更新表示（Goal 3）
- The `ClockViewModel` に `lastUpdatedAt: Date?` を保持
- The `GoogleCalendarGateway.reload()` 成功時に ViewModel に更新時刻を伝える経路を追加
- The 控えめな位置（下部「次の予定」ラインの右端 or ツールチップ表示エリア）に「最終更新 X 分前」を表示
- When 60 秒未満：「最終更新 たった今」、60 秒以上：「最終更新 X 分前」

#### focus reload（Goal 4）
- When `NSWindow.didBecomeKeyNotification` または `NSApplication.didBecomeActiveNotification` を受信したとき、`gateway?.reload()` を trigger
- The reload は **30 秒以内に複数回呼ばれないよう debounce**（連続フォーカス切替で連発を防ぐ）

#### 接続中スピナー（Goal 5）
- The `ClockViewModel` に `isConnecting: Bool` を保持
- The `AppDelegate.handleConnect` 開始時に `true`、完了 / 失敗で `false`
- The 中央テキストの subtitle として「接続中…」と表示（既存 `.freeTime(time:subtitle:)` を流用）
- The 動的アニメーションは MVP では追加しない（テキスト表示のみ）

### ウィンドウ調整

#### 背景透過（Goal 6）
- The `ClockView.body` の `.background(Color(NSColor.windowBackgroundColor))` を **Liquid Glass material**（macOS 26+）に置換
- If macOS 25 以下、then `.regularMaterial` または半透明 `Color.background.opacity(0.85)` に fallback
- The 既存の `RoundedRectangle(cornerRadius: 12)` clip と stroke は維持

#### ウィンドウサイズ可変（Goal 7）
- The `FloatingClockWindow` の `styleMask` に `.resizable` を追加
- The min size: **220 x 260**、max size: **420 x 500**（妥当な範囲）
- The ClockGeometry が ウィンドウサイズに **比例して**スケールするよう調整（既存 `standard(in:)` がサイズ受け取るので可能）
- The リサイズ中も円弧 / 針 / 中央テキスト が破綻しないこと

#### 透過率調整（Goal 8）
- The `AppDelegate.showContextMenu` に「設定…」項目を追加
- The 「設定…」クリックで小さな設定パネルを表示（既存 FloatingClockWindow と独立した別ウィンドウ or popover）
- The 設定項目：透過率（0.5〜1.0 のスライダー or 段階値）
- The 値は `UserDefaults` に保存、`ClockView` の `.opacity()` に反映
- The 設定パネル自体も Liquid Glass で表示

#### ウィンドウ位置記憶（Goal 9）
- The アプリ終了時に `NSWindow.frame.origin` を `UserDefaults` に保存
- The アプリ起動時に保存された position があれば復元、なければ画面の特定位置（例：右上）に配置
- The 画面構成が変わって position が画面外になる場合は安全な位置（メインスクリーン内）にクランプ

### 共有 event 対応

#### "予定あり" 検出（Goal 10）
- The `GoogleCalendarAPI.parseEvent` レスポンス JSON 内の `visibility` フィールドを `GoogleAPIEvent` の中間型に保持
- The `summary` が "予定あり" / "Busy" / "" のいずれかなら "busy block" と判定する補助ロジックを追加
- The Domain `Event` には **新フィールドを追加しない**（フラグは UI 層でのみ判定、`webURL` の nil 化で表現）

#### fallback（Goal 11）
- When event が visibility=private または summary='予定あり' / 'Busy' のとき、`Event.webURL` を **nil** にする（Gateway の `convert` 内で判定）
- The クリック時、既存 `handleArcTap` の webURL nil 経路で **今日ビューへ fallback**（spec 003 既存挙動）

### Liquid Glass

#### ウィンドウ背景（Goal 12）
- The macOS 26+ のとき、`ClockView.body` 背景に SwiftUI 標準の glass material を適用（`.glassEffect()` 等）
- The Liquid Glass の挙動：背後アプリの内容が屈折的に透けて見える

#### ツールチップ（Goal 13）
- The `EventTooltip` の背景を Liquid Glass material に置換
- The 既存の角丸 / shadow と整合する

#### 設定パネル（Goal 14）
- The 設定 UI（透過率スライダー等）の背景を Liquid Glass material で表示

### 既存挙動

#### 円形時計の描画（Goal 15）
- The `ClockFaceCanvas` の draw* 系メソッドは無変更
- The リング / 時刻マーク / 円弧 / 針 / 中心ドットの描画ロジックは触らない（ウィンドウサイズ変動への適応のみ ClockGeometry 経由）

#### クリック → ブラウザ（Goal 16）
- The `handleArcTap` の webURL 優先 → 今日ビュー fallback の構造は維持

#### OAuth フロー（Goal 17）
- The `GoogleOAuthClient` の PKCE / loopback / Keychain は無変更
- The `LoopbackOAuthReceiver` の二重 resume 防止も維持

#### Domain テスト（Goal 18）
- The 既存 36 ケースは無変更で全 pass
- The 新規 Domain テストは不要（Domain 層への変更なし）

## Domain Model

本 iteration では Domain 層に変更を入れない。Infrastructure / Composition / UI / App 層のみ変更。

`Event` への "busy block" フラグ追加は **しない**：UI 表示には `webURL == nil` で十分に表現でき、フィールド追加は dead field 化リスク。

`GoogleAPIEvent`（Infrastructure 中間型）には `visibility: String?` を追加して、`GoogleCalendarGateway.convert` で webURL を nil 化する判定に使う。

## Open Questions

実装着手前に判断したい論点：

### データ鮮度
1. **ポーリング間隔**：5 分 → 1 分？ 2 分？ Google API クォータは 100 万 req/日で個人利用なら 1 分 = 1440 req/日で全く問題なし。ただし電力 / 帯域考慮で **2 分推奨**
2. **focus reload の debounce**：30 秒？ 60 秒？ 「画面切替の瞬間に最新化したい」が主目的なので、**30 秒** で十分
3. **「最終更新 X 分前」の表示位置**：下部の「次の予定」ライン右端 / 中央テキスト下 / ツールチップ表示エリア / 設定パネル内のみ。**下部右端 が控えめで推奨**
4. **接続中の中央テキスト表現**：既存 `freeTime(time:subtitle:)` の subtitle で「接続中…」にするだけ？ アニメーションは MVP では追加しない（spec 008 §Non-goals）

### ウィンドウ調整
5. **ウィンドウサイズ可変の方法**：`styleMask` に `.resizable` を追加するだけで NSWindow の標準ハンドラに任せる / カスタム resize handle を実装 → **標準ハンドラ推奨**
6. **透過率の段階値 vs 連続スライダー**：個人ツールなので **連続スライダー（0.5〜1.0）** 推奨
7. **設定パネルの形式**：別 NSWindow / SwiftUI Popover / メニューバー上のドロップダウン → **別 NSWindow（軽量、独立）** 推奨
8. **位置記憶の保存タイミング**：終了時のみ / ドラッグ終了時 / 定期 → **ドラッグ終了時の `NSWindow.didMoveNotification`** 推奨（終了時保存だと crash で消える）

### 共有 event
9. **判定ロジックの厳密度**：`visibility=private` のみ / summary も見る / 両方 → **両方判定** 推奨（精度向上）
10. **共有 event でも circle に表示するか**：表示する / フィルタリングする → **表示する**（時間帯は知りたい）、ただしクリック時は fallback

### Liquid Glass
11. **macOS 25 以下の fallback**：完全に Material に / opacity 調整 / バージョン分岐 → **`if #available(macOS 26, *)` で分岐**、25 以下は `.regularMaterial`
12. **`Info.plist` の `LSMinimumSystemVersion`**：14.0 のまま維持（fallback で 25 以下も動かす）。Liquid Glass は 26 のみ
13. **Liquid Glass の SwiftUI API**：実機検証必要。`.glassEffect()` / `glassBackgroundEffect()` の正確な使い方は Apple のサンプルを参照

## Out of scope / Phase 2 以降

参考：

- **spec 009 候補**：in-app event preview（popover / 詳細カード）、参加可否操作、Meet 起動、calendar.events scope への昇格、OAuth 再認可フロー
- **Phase 3**：複数日 navigation（マウスホイール / キーボード）、複数アカウント、対象カレンダー選択 UI、重なりイベントの 2 段リング、透明度の Option+scroll
- **将来検討**：os_log 共通化（spec 007 plan §12）、ISO8601Formatter キャッシュ、isAuthorized 名称分離（spec 007 review H-007-1）、webURL Domain テスト
