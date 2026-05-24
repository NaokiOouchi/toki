# 026 — GitHub Issues / Templates 整備

参照: `specs/ROADMAP.md` §2 Phase 4C
ステータス: **実装中**

Toki の v1.0 公開後、ユーザーからのフィードバック（バグ報告 / 機能要望 / 質問）を
構造化された形で受け取れるよう、GitHub Issue Templates を整備する。
公開前の今のうちに整備しておけば、リリース直後の混乱を避けられる。

## 1. 目的

- ユーザーが Issue を作るときの **報告品質** を上げる（環境情報 / 再現手順 / 期待動作）
- バグ / 機能要望 / 質問 を **分類** して優先度判断を容易に
- 想定外用途の Issue（マーケ営業 / 雑談）を抑制（blank issue 無効化）

## 2. スコープ

### 2.1 やること
- `.github/ISSUE_TEMPLATE/` ディレクトリ作成
- 3 つのテンプレ作成：
  - `bug_report.md`（バグ報告）
  - `feature_request.md`（機能要望）
  - `question.md`（使い方質問）
- `.github/ISSUE_TEMPLATE/config.yml`：blank issue 無効化 + 外部リンク
- Labels 定義（GitHub Web UI で手動設定する内容を spec で定義）

### 2.2 やらないこと
- **Pull Request Template**：Toki は個人開発なので不要
- **GitHub Discussions セットアップ**：Phase 6 以降で検討（ユーザー数に応じて）
- **Code of Conduct**：小規模個人プロジェクトには過剰
- **Issue 自動振り分けワークフロー**：Issue 数が増えてから検討

## 3. ファイル設計

各テンプレートは **日本語 + 英語併記**（ローカライズ方針 §1.5 と整合）。

### 3.1 bug_report.md
バグ報告用。環境情報 / 再現手順を必須化。

### 3.2 feature_request.md
機能要望用。「問題」を先に書かせて「解決方法」へ。

### 3.3 question.md
質問用。試したことを書かせて重複質問を減らす。

### 3.4 config.yml
blank issue を無効化（必ずテンプレ経由）。App Store レビューへ誘導するリンクも配置。

## 4. Labels（GitHub Web UI で手動設定）

| Label | 色 | 用途 |
|---|---|---|
| `bug` | `#d73a4a` (red) | バグ報告 |
| `enhancement` | `#a2eeef` (blue) | 機能要望 |
| `question` | `#d876e3` (purple) | 質問 |
| `wontfix` | `#ffffff` (white) | 対応しない |
| `duplicate` | `#cfd3d7` (gray) | 重複 |
| `invalid` | `#e4e669` (yellow) | 不正 |
| `documentation` | `#0075ca` (blue) | ドキュメント |
| `pro-candidate` | `#fbca04` (yellow) | Pro 機能候補（v1.1+ で検討）|

`pro-candidate` は Toki 独自：feature_request の中から「Pro 化候補」を後で識別するため。

## 5. 完了条件

- [x] `.github/ISSUE_TEMPLATE/bug_report.md` 作成
- [x] `.github/ISSUE_TEMPLATE/feature_request.md` 作成
- [x] `.github/ISSUE_TEMPLATE/question.md` 作成
- [x] `.github/ISSUE_TEMPLATE/config.yml` 作成（blank issue 無効化）
- [ ] GitHub Web UI で labels 設定（**手動、別途**）
- [ ] 新規 Issue 画面で 3 つのテンプレが選択可能（**push 後に確認**）

## 6. 並行作業との関連

このタスク完了後、Apple Developer 登録待ちの間に進める残りの並行作業：
- spec 022（App 説明文 / キーワード 起草）
- spec 023（Privacy Policy 草案）
- spec 020（App Icon 要件 spec）

## 7. 参照

- `ROADMAP.md` §2 Phase 4C
- [GitHub Issue Templates docs](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests)
