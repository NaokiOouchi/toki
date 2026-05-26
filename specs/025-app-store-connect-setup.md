# 025 — App Store Connect セットアップ手順

参照: `specs/ROADMAP.md` §2 Phase 4A
依存: spec 014 / 016 / 022 / 023 / 024 完了済み
ステータス: **手順書、未着手**（ユーザー Web 操作）

App Store Connect で Toki の App レコードを作成し、すべてのメタデータ /
価格 / Privacy 情報を入力する。本 spec は手順書として機能、ユーザーが Web UI で
順次操作する。

## 1. 目的

- App Store Connect に **Toki の App レコード** を作成
- spec 022 / 023 / 024 で起草した内容を Web UI に **入力**
- TestFlight / 審査提出（spec 027 / 028）の前提条件を満たす

## 2. 前提条件

- ✅ Apple Developer Program 有効（spec 014）
- ✅ Bundle ID `jp.co.noouchi.toki` を Apple Developer で登録済み
- ✅ OAuth Client（iOS type）作成済み（spec 016）
- ✅ Privacy Policy URL 公開済み（GitHub Pages、spec 023）
- ✅ Privacy Manifest 実装済み（spec 024）

## 3. 手順

### Step 1: App Store Connect にサインイン

https://appstoreconnect.apple.com にアクセス → Apple Developer アカウントでサインイン

### Step 2: App 新規作成

1. 上部メニュー **「マイ App」** をクリック
2. 左上の **「+」** ボタン → **「新規 App」**
3. ダイアログ入力：
   | 項目 | 値 |
   |---|---|
   | プラットフォーム | **macOS** |
   | 名前 | `Toki - 円形カレンダー時計`（30 文字以内）|
   | プライマリ言語 | **日本語** |
   | バンドル ID | `jp.co.noouchi.toki` をプルダウンから選択 |
   | SKU | `toki-mac-v1`（任意、内部識別子）|
   | ユーザーアクセス | **アクセスあり**（全員）|
4. **「作成」**

### Step 3: バージョン情報（v1.0）

左サイドバー **「macOS App」→「1.0 配信準備中」** を選択。

#### 3.1 プロモーション用テキスト（170 文字以内、いつでも変更可）

`specs/022-app-store-copy.md` §3.3 の文言を入力：

> 24 時間を 1 つの円で見渡せる、新しいカレンダー時計。Google Calendar と連携、常時前面表示で作業中も予定を見逃さない。ホバーで詳細、クリックで Meet / カレンダーへ。Mac 専用、無料。

#### 3.2 説明（4000 文字以内）

`specs/022-app-store-copy.md` §3.4 の Description 本文をコピペ。

#### 3.3 キーワード（100 文字以内、カンマ区切り、スペースなし）

```
Google,スケジュール,予定,常時前面,デスクトップ,Meet,時間管理,可視化,円,丸,フローティング,生産性
```

#### 3.4 サポート URL

GitHub Pages の Support トップ：
```
https://NaokiOouchi.github.io/toki/
```

#### 3.5 マーケティング URL（任意）

同上 or 空欄。

### Step 4: カテゴリ

- **プライマリ**: 仕事効率化（Productivity）
- **セカンダリ**: 任意（ユーティリティ Utilities 推奨）

### Step 5: 価格および配信状況

1. 左サイドバー **「価格および配信状況」**
2. **価格**: 「**無料**」を選択
3. **配信地域**: 全地域（worldwide）← デフォルト
4. **App Store 配信**: 利用可能

### Step 6: App プライバシー（重要）

1. 左サイドバー **「App プライバシー」**
2. **プライバシーポリシー URL** を入力：
   - 日本語版: `https://NaokiOouchi.github.io/toki/privacy/`
   - 英語版: `https://NaokiOouchi.github.io/toki/privacy-en/`
   - 主要 URL は **どちらか 1 つ**（日本ストアなら ja、worldwide なら en）
3. **データ収集** 質問：
   - 「データを収集していますか？」→ **はい**
   - 詳細は `specs/024-data-use-disclosure.md` §3.2 表を参照
   - Diagnostics（Crash Data + Performance Data）のみ「収集する」を選択
   - その他全カテゴリ：「収集しない」
   - Crash Data / Performance Data：
     - **ユーザーアカウントにリンク**: いいえ
     - **トラッキングに使用**: いいえ
     - **目的**: App の機能性、分析

### Step 7: 言語サポート

- **日本語** + **英語** を追加（spec 019 と整合）
- 各言語で：
  - 名前
  - サブタイトル
  - 説明
  - キーワード

英語版（spec 022 §4 参照）：
- Name: `Toki - Circle Calendar Clock`
- Subtitle: `Always-on-top Calendar Clock`
- Promotional Text: spec 022 §4.3 の英文
- Description: spec 022 §4.4 の英文
- Keywords: `google,schedule,planner,floating,desktop,meet,timer,productivity,visualization,minimal,widget`

### Step 8: スクリーンショット（spec 021 で別途）

スクリーンショットは spec 021 で撮影する。本 spec 着手時点では未配置でも OK
（v1.0 リリース提出時には必須）。

**macOS App Store のスクリーンショット要件**：
- サイズ：1280 x 800 / 1440 x 900 / 2560 x 1600 / 2880 x 1800 のいずれか
- 形式：PNG または JPG
- 最大 10 枚
- 各言語ごとに別途アップロード可

### Step 9: App アイコン

- Xcode build で `Toki.icns` が自動 bundle に含まれる（spec 020 完了済み）
- App Store Connect 側では別途 1024x1024 PNG が必要（マーケティング用 icon）
- これは Toki.icon の 1024x1024 view を export する必要

### Step 10: バージョンリリース

- **手動でリリース** or **自動でリリース**
- 推奨：**手動**（審査通過後、自分のタイミングで公開）

### Step 11: 年齢制限

- 4+ を選択
- 質問はすべて「該当なし / なし」で回答
  - 暴力、性的表現、不適切な言葉、ギャンブル、薬物、医療情報 等すべて

### Step 12: 著作権

- `© 2026 Naoki Oouchi`（または開発者名）

### Step 13: App レビュー連絡先情報

審査担当者から連絡が必要な場合の情報：
- 名前
- 電話番号
- メールアドレス（開発者メール）
- レビューメモ（任意）：
  ```
  Toki uses Google Calendar API (calendar.readonly scope) via OAuth 2.0 PKCE.
  Sign-in flow uses ASWebAuthenticationSession with a custom URL scheme
  (com.googleusercontent.apps.xxx) — no loopback / network.server entitlement.

  Demo account for review:
  - Email: <デモ用 Google アカウント>
  - Password: <デモ用パスワード>
  - 2FA: <該当なら手順>

  All event data is processed in-memory only; nothing is sent to our servers.
  ```

### Step 14: ビルドの紐付け

TestFlight / Archive upload 後、本ページから「+」で v1.0 のビルドを選択。
（spec 027 で実施）

## 4. 完了条件

- [ ] App レコード作成完了
- [ ] 日本語版 メタデータ全項目入力
- [ ] 英語版 メタデータ全項目入力
- [ ] 価格：無料、配信地域：全世界
- [ ] App プライバシー入力完了（spec 024 と整合）
- [ ] サポート URL 設定（GitHub Pages）
- [ ] App アイコン 1024x1024 PNG アップロード
- [ ] 年齢制限：4+
- [ ] レビュー連絡先 + デモアカウント情報入力

スクリーンショット（spec 021）+ ビルド紐付け（spec 027）は別 spec で。

## 5. リスク・注意事項

- **メタデータの揃え漏れ**：英語版を忘れがち、両言語必須
- **Privacy Disclosure の不整合**：spec 024 と異なる回答すると審査で指摘される
- **アイコン 1024x1024 PNG**：Xcode Icon Composer から export 必要、忘れがち
- **デモアカウント**：Google Workspace の test account 推奨、個人 Google アカウント貸出は避ける

## 6. 並行作業

- **spec 021 Screenshot**：本 spec 着手中に並行で撮影 OK
- **spec 027 TestFlight**：本 spec 完了後

## 7. 参照

- `ROADMAP.md` §2 Phase 4A
- `specs/022-app-store-copy.md` — メタデータ文言
- `specs/023-privacy-policy-support-site.md` — Privacy Policy URL
- `specs/024-data-use-disclosure.md` — App プライバシー回答
- [App Store Connect Help](https://developer.apple.com/help/app-store-connect/)
- [App Store Connect URL](https://appstoreconnect.apple.com)
