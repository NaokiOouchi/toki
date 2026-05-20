# CLAUDE.md — Toki

macOS 常時前面表示型の円形時計カレンダー。個人利用、Mac専用。
詳細仕様は @SPEC.md、機能ごとの仕様は @specs/ を参照。

## Commands

```bash
swift build              # ビルド
swift run                # 実行（開発時）
swift test               # ドメイン層テスト実行
swift build -c release   # リリースビルド
```

## Project Structure

```
Sources/Toki/
├── App/             # @main, AppDelegate, NSStatusBar
├── Window/          # NSWindow 設定（floating, borderless）
├── UI/              # SwiftUI Views, Canvas 描画
├── Domain/          # 純粋ロジック（TimeOfDay, Event, DayTimeline）
├── Infrastructure/  # EventKit ↔ Domain の変換
└── Composition/     # ViewModel, 依存組み立て
Tests/TokiTests/     # Domain 層のみ
```

## アーキテクチャ

依存方向は厳守：

```
App / Window → Composition → UI → Domain
                          ↘ Infrastructure → Domain
```

- **Domain** は Foundation のみに依存（純粋）
- **Infrastructure** は Domain に依存（逆はNG）
- **UI** は Domain の値型を受けて描画、Infrastructure 直接参照禁止
- **Composition** が ViewModel と依存組み立てを担う

IMPORTANT: `EKEvent` などの Infrastructure 型を Domain 層に漏らさない。必ず Domain の `Event` に変換する。

## 命名・スタイル

- ドメイン用語（`TimeOfDay`, `Event`, `DayTimeline`, `EventStatus`）は spec の表記から変えない
- **コミュニケーション・コードコメントは日本語**
- 1 タスク = 1 commit、Conventional Commits 形式
  - フォーマット：`<type>(<scope>): <summary>`
  - 例：`feat(domain): TimeOfDay の clockAngle 実装`
  - type: `feat / fix / refactor / docs / test / chore`
  - scope: `domain / infra / ui / app / window / composition`

## 禁止事項

IMPORTANT: 以下は明示的な相談なしに変えない。

- **過剰な抽象化**：protocol を「念のため」切らない、必要になってから
- **勝手な外部ライブラリ追加**：SwiftPM dependency 追加前に必ず相談
- **イベント編集機能の実装**：クリックは純正カレンダー.app に飛ばすのみ
- **Windows 対応のための技術選定**：いま考えない
- **Domain 以外のテスト**：UI / Infrastructure は手動確認、XCTest は Domain のみ
- **vibe coding**：spec / plan / tasks を飛ばして実装に行かない
- **設定UI**：MVP では作らない、Phase 3 で必要なら

## 開発フロー

1. `/specify <feature>` → `specs/<n>-<feature>.md`
2. `/plan <feature>` → 技術プラン
3. `/tasks <feature>` → atomic task 分解
4. 各タスク → fresh subagent で実装 → commit
5. `code-reviewer` agent でレビュー → main へ

IMPORTANT: 設計判断を勝手に下さない。困ったら止まって質問。
