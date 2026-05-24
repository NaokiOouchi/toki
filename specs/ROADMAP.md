# Toki — 公開ロードマップ

最終更新: 2026-05-24
ステータス: **Planning**（プロトタイプ完了、公開準備フェーズ着手前）

このドキュメントは Toki の Mac App Store 公開に向けた戦略決定と工程計画を保持する。
個別 spec（`specs/<NNN>-<feature>.md`）への落とし込み前のトップレベル planning 文書。

---

## 1. 公開戦略の決定事項

### 1.1 配布チャネル
- **Mac App Store** で配布
- 理由：不特定多数の Mac ユーザーへのリーチ、Apple の発見性、IAP インフラ

### 1.2 ターゲット
- Mac ユーザー全般（個人プロトタイプ → 不特定多数への転換）

### 1.3 課金モデル
- **完全無料 + Tip Jar（Pro 解放紐付け）**
- スタイル：Checker Plus for Google Calendar の Donation モデルを参考
- 「売りたいわけじゃない、お布施くらいのノリ」が根底
- Pro 機能を解放するために Tip するが、金額は複数 tier から選べる
- どの tier を買っても Pro 解放（最小額から OK）

### 1.4 価格レンジ
- **一回限り**: ¥250 / ¥600 / ¥1,500 / ¥3,000
- **月額**: ¥250
- **年額**: ¥1,800（年割引）
- StoreKit 2 の固定価格 tier として実装、Chrome 拡張のような完全自由額は不可

### 1.5 Pro 機能（候補、具体は後で確定）
既存機能の一部を Pro 昇格 OK。新規機能を Pro 専用に作る圧力はかけない。

候補：
- 複数 Google アカウント / 複数 Calendar 表示
- カラーピック / カスタムテーマ拡張
- LaunchAtLogin
- その他（Phase 6 で議論）

### 1.6 管理ツール
- `specs/` markdown ベースを維持
- GitHub Issues は Phase 4 直前（公開準備）で integration（bug 報告ルート、Issue Templates）
- GitHub Projects は当面導入しない（個人開発で overhead 過大）

---

## 2. 公開までの Phase 一覧

各サブカテゴリは独立した spec として落とし込む。spec 番号は予定（変動あり）。
**依存** 列で「並行で進められる作業」と「待ちが必要な作業」を判別する。
**難** 列：低 / 中 / 高（実装侵襲度 + 不確実性）。

| Phase | サブ | カテゴリ | 内容 | 依存 | Spec | 難 |
|:---:|:---:|---|---|---|:---:|:---:|
| 0 | – | 準備 | Apple Developer Program 登録（年 ¥14,800）/ Bundle ID 確定 / Privacy Policy 草案 | なし | spec 014 | 低 |
| 1 | A | 技術 | App Sandbox 対応（entitlements / keychain / network 検証）| Phase 0 | spec 015 | 中 |
| 1 | B | 技術 | **OAuth 公開対応**（client_secret 漏洩問題、PKCE / proxy 等）| Phase 0 | spec 016 | **高** |
| 1 | C | 技術 | エラーハンドリング強化（UI で見える形に）| Phase 1A | spec 017 | 低 |
| 1 | D | 技術 | アクセシビリティ最低限（VoiceOver / キーボード）| Phase 1A | spec 018 | 中 |
| 1 | E | 技術 | ローカライズ（日本語 + 英語？）| Phase 1A | spec 019 | 中 |
| 2 | A | ブランディング | App Icon（1024 までの複数サイズ）| なし（並行可）| spec 020 | 中 |
| 2 | B | ブランディング | スクリーンショット（macOS App Store 規定サイズ）| Phase 1A 完了後 | spec 021 | 低 |
| 2 | C | ブランディング | App 説明文 / キーワード / カテゴリ | なし | spec 022 | 低 |
| 3 | A | 法務 | Privacy Policy（ウェブ掲載必須）| Phase 0 | spec 023 | 低 |
| 3 | B | 法務 | Support サイト（最低限 GitHub Issues でも可）| なし | spec 023 | 低 |
| 3 | C | 法務 | Data Use Disclosure（App Store Connect 質問）| Phase 1 完了後 | spec 024 | 低 |
| 4 | A | ストア | App Store Connect レコード作成 / メタデータ入力 | Phase 0 | spec 025 | 低 |
| 4 | B | テスト | TestFlight 配布 / β ユーザーテスト | Phase 1 + 4A | spec 027 | 中 |
| 4 | C | インフラ | GitHub Issues / Templates 整備 | なし | spec 026 | 低 |
| 5 | – | リリース | 審査提出 → リジェクト対応 → 公開 | Phase 1–4 全部 | spec 028 | 高 |
| 6 | A | 後付け | StoreKit 2 統合 | 公開後 | spec 029 | 中 |
| 6 | B | 後付け | 機能フラグ機構（Pro / 無料の出し分け）| 公開後 | spec 030 | 中 |
| 6 | C | 後付け | Tip Jar UI | Phase 6A | spec 031 | 低 |
| 6 | D | 後付け | Pro 機能（複数アカウント / カラーピック等）| Phase 6B | spec 032 | 中 |

### 並行で進められる作業（依存「なし」のもの）

Phase 0 着手と同時にスタート可：
- **2A** App Icon（デザイン作業、コードに侵襲しない）
- **2C** App 説明文 / キーワード / カテゴリ（マーケコピー作成）
- **3B** Support サイト準備（GitHub repo 整備）
- **4C** GitHub Issues / Templates 整備

これらは Phase 1 の重い技術作業と完全に独立、隙間時間で進められる。

### 待ちが発生する依存チェーン

```
Phase 0
 ├─ 1A (Sandbox) ──┬─ 1C (エラー) ─┐
 │                 ├─ 1D (a11y)    │
 │                 └─ 1E (l10n)    ├─ 2B (Screenshot)
 ├─ 1B (OAuth)  ───────────────────┤
 ├─ 3A (Privacy Policy)            │
 └─ 4A (App Store Connect) ─┐      │
                            ├─ 4B (TestFlight) ─┐
                            │                   │
                            └─ 3C (Data Use) ───┴─ 5 (審査 → 公開) → Phase 6
```

---

## 3. クリティカルパス

```
Apple Developer 登録 → App Sandbox → OAuth 公開対応 → ストア素材 → 審査 → 公開
                                       ↑ 最難・最ブロッカー
```

### 3.1 OAuth 公開対応の論点

現状：`client_secret` がアプリにハードコード。
MAS で配布すると IPA 解凍されて secret 抜かれる → 悪用される → Google から OAuth client が banned される可能性。

対策候補：
- **(a) PKCE フロー**（client_secret 不要、Google サポート）— 第一候補
- **(b) OAuth proxy 自前構築**（Cloudflare Workers 等で secret を隠す）— インフラ運用必要
- **(c) ユーザーに client_id 入力させる**（power user 向け、UX 悪い）— 最終手段

spec 015 で技術選定する。

---

## 4. 未決定事項

| 項目 | 候補 | 決定時期 |
|---|---|---|
| **v1.0 スコープ** | (i) 完全無料のみ / (ii) Tip Jar まで / (iii) Pro 機能まで | spec 014 着手前 |
| **ローカライズ** | (i) 日本語のみ / (ii) 日本語+英語 / (iii) 英語のみ | Phase 1 着手前 |
| **Bundle ID** | `com.<author>.toki` 形式で確定 | Phase 0 |
| **App 表示名** | `Toki` でいくか別名か | Phase 2 |

---

## 5. リリース後の運用

- バグ報告：GitHub Issues
- アップデート計画：未定（feedback ベース）
- ユーザーフィードバック収集：Issues + App Store reviews
- マーケティング：個人 SNS + GitHub README（最小限）

---

## 参照

- `SPEC.md` — 機能仕様トップレベル
- `CLAUDE.md` — プロジェクト指示 / 禁止事項
- `specs/<NNN>-*.md` — 個別機能 spec
