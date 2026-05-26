# 028 — App Review 提出 + リジェクト対応プロトコル

参照: `specs/ROADMAP.md` §2 Phase 5
依存: spec 014 / 015 / 016 / 017 / 019 / 020 / 021 / 022 / 023 / 024 / 025 / 027 完了済み
ステータス: **手順書、未着手**（ユーザー App Store Connect 操作 + 待機）

App Store Connect で v1.0 ビルドを Apple Review に提出 → 通過 → 公開。
リジェクト時の対応プロトコルも含む。

## 1. 目的

- v1.0 を Apple App Review に提出
- 通過後、App Store で **公開**（リリース）
- リジェクト時の迅速な対応

## 2. 前提条件（全部 ✅ 必須）

- ✅ spec 014: Apple Developer 登録
- ✅ spec 015 / 015a / 016: コア技術（Sandbox + OAuth + Xcode）
- ✅ spec 017: エラーハンドリング
- ✅ spec 019: ローカライズ（日英）
- ✅ spec 020: App Icon 反映済み
- ✅ spec 021: Screenshot アップロード済み
- ✅ spec 022: App メタデータ入力済み
- ✅ spec 023: Privacy Policy 公開済み（GitHub Pages）
- ✅ spec 024: Privacy Manifest + Disclosure 入力済み
- ✅ spec 025: App Store Connect レコード完成
- ✅ spec 027: TestFlight β テスト通過

## 3. 提出前 最終チェックリスト

App Store Connect の Toki > 1.0 配信準備中 ページで：

- [ ] **App プライバシー**：質問全部回答済み（緑チェック）
- [ ] **価格と配信状況**：無料 / worldwide
- [ ] **App 情報**：カテゴリ / コンテンツライセンス（None）/ プライバシーポリシー URL
- [ ] **macOS App スクリーンショット**：最低 1 枚アップロード（推奨 4-10 枚）
- [ ] **プロモーション用テキスト / 説明 / キーワード / サポート URL**：全項目入力
- [ ] **ビルド**：TestFlight で動作確認済みビルドを紐付け
- [ ] **App Review に関する情報**：
   - [ ] 連絡先情報（名前 / 電話 / メール）
   - [ ] **デモアカウント**（OAuth 必須なので必ず提供）
   - [ ] **レビューメモ**（OAuth フロー / network.server なし等の補足）
- [ ] **バージョンのリリース**：**手動でリリース** 推奨

## 4. デモアカウント + レビューメモ（重要）

OAuth サインインが必要なアプリは Apple Reviewer がアプリを操作するためにデモアカウントが必須。

### 4.1 デモアカウント準備

選択肢：
- **専用デモ Google アカウント** 作成（推奨）
  - `toki.demo+review@gmail.com` 等
  - ダミー予定を 5-10 件登録（OAuth + Calendar 取得が動くと確認できる）
  - 2FA を無効化（reviewer が困らないように）or 必須なら手順記載

### 4.2 レビューメモ テンプレ

```
Toki is a circle-shaped clock for macOS that visualizes your Google Calendar
events on a 24-hour clock face. It runs as a floating window above other apps.

== How to test ==

1. Click the menu bar 🕐 icon (right-click)
2. Select "Connect to Google Calendar"
3. An Apple-provided authentication window will appear (ASWebAuthenticationSession)
4. Sign in with the demo account below
5. Grant calendar.readonly permission
6. The window will auto-close; today's events will appear as arcs on the clock

== Demo account ==

Email: toki.demo+review@gmail.com
Password: <パスワード>
2FA: disabled for review (will be re-enabled post-review)

== Technical notes ==

- OAuth: Google OAuth 2.0 for iOS apps + PKCE (no client_secret embedded)
- Redirect URI: com.googleusercontent.apps.<id>:/oauthredirect (custom scheme)
- No client_secret is bundled. Authentication relies on PKCE only.
- All event data is processed in-memory only; nothing is sent to our servers.
- We use MetricKit for crash reporting (standard macOS framework).
- No third-party SDKs.

== Sandbox entitlements ==

- com.apple.security.app-sandbox (required for App Store)
- com.apple.security.network.client (Google Calendar API)
- No network.server entitlement (we use ASWebAuthenticationSession instead of loopback)

== Calendar scope justification ==

We request calendar.readonly only. We need read access to display today's
events on the circular clock face. We never modify, create, or delete events.

== Privacy policy ==

https://NaokiOouchi.github.io/toki/privacy-en/
```

## 5. 提出手順

### Step 1: 「審査に提出」

1. https://appstoreconnect.apple.com → マイ App > Toki
2. **「macOS App」→ 「1.0 配信準備中」**
3. 右上 **「審査に追加」** ボタン
4. ダイアログで第三者コンテンツ等の質問に回答
5. **「審査に提出」**

### Step 2: 待機

通常の審査期間：
- 初回 v1.0：**1-3 日**（混雑期は 5-7 日）
- 短時間（数時間）で結果が出ることも
- 連休前後は長引く

### Step 3: 結果通知

メールで届く：
- ✅ **「準備完了 (Ready for Sale)」** → 通過
- ❌ **「リジェクト (Rejected)」** → 対応必要

## 6. 通過時：公開（リリース）

### 6.1 手動リリース選択時

1. App Store Connect > Toki > **「準備完了」** ステータス
2. **「このバージョンをリリース」** ボタン
3. 数時間以内に App Store に反映（worldwide で配信開始）

### 6.2 直後の確認

- App Store macOS で `Toki` 検索 → ヒットする
- インストール → 動作確認
- 自分でレビュー（★5）を書く（OK）

## 7. リジェクト時：対応プロトコル

### 7.1 落ち着く

リジェクトは **普通** のこと。慌てて反論しない。

### 7.2 リジェクト理由を読む

App Store Connect > Resolution Center にメッセージ：
- ガイドライン違反の番号（例：Guideline 2.1 - Information Needed）
- 具体的な指摘内容
- スクリーンショット付きの場合あり

### 7.3 リジェクト理由別の対応

#### A. **Information Needed**（情報不足）

最も多いパターン：Reviewer がアプリを動かせなかった / 説明不足。

対応：
1. Resolution Center で **メッセージ返信**
2. デモアカウント情報 + 操作手順を再送
3. レビューメモを充実させて再送
4. 必要なら動画（Loom 等）を案内

→ 多くは追加情報で再審査通過。

#### B. **Sandbox / Entitlement 関連**

例：「Why does your app use network.server?」（実は spec 016 で削除済みなので発生しないはず）

対応：
- レビューメモで技術的理由を説明
- 該当 entitlement の use case を明示

#### C. **Privacy / Data 関連**

例：「Privacy Policy 不整合」「Data Collection 未申告」

対応：
- spec 023 と spec 024 を再確認、Privacy Policy と App Privacy 申告が一致するか
- 不整合あれば修正 → メタデータ更新 → 再提出

#### D. **Functionality / Bug**

例：「アプリがクラッシュする」「機能が動かない」

対応：
- バグ修正 → Xcode で build 番号 increment → Archive → Upload
- App Store Connect で **新ビルド紐付け** → 再提出

#### E. **Metadata Reject**

例：「説明文に「Beta」と書いてある」「スクリーンショットが実機と違う」

対応：
- メタデータ修正のみ（ビルド再 upload 不要）
- App Store Connect で 修正 → 再審査リクエスト

### 7.4 反論する場合

技術的に正しいのに Reviewer の誤解の場合：
- 丁寧に説明 → Resolution Center で技術詳細
- 必要なら **App Review Board に申し立て** (rare)
- 過去 commits / 公開ドキュメントへのリンクで補強

### 7.5 修正版 build upload + 再提出

1. Source 修正 → `CFBundleVersion` increment
2. Archive → Upload（spec 027 と同じ手順）
3. App Store Connect で新ビルド紐付け
4. **「審査に提出」** 再度

## 8. 公開後の運用

- App Store 上のレビュー / 評価を確認
- GitHub Issues / Discussion でユーザー報告対応
- バグ修正 → v1.0.1 → 同じ手順で再提出
- 機能追加 → v1.1 → spec 016b (ASWebAuth マイグレーション) 等で計画的に

## 9. 完了条件

- [ ] 提出前チェックリストすべて OK
- [ ] デモアカウント準備済み
- [ ] レビューメモ書き込み済み
- [ ] App Store Connect で「審査に追加」→ 「審査に提出」
- [ ] **「準備完了 (Ready for Sale)」** ステータス到達
- [ ] 「このバージョンをリリース」ボタンクリック
- [ ] App Store で `Toki` 検索ヒット
- [ ] インストール / 動作確認 ✅

🎉 **公開完了**

## 10. リスク・注意事項

- **OAuth がレビューで動かない**：デモアカウント不備が最頻リジェクト要因、念入りに準備
- **iOS app type OAuth Client 経由のため Reviewer 環境で動くか**：TestFlight で reviewer と同条件で確認しておく
- **Privacy Verification 未取得**：100 user 上限の警告画面が出る、ただし審査自体は通る（公開後ユーザーが増えたら別 spec で対応）
- **連休 / 年末年始**：審査が遅くなる、リリース希望日に余裕を持って提出

## 11. 参照

- `ROADMAP.md` §2 Phase 5
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [App Review - Apple](https://developer.apple.com/app-store/review/)
- [Resolution Center docs](https://help.apple.com/app-store-connect/#/dev0c2bff85a)
