# 002 — visual-polish: Tasks

参照: `specs/002-visual-polish.md` / `specs/002-visual-polish-plan.md`

合計: **4 tasks**（+ 例外的に 0〜1 個の `fix(composition)` が Task 2 内で発生する可能性あり）

実装順序：上から順に。各 task は fresh subagent に渡して 1 commit ずつ。

Phase 1.5 polish のため、Domain / Infrastructure / Composition / Window / App 層は無変更。UI 層 + SPEC.md のみ。

---

## Task 1: SPEC.md リング径の表記矛盾を訂正

**Commit**: `docs(spec): SPEC.md リング径の表記矛盾を訂正`

**目的**: SPEC.md §1「時計直径 約240px」と §2「内径 220px、外径 260px」の数値矛盾を解消し、本 polish で採択する実装値（内径 200 / 外径 240）と整合させる。

**コンテキスト**:
- 参照: plan §7「SPEC.md 訂正詳細」/ spec 002 §AC「SPEC 整合性」
- 前提: spec 002 §AC で「表記訂正は別 commit として実装変更とは分離」と明示。本 task は **ドキュメントのみ**で実装には触らない
- 直径換算：内径 200 = innerRadius 100、外径 240 = outerRadius 120、§1「直径 約240px」と一致

**実装内容**:
- ファイル: `SPEC.md`（編集のみ）
- 変更箇所 1: §2「時計」セクション
  - 変更前: `二重円のリング（内径 220px、外径 260px）が「時間トラック」`
  - 変更後: `二重円のリング（内径 200px、外径 240px）が「時間トラック」`
- 変更箇所 2: §7「実装メモ・落とし穴」内の「SwiftUI Canvas で annulus segment」コード例
  - 変更前: `let outerR: CGFloat = 130`
  - 変更後: `let outerR: CGFloat = 120`
  - 変更前: `let innerR: CGFloat = 110`
  - 変更後: `let innerR: CGFloat = 100`
- §1「ウィンドウ」セクションの `サイズ：280 × 320 px（時計直径 約240px + 上下余白）` は **無変更**（240px のまま）

**完了条件**:
- [ ] `grep -n "内径 220\|外径 260" SPEC.md` が **何もマッチしない**
- [ ] `grep -n "内径 200\|外径 240" SPEC.md` が **1 件マッチする**（§2 の該当行）
- [ ] `grep -nE "outerR: CGFloat = 1(30|10)" SPEC.md` が **何もマッチしない**
- [ ] `grep -nE "outerR: CGFloat = 120|innerR: CGFloat = 100" SPEC.md` が **2 件マッチする**（§7 コード例）
- [ ] `swift build` および `swift test` への影響なし（ドキュメント変更のため不要だが、念のため `swift test` で 36 ケース pass を確認）

**コミット**:
```bash
git add SPEC.md
git status   # SPEC.md の変更だけがステージされていること
git commit -m "docs(spec): SPEC.md リング径の表記矛盾を訂正"
```

**依存**: なし

---

## Task 2: ClockGeometry のリング径を 100/120 に変更

**Commit**: `style(ui): ClockGeometry のリング径を 100/120 に変更`

**目的**: 時計の内外径を `innerRadius: 110 → 100` / `outerRadius: 130 → 120` に縮小し、ウィンドウ内縁とイベント円弧最外端の余白 20pt を確保する。time track 幅 20pt は維持。

**コンテキスト**:
- 参照: plan §4「ClockGeometry 詳細」/ spec 002 §AC「時計の余白」
- 前提: `Sources/Toki/UI/ClockGeometry.swift` は spec 001 で作成済み。`ClockGeometry.standard(in:)` ファクトリが呼び出し側に対する単一の供給点
- API シグネチャ（`center`/`innerRadius`/`outerRadius` の存在と型）は不変、内部値のみ変更

**着手前の確認（必須）**:
本 polish の前提として「Composition 層は無変更」だが、`ClockViewModel.handleArcTap` のヒットテストロジックがハードコード値 110/130 を直接参照していると、`ClockGeometry` 変更で破綻する。**実装前に必ず以下を実行**：

```bash
grep -nE "innerRadius|outerRadius|110|130" Sources/Toki/Composition/ClockViewModel.swift
```

- ハードコード値 110/130 がなければ → そのまま Task 2 を進める（geometry 経由なので自動追随）
- ハードコード値 110/130 があれば → **例外的に別 commit `fix(composition): handleArcTap のハードコード半径を ClockGeometry 参照に変更` を Task 2 の前に追加**してから Task 2 を進める

実態は `ClockFaceCanvas` 内で `ClockGeometry.standard(in:)` から geometry を作って `onTap?(value.location, geometry)` で渡している想定なので、ClockViewModel 側がハードコード値を持つ可能性は低いはず。

**実装内容**:
- ファイル: `Sources/Toki/UI/ClockGeometry.swift`（編集のみ）
- 変更内容:
  ```swift
  static func standard(in size: CGSize) -> ClockGeometry {
      ClockGeometry(
          center: CGPoint(x: size.width / 2, y: size.height / 2),
          innerRadius: 100,  // 変更：110 → 100
          outerRadius: 120   // 変更：130 → 120
      )
  }
  ```
- コメントがあれば「内径 110 / 外径 130」を「内径 100 / 外径 120」に更新

**完了条件**:
- [ ] `swift build` が通る
- [ ] `swift test` で既存 Domain 36 ケース全 pass（無影響確認）
- [ ] `grep -nE "(innerRadius|outerRadius): (110|130)" Sources/Toki/UI/ClockGeometry.swift` が **何もマッチしない**
- [ ] `grep -nE "innerRadius: 100|outerRadius: 120" Sources/Toki/UI/ClockGeometry.swift` が **2 件マッチする**
- [ ] `./scripts/build-app.sh` が成功し `.build/Toki.app` 再生成

**コミット**:
```bash
git add Sources/Toki/UI/ClockGeometry.swift
git status
git commit -m "style(ui): ClockGeometry のリング径を 100/120 に変更"
```

**依存**: Task 1（SPEC と実装の整合性を保つため、ドキュメント訂正を先に commit）

---

## Task 3: ClockFaceCanvas の外側リング輪郭を削除、内側を強調

**Commit**: `style(ui): ClockFaceCanvas の外側リング輪郭を削除、内側を強調`

**目的**: モックアップに合わせて時間トラックの外側リング輪郭線を削除し、内側リング輪郭線を α 0.6 / lineWidth 0.75pt に強化してテーマ両対応の視認性を確保する。

**コンテキスト**:
- 参照: plan §5「ClockFaceCanvas 詳細」/ spec 002 §AC「リング輪郭」
- 前提: spec 001 Task 中の Phase 1.5 polish で `drawRingOutlines` は既に追加済み（外側 α 0.25 / 内側 α 0.4、両方 lineWidth 0.5）
- 確定値：α 0.6 / lineWidth 0.75pt で着手、Task 3 内で light/dark 両方確認後、薄ければ α のみ 1 行差分で 0.7 等に微調整（追加 commit なし）
- イベント円弧の current アウトラインも lineWidth 0.75pt なので統一感が出る
- `Color.secondary` は SwiftUI が light/dark で自動適応するため、濃度値 1 個で両対応

**実装内容**:
- ファイル: `Sources/Toki/UI/ClockFaceCanvas.swift`（編集のみ）
- 変更対象: `private func drawRingOutlines(...)` メソッド本体
- 変更内容:
  - 外側リング（`let outer = Path(ellipseIn:...)` から `ctx.stroke(outer, ...)` まで）の **6 行ブロックを削除**
  - 内側リング `ctx.stroke(inner, ...)` の パラメータを変更:
    - 変更前: `ctx.stroke(inner, with: .color(.secondary.opacity(0.4)), lineWidth: 0.5)`
    - 変更後: `ctx.stroke(inner, with: .color(.secondary.opacity(0.6)), lineWidth: 0.75)`
  - メソッドのドキュメントコメントを「二重リング輪郭」→「内側リング輪郭線。時間トラックの内縁を示す」に修正

期待される最終形：

```swift
/// 内側リング輪郭線。時間トラックの内縁を示す。
/// 外側はイベント円弧の外端で示唆されるため描画しない。
private func drawRingOutlines(in ctx: inout GraphicsContext, geometry: ClockGeometry) {
    let inner = Path(ellipseIn: CGRect(
        x: geometry.center.x - geometry.innerRadius,
        y: geometry.center.y - geometry.innerRadius,
        width: geometry.innerRadius * 2,
        height: geometry.innerRadius * 2
    ))
    ctx.stroke(inner, with: .color(.secondary.opacity(0.6)), lineWidth: 0.75)
}
```

他の関数（`drawHourMarks` / `drawEventArcs` / `drawHand` / `drawCenterDot`）は無変更。描画順も無変更。

**完了条件**:
- [ ] `swift build` が通る
- [ ] `swift test` で既存 36 ケース全 pass
- [ ] `grep -nE "let outer = Path|ctx.stroke\(outer" Sources/Toki/UI/ClockFaceCanvas.swift` が **何もマッチしない**
- [ ] `grep -nE "opacity\(0\.6\)|lineWidth: 0\.75" Sources/Toki/UI/ClockFaceCanvas.swift` が `drawRingOutlines` 内で **マッチする**
- [ ] `./scripts/build-app.sh` 成功で `.build/Toki.app` 再生成
- [ ] **実機目視確認**（必須）：`open .build/Toki.app` で起動し以下を確認
  - 外側リング輪郭線が描画されていないこと（イベント円弧の外端で時間トラック外縁が示される）
  - 内側リング輪郭線が視認可能であること（時計盤の中央寄りに細い円弧が見える）
  - System Settings の Appearance を light → dark で切り替え、両方で内側リング輪郭が見えること
  - 視認性が不足する場合は本 task 内で α を 0.7 に上げ、再度確認（追加 commit なし）

**コミット**:
```bash
git add Sources/Toki/UI/ClockFaceCanvas.swift
git status
git commit -m "style(ui): ClockFaceCanvas の外側リング輪郭を削除、内側を強調"
```

**依存**: Task 2

---

## Task 4: NextEventLine を 2 行 wrap 可に変更

**Commit**: `style(ui): NextEventLine を 2 行 wrap 可に変更`

**目的**: 長い次の予定タイトル（例：「16:00 ENEOS実装ミーティング第2回」）が末尾省略されず、2 行 wrap で全文表示されるようにする。3 行目以降は引き続き `.tail` で省略。

**コンテキスト**:
- 参照: plan §6「NextEventLine 詳細」/ spec 002 §AC「次の予定ライン」
- 前提: `Sources/Toki/UI/NextEventLine.swift` は spec 001 で作成済み。現状は `.lineLimit(1)` + `.truncationMode(.tail)` で 1 行表示・末尾省略
- ClockView 側の `.frame(height: 40)` は 11pt × 2 行 ≈ 26pt + padding ≈ 40pt で収まる見込み。不足時のみ 44pt に拡張（同 commit 内）
- HStack の alignment は初期は指定なし（`.center`）で着手、実機で「次」ラベルが右テキスト 1 行目と揃わず違和感あれば `HStack(alignment: .firstTextBaseline)` を 1 行追加

**実装内容**:

### 必須変更
- ファイル: `Sources/Toki/UI/NextEventLine.swift`（編集）
- 変更前:
  ```swift
  Text("\(s.timeHHMM) \(s.title)")
      .font(.system(size: 11))
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .truncationMode(.tail)
  ```
- 変更後:
  ```swift
  Text("\(s.timeHHMM) \(s.title)")
      .font(.system(size: 11))
      .foregroundStyle(.secondary)
      .lineLimit(2)
      .truncationMode(.tail)
  ```

### 条件付き追加変更（実機で必要が判明した場合のみ、同 commit 内で）
- **HStack 整列が崩れる場合**：`Sources/Toki/UI/NextEventLine.swift` 内の `HStack { ... }` を `HStack(alignment: .firstTextBaseline) { ... }` に変更
- **2 行目が見切れる場合**：`Sources/Toki/UI/ClockView.swift` 内の `NextEventLine(state: viewModel.nextLineState).frame(height: 40)` を `.frame(height: 44)` に拡張

**完了条件**:
- [ ] `swift build` が通る
- [ ] `swift test` で既存 36 ケース全 pass
- [ ] `grep -nE "\.lineLimit\(2\)" Sources/Toki/UI/NextEventLine.swift` が **1 件マッチする**
- [ ] `grep -nE "\.lineLimit\(1\)" Sources/Toki/UI/NextEventLine.swift` が **何もマッチしない**
- [ ] `./scripts/build-app.sh` 成功で `.build/Toki.app` 再生成
- [ ] **実機目視確認**（必須）：`open .build/Toki.app` で起動し以下を確認
  - 短い次の予定タイトル（例：「14:00 昼食」）が 1 行で表示される
  - 長いタイトル（実カレンダーに 30 字以上のタイトルを一時的に追加するか、既存の長い予定で確認）が 2 行 wrap して全文表示される
  - 「次」ラベルが左端に固定、wrap してもレイアウト破綻なし
  - 違和感があれば本 task 内で `.firstTextBaseline` 追加 or `.frame(height: 44)` に拡張、再確認（追加 commit なし）

**コミット**:
```bash
git add Sources/Toki/UI/NextEventLine.swift
# ClockView.swift を編集した場合は追加
git add Sources/Toki/UI/ClockView.swift 2>/dev/null || true
git status
git commit -m "style(ui): NextEventLine を 2 行 wrap 可に変更"
```

**依存**: なし（Task 2/3 と独立、コミット順序的に最後）

---

## 全 task 完了後

### 回帰確認
- [ ] `swift test`：Domain 36 ケース全 pass
- [ ] `./scripts/build-app.sh && open .build/Toki.app`：実機目視で spec 002 §Acceptance Criteria 13 項目を walkthrough：
  - ウィンドウ内縁とイベント円弧最外端の余白 ≥ 20pt
  - 内側リング輪郭線が light/dark 両テーマで視認可能
  - 外側リング輪郭線が非描画
  - 短い次の予定が 1 行、長い次の予定が 2 行 wrap、超長文は 2 行目末尾 `…`
  - 「次」ラベル左端固定
  - 時刻マーク（0/6/12/18）と中央テキストが重ならない
  - 針が中心から外径まで描画
  - イベント円弧クリック → 純正カレンダー.app 起動が引き続き動作
  - 中央テキスト 3 行レイアウト維持
  - 右クリック → 終了メニュー動作
  - メニューバーアイコンの表示/非表示トグル動作

### コードレビュー
- `code-reviewer` agent で全体レビューを実行
  - 特にチェック：依存方向（Domain / Infrastructure / Composition への変更ゼロ）、ファイル長 < 400 行、不要な抽象化なし
- レビュー結果をもとに修正があれば追加 task として積む

### マージ
- 修正完了後、main ブランチへマージ（既に main で作業している場合は何もしない）
