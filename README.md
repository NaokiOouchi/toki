# Toki

macOS 常時前面表示型の円形時計カレンダー。
24 時間アナログ時計の外周に今日の予定を色付き円弧で表示する、邪魔にならないフローティングアプリ。

個人利用、Mac専用。

## Status

WIP — Phase 1 (MVP) 開発中

## 要件

- macOS 14+ (Sonoma)
- Swift 5.9+
- Xcode CLI tools

## Setup

```bash
git clone <repo>
cd Toki
swift build
swift run
```

初回起動時に EventKit の権限要求が出るので許可する。

## 開発ワークフロー (Spec-Driven Development)

このプロジェクトは Claude Code + SDD で開発する。`vibe coding` 禁止。

### 流れ

1. **Brainstorm**: 機能アイデアを対話で深掘り（コードは書かない）
2. **Specify**: `/specify <feature>` で spec を起こす
3. **Spec Review**: `spec-reviewer` agent で 5 視点レビュー、Open Questions を埋める
4. **Plan**: `/plan <feature>` で技術プランに展開
5. **Tasks**: `/tasks <feature>` で atomic task に分解
6. **Implement**: 各 task を fresh subagent で 1 commit ずつ
7. **Code Review**: `code-reviewer` agent で spec 準拠 + 品質チェック
8. **Merge**: main へ

### ディレクトリ構造

```
Toki/
├── CLAUDE.md                  # プロジェクト憲法（Claude Code が常に読む）
├── README.md                  # この file
├── SPEC.md                    # MVP 全体仕様（手書き、初期参照用）
├── Package.swift              # SwiftPM
├── specs/                     # feature 単位の spec / plan / tasks
│   ├── 001-clock-mvp.md
│   ├── 001-clock-mvp-plan.md  (要 /plan 実行)
│   └── 001-clock-mvp-tasks.md (要 /tasks 実行)
├── .claude/
│   ├── agents/                # サブエージェント定義
│   │   ├── spec-reviewer.md   # spec を 5 視点でレビュー (opus)
│   │   ├── code-reviewer.md   # 実装後の spec 準拠 + 品質チェック (opus)
│   │   └── researcher.md      # コードベース・API 調査 (sonnet)
│   └── commands/              # スラッシュコマンド定義
│       ├── specify.md
│       ├── plan.md
│       └── tasks.md
├── Sources/Toki/              # 実装（DDD レイヤ）
│   ├── App/                   # @main, AppDelegate, NSStatusBar
│   ├── Window/                # NSWindow 設定
│   ├── UI/                    # SwiftUI Views, Canvas 描画
│   ├── Domain/                # 純粋ロジック
│   ├── Infrastructure/        # EventKit ↔ Domain 変換
│   └── Composition/           # ViewModel, 依存組み立て
└── Tests/TokiTests/           # Domain 層のテスト
```

### コマンドリファレンス

| コマンド | 役割 |
|---|---|
| `/specify <feature>` | 新規 spec を作成 |
| `/plan <feature>` | spec を技術プランに展開 |
| `/tasks <feature>` | plan を atomic task に分解 |

### エージェントリファレンス

| エージェント | 役割 | model |
|---|---|---|
| spec-reviewer | spec を 5 視点（dev/QA/product/UX/domain-architect）でレビュー | opus |
| code-reviewer | コードを spec 準拠 + 品質の 2 段階でレビュー | opus |
| researcher | コードベース・Apple API 等を並列調査 | sonnet |

## 実装フェーズ

- **Phase 1 (MVP)**: 円形時計、イベント円弧描画、針、中央テキスト、メニューバー常駐
- **Phase 2**: マウスホバー切替、ウィンドウ位置記憶、右クリックメニュー
- **Phase 3**: 重なりイベントの 2 段リング、透明度調整、対象カレンダー選択、LaunchAtLogin

詳細は `SPEC.md` および `specs/` 配下を参照。

## ライセンス

非公開（個人利用）
