# 023 — Privacy Policy / Support サイト（GitHub Pages）

参照: `specs/ROADMAP.md` §2 Phase 3A, 3B
ステータス: **初稿実装中**

Apple App Store 必須の Privacy Policy をウェブ公開し、同時に最小限の Support
サイト（FAQ / リンク / 連絡先）も整備する。Phase 3A と 3B を 1 spec に統合
（同じ GitHub Pages サイトに同居させるため）。

## 1. 目的

- App Store 審査必須の Privacy Policy をウェブ公開（URL を App Store Connect に登録）
- ユーザーが「Toki ってどんなアプリ？」「どこで質問する？」と検索した時の情報源
- Apple Privacy Manifest（後の Phase で必要）と整合したデータ宣言を持つ

## 2. スコープ

### 2.1 やること
- `docs/` ディレクトリに Jekyll ベースの静的サイト構築
- Privacy Policy（日本語 / 英語）
- Support トップページ（FAQ / リンク / 連絡先）
- GitHub Pages 有効化手順を spec に明記（ユーザー作業）

### 2.2 やらないこと
- 独自ドメイン取得（GitHub の `<user>.github.io/toki` URL でスタート）
- 多言語追加（日英のみ、ROADMAP §4.1 と整合）
- 詳細マニュアル / ブログ（必要に応じて後追加）
- 法的厳密チェック（**ユーザーが必要に応じて弁護士確認推奨**）

## 3. 重要：Toki が扱うデータの整理

Privacy Policy / Privacy Manifest 両方の基礎データ。

| データ | 取得元 | 保存先 | 第三者送信 |
|---|---|---|---|
| Google Calendar イベント情報（タイトル/時刻/場所/参加者/説明）| Google Calendar API | メモリのみ | なし |
| OAuth access / refresh token | Google OAuth | macOS Keychain | なし |
| アプリ設定（テーマ色 / フォント等）| ユーザー操作 | UserDefaults | なし |
| クラッシュレポート / 診断情報 | MetricKit（OS） | Apple サーバー | **Apple 経由のみ**（ユーザーが Share App Analytics OFF なら送信されない）|

## 4. クラッシュレポート / 分析の方針

- **MetricKit を使用**（Apple 純正フレームワーク）
- 追加 SDK 不要、第三者サービス（Sentry / TelemetryDeck 等）は使わない
- ユーザー識別情報は含まない（Apple が匿名化）
- ユーザーは macOS 設定 > Privacy & Security > Analytics & Improvements > Share Mac Analytics で OFF 可能
- 実装は別 spec（spec 015 App Sandbox or 別途）で技術詳細

## 5. ファイル設計

```
docs/
├── _config.yml          # Jekyll 設定（テーマ / サイト情報）
├── index.md             # Support トップ（FAQ / リンク）
├── privacy.md           # Privacy Policy 日本語
├── privacy-en.md        # Privacy Policy 英語
└── assets/
    └── style.css        # 最小限のスタイル（任意）
```

GitHub Pages は `docs/` ディレクトリを source として配信する設定にする。
Jekyll が `.md` を自動で HTML 変換するため、HTML 直接編集は不要。

## 6. ホスティング URL

GitHub Pages のデフォルト URL：

- Support トップ: `https://<github-username>.github.io/toki/`
- Privacy (JP): `https://<github-username>.github.io/toki/privacy/`
- Privacy (EN): `https://<github-username>.github.io/toki/privacy-en/`

App Store Connect には Privacy Policy URL として **言語に応じた URL** を登録（日本ストア = JP、その他 = EN）。

## 7. GitHub Pages 有効化手順（ユーザー作業）

実装完了後、以下を実施：

1. GitHub リポジトリの Settings → Pages
2. **Source**: Deploy from a branch
3. **Branch**: `main` / `/docs` フォルダ
4. Save
5. 数分待つと `https://<username>.github.io/toki/` でアクセス可能になる
6. アクセス確認 → URL を App Store Connect に登録（Phase 4A）

## 8. Privacy Policy 本文（日本語、初稿）

`docs/privacy.md` 配下に配置するため、別ファイルで起草（このセクションで概要のみ）。

含めるセクション：
1. はじめに（このアプリは何か）
2. 取得するデータの種類
3. データの利用目的
4. データの保存場所
5. データの第三者提供（しないことを明記）
6. クラッシュレポート / 診断情報（MetricKit）
7. データの削除方法（アプリ削除 + Google 側で OAuth 連携解除）
8. お問い合わせ
9. 改訂履歴 / 適用日

## 9. Privacy Policy 本文（英語、初稿）

同上、`docs/privacy-en.md` に配置。

## 10. Support サイト本文（`docs/index.md`）

含めるセクション：
1. Toki とは（1〜2 段落の説明）
2. 必要システム要件
3. クイックスタート（Google サインイン → 完了）
4. よくある質問（FAQ、3〜5 項目）
5. バグ報告 / 機能要望（GitHub Issues へのリンク）
6. Privacy Policy へのリンク（日英）
7. 開発者連絡先

## 11. 完了条件

- [ ] `docs/_config.yml` 作成
- [ ] `docs/index.md` 作成（Support トップ、日英併記 or 分離）
- [ ] `docs/privacy.md` 作成（日本語 Privacy Policy）
- [ ] `docs/privacy-en.md` 作成（英語 Privacy Policy）
- [ ] GitHub Pages を `docs/` から配信する設定（**ユーザー作業**）
- [ ] 公開 URL でアクセス確認（**ユーザー作業**）
- [ ] App Store Connect に Privacy Policy URL 登録（Phase 4A）

## 12. 注意事項

- **本 spec の Privacy Policy 草案は法的厳密保証なし**：弁護士確認が理想
- データ取扱を変更した場合（Pro 機能で新しい API 使う等）、Privacy Policy 更新必須
- App Store Connect の **App Privacy Disclosure**（質問形式）にも整合した回答が必要（Phase 4A の spec 024 で詳述）

## 13. 参照

- `ROADMAP.md` §2 Phase 3A, 3B
- [Apple Privacy Manifest documentation](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files)
- [GitHub Pages docs](https://docs.github.com/en/pages)
- [MetricKit](https://developer.apple.com/documentation/metrickit)
