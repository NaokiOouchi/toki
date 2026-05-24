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

各 Phase は順次 spec 化していく。spec 番号は予定（変動あり）。

### Phase 0: 準備
- Apple Developer Program 登録（年 ¥14,800）
- Bundle ID 確定 / App ID 作成
- 公開戦略の最終化（このドキュメント）

### Phase 1: 技術基盤
| Spec 候補 | 内容 | 難易度 |
|---|---|---|
| spec 014 | App Sandbox 対応（entitlements / keychain / network 検証）| 中 |
| spec 015 | **OAuth 公開対応**（client_secret 漏洩対策）| **高（最難）** |
| spec 016 | エラーハンドリング強化（UI で見える形に）| 低 |
| spec 017 | アクセシビリティ最低限（VoiceOver / キーボード）| 中 |
| spec 018 | ローカライズ（未決定）| 中 |

### Phase 2: ブランディング / ストア素材
| Spec 候補 | 内容 |
|---|---|
| spec 019 | App Icon（1024 までの複数サイズ）|
| spec 020 | スクリーンショット（App Store 規定サイズ）|
| spec 021 | App 説明文 / キーワード / カテゴリ |

### Phase 3: 法務 / コンプライアンス
| Spec 候補 | 内容 |
|---|---|
| spec 022 | Privacy Policy / Support サイト |
| spec 023 | Data Use Disclosure（App Store Connect 質問）|

### Phase 4: App Store Connect + テスト
| Spec 候補 | 内容 |
|---|---|
| spec 024 | App Store Connect レコード作成 / メタデータ入力 |
| spec 025 | GitHub Issues / Templates 整備 |
| spec 026 | TestFlight 配布 / β テスト |

### Phase 5: 審査 → 公開
| Spec 候補 | 内容 |
|---|---|
| spec 027 | 審査提出準備 / リジェクト対応プロトコル |

### Phase 6: 後付け（v1.1+、Tip Jar / Pro 機能解放）
| Spec 候補 | 内容 |
|---|---|
| spec 028 | StoreKit 2 統合 |
| spec 029 | 機能フラグ機構（Pro / 無料の出し分け）|
| spec 030 | Tip Jar UI |
| spec 031 | Pro 機能（複数アカウント / カラーピック等）|

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
