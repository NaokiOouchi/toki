# 022 — App Store 掲載文 / キーワード 起草

参照: `specs/ROADMAP.md` §2 Phase 2C
ステータス: **初稿**（Phase 4A で App Store Connect 入力時に最終調整）

App Store Connect で入力する全コピー（App Name / Subtitle / Description /
Promotional Text / Keywords / Category / 年齢制限）を日英で起草する。
ローカライズ方針に従い、日本語版と英語版を併記する。

## 1. 目的

- App Store SEO の土台を整える
- リリース直前に焦らないよう、文言を先に推敲しておく
- App Icon / Privacy Policy / Support サイト等、後続作業のメッセージ整合性の基準にする

## 2. App Store Connect 入力項目と制限

| 項目 | 文字数制限 | SEO 重要度 | 変更可能性 |
|---|---|---|---|
| App Name | 30 | ★★★ | 各バージョンで変更可 |
| Subtitle | 30 | ★★★ | 各バージョンで変更可 |
| Promotional Text | 170 | ☆ | **いつでも変更可**（強調用）|
| Description | 4000 | ★ | 各バージョンで変更可 |
| Keywords | 100 | ★★★ | 各バージョンで変更可 |
| Category (Primary / Secondary) | – | ★★ | 変更可 |
| Age Rating | – | – | 変更可 |

## 3. 日本語版

### 3.1 App Name
**`Toki - 円形カレンダー時計`**（17 文字）

### 3.2 Subtitle（30 文字以内）
**候補：**
- `常時前面の Google Calendar 時計`（24 文字）★ 推奨
- `デスクトップに浮かぶ円形カレンダー`（17 文字）
- `Google カレンダーを 24h 円形表示`（22 文字）

### 3.3 Promotional Text（170 文字以内）
```
24 時間を 1 つの円で見渡せる、新しいカレンダー時計。
Google Calendar と連携、常時前面表示で作業中も予定を見逃さない。
ホバーで詳細、クリックで Meet / カレンダーへ。Mac 専用、無料。
```
（約 130 文字）

### 3.4 Description（4000 文字以内）

```
Toki は、あなたの 24 時間を 1 つの円で見渡せる、Mac 専用のカレンダー時計です。

■ 特徴

・常時前面表示
他のアプリの上に浮かぶ円形ウィンドウ。作業中もスケジュールが視界に入り続けます。

・Google Calendar と直接連携
複雑な設定は不要。Google アカウントでサインインするだけで、今日の予定が円弧として時計に描かれます。

・24 時間を 1 つの円に
12 時間制ではなく 24 時間制。朝から夜までを 1 周で見渡せるので、1 日のスケジュール感が直感的に分かります。

・重なる予定にも対応
同時刻に複数の予定があっても、スクロールで切り替え可能。円弧の外側に「2/3」のような表示で全件を把握できます。

・終日予定の背景表示
終日の予定（出張・休暇など）は時計全体の背景として表示。一目で「今日は特別な日」と分かります。

・ホバーで詳細、クリックで開く
予定の円弧にカーソルを乗せると詳細表示。クリックで Google Meet や Google Calendar をブラウザで直接開けます。

・豊富なカスタマイズ
テーマカラー、リング太さ、針の太さ、文字サイズ、透過率、Liquid Glass（macOS 26+）など、見た目を細かく調整可能。

■ こんな方におすすめ

・Google Calendar をメインで使っている Mac ユーザー
・スケジュール管理を視覚的に行いたい方
・作業に集中しつつ、次の予定を見落としたくない方
・常駐型のシンプルなツールが好きな方

■ プライバシー

Toki はあなたの予定データを Google Calendar から直接取得し、ローカルでのみ処理します。第三者サーバーへの送信は一切ありません。詳細はプライバシーポリシーをご確認ください。

■ 動作環境

・macOS 14 以降
・macOS 26 以降で Liquid Glass の最高表現

■ ライセンス

完全無料。広告も課金もありません。
（将来のアップデートで、応援したい方向けの Tip / Pro 機能を予定しています。）
```

### 3.5 Keywords（100 文字以内、カンマ区切り、スペースなし）

App Name に含まれる「Toki」「カレンダー」「時計」「円形」は自動 index されるので除外。

**候補：**
```
Google,スケジュール,予定,常時前面,デスクトップ,Meet,時間管理,可視化,円,丸,フローティング,生産性
```
（約 65 文字）

### 3.6 Category
- **Primary**: Productivity（仕事効率化）
- **Secondary**: なし or Utilities（ユーティリティ）

### 3.7 Age Rating
**4+**（成人向けコンテンツなし）

## 4. 英語版

### 4.1 App Name
**`Toki - Circle Calendar Clock`**（28 文字）

### 4.2 Subtitle（30 文字以内）
**候補：**
- `Floating Calendar Clock` (23) + 余白
- `Always-on-top Calendar Clock` (28) ★ 推奨
- `Circle Clock for Google Calendar` (32) — オーバー
- `Floating Circle Calendar Clock` (30) — ぴったり

### 4.3 Promotional Text（170 文字以内）
```
See your full day at a glance with a circle clock that floats above your work.
Connects to Google Calendar. Hover for details, click to open Meet. Free for Mac.
```
（約 165 文字）

### 4.4 Description（4000 文字以内）

```
Toki is a floating circle clock for Mac that puts your full 24-hour day in a single glance.

■ Features

· Always-on-top floating window
A small circle window stays above your other apps so your schedule is always visible while you work.

· Direct Google Calendar integration
Just sign in with Google. Today's events are drawn as arcs on the clock face — no complex setup.

· 24-hour at a glance
A full day in one circle (not 12-hour). Morning to night is one rotation, giving you an intuitive sense of your daily flow.

· Overlapping events supported
Multiple events at the same time? Scroll to cycle through them. An indicator like "2/3" shows how many events overlap.

· All-day events as background
All-day events (trips, holidays) appear as the clock's background — instantly telling you "today is different."

· Hover for details, click to open
Hover any arc to see the event's details. Click to open it in Google Meet or Google Calendar.

· Rich customization
Theme color, ring thickness, hand thickness, text scale, opacity, and Liquid Glass on macOS 26+ — all adjustable.

■ Who it's for

· Mac users who live in Google Calendar
· Anyone who wants visual schedule awareness while focusing on other work
· Lovers of minimal always-available tools

■ Privacy

Toki fetches your events directly from Google Calendar and processes them locally only. No third-party servers, ever. See our privacy policy for details.

■ Requirements

· macOS 14 or later
· macOS 26 or later for the full Liquid Glass experience

■ License

Free, with no ads, no in-app purchases.
(Future updates may include optional Tip / Pro features for those who want to support development.)
```

### 4.5 Keywords（100 文字以内）

App Name の語（toki, circle, calendar, clock）は除外。

**候補：**
```
google,schedule,planner,floating,desktop,meet,timer,productivity,visualization,minimal,widget
```
（約 90 文字）

### 4.6 Category
- **Primary**: Productivity
- **Secondary**: なし or Utilities

### 4.7 Age Rating
**4+**

## 5. 注意事項

- **競合アプリ名は Keywords に入れない**（Apple 規約違反、リジェクトリスク）
- **「ベスト」「No.1」等の最上級表現は控える**（裏付け要求される）
- **絵文字は Description で慎重に**（一部は審査落ち事例あり）
- **「Beta」「Test」等の文言は不可**（公式 release では）
- **広告 / 課金がある場合は明記必須**（v1.0 は両方なし）

## 6. 完了条件（spec として）

- [x] 日本語版 7 項目すべて起草
- [x] 英語版 7 項目すべて起草
- [ ] Phase 4A で App Store Connect に入力 → 微調整
- [ ] スクリーンショット完成後に Description との整合性確認（Phase 2B）

## 7. 次の Phase 4A での作業

- App Store Connect で本 spec の文言を入力
- 文字数オーバーがないか実機確認
- 翻訳の自然さ最終チェック（ネイティブレビュー推奨）
- Promotional Text は **公開後でも変更可能** なので、初版は控えめに

## 8. 参照

- `ROADMAP.md` §2 Phase 2C
- [App Store Product Page - Apple Developer](https://developer.apple.com/app-store/product-page/)
- [Search Optimization (ASO) - Apple Developer](https://developer.apple.com/app-store/search/)
