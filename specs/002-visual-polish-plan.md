# 002 — モックアップ準拠の視覚調整 技術プラン

`specs/002-visual-polish.md` を技術プランに展開したもの。`/tasks` で atomic task に分解する元となる。

## 0. 確定済み設計判断（このプランで採用）

ユーザーとの合意事項：

1. **C プラン採択**：リング径を 120/100 に縮小、外側リング輪郭を削除、内側リング輪郭を濃く、次の予定ラインを 2 行 wrap 可に
2. **SPEC.md の typo 訂正**：§2「外径 260」→「外径 240」、`§7` コード例も同期。別 commit `docs(spec): ...` に分離
3. **Phase 1.5 として位置づけ**：MVP 完成後の polish iteration、Domain/Infrastructure/Composition は無変更
4. **次の予定ライン高さ**：`.frame(height: 40)` 据え置きで着手、実機で 2 行が見切れた場合のみ Task 4 内で 44pt に拡張
5. **Composition 修正**：Task 2 着手前に `ClockViewModel.handleArcTap` を Read して確認、ハードコード値があった場合は例外的に `fix(composition): ...` を別 commit として追加
6. **内側リング輪郭の初期値**：α 0.6 / lineWidth 0.75pt で着手、実機 light/dark 両方確認後に不足なら α のみ Task 3 内で微調整（追加 commit なし）

## 1. Requirements restatement

本 polish（Phase 1.5）は spec 001 完成後に判明したモックアップとの視覚的乖離を埋める UI 層のみの調整。

- 達成：(a) ウィンドウ内縁とイベント円弧最外端の余白 ≥ 20pt、(b) 内側リング輪郭線をテーマ両対応の濃度に強化、(c) 外側リング輪郭線を削除、(d)「次の予定」ラインを 2 行 wrap 可、(e) SPEC.md §1/§2 の数値矛盾を実装値と整合
- 達成しない：色 / フォント / 針スタイル / ウィンドウサイズ / 中央テキストレイアウト / 円弧の角丸化（spec 002 Non-goals）
- 制約：Domain / Infrastructure / Composition 無変更、既存 Domain テスト 36 ケースは無修正で全 pass

## 2. Open Questions — 解決済み

spec 002 の 5 件をすべて解決：

1. **OQ #1 内側リング輪郭の濃度** → α 0.6 / lineWidth 0.75pt で着手、Task 3 内で実機微調整
   - 根拠：α 0.4/0.5pt は薄すぎ、α 0.7 超は黒背景でハロー的に光る懸念。0.75pt はイベント円弧の current アウトラインと同じ太さで馴染む。`Color.secondary` が light/dark で自動適応
2. **OQ #2 時刻マーク位置** → `labelRadius = innerRadius - 12` 据え置き
   - 根拠：innerRadius が 110→100 に縮むと位置は 98pt→88pt と内側へ。中央テキスト（最外端 ~30pt）との距離は ~28pt 確保。式そのままで OK
3. **OQ #3 次の予定ライン高さ枠** → 40pt 据え置き、不足時のみ 44pt
   - 根拠：11pt × 2 行 ≈ 26pt なので 40pt あれば十分。実機で見切れたら Task 4 内で 1 行差分追加で 44pt に拡張
4. **OQ #4 時刻ラベル再評価** → 動かさない
   - 根拠：spec 001 で内側配置に修正済み。本 polish の主旨は「内縁余白」であり、ラベル位置の見直しは Out of scope
5. **OQ #5 「20pt 以上」のマージン値** → 100/120 で確定
   - 根拠：280pt canvas で `outerRadius = 120` なら端から 20pt 確保。これより小さくするとモックアップとの乖離が再発

## 3. ファイル別変更計画

| ファイル | 変更内容 | 差分行数概算 | 公開 API 影響 |
|---|---|---|---|
| `Sources/Toki/UI/ClockGeometry.swift` | `innerRadius: 110 → 100`、`outerRadius: 130 → 120`、コメント更新 | 3 行 | なし |
| `Sources/Toki/UI/ClockFaceCanvas.swift` | `drawRingOutlines` から外側 stroke 削除、内側を `α 0.6 / lineWidth 0.75pt` に強化 | 5 行削除 / 2 行修正 | なし |
| `Sources/Toki/UI/NextEventLine.swift` | `.lineLimit(1)` → `.lineLimit(2)` | 1 行 | なし |
| `SPEC.md` | §2 リング径表記訂正、§7 コード例同期 | 3 行 | なし（ドキュメント） |
| `Sources/Toki/Composition/ClockViewModel.swift` | 例外的：`handleArcTap` のヒットテストがハードコード値の場合のみ修正 | 0〜数行 | 条件付き |

**新規ファイル**：なし
**Domain / Infrastructure / Window / App**：触らない

## 4. ClockGeometry 詳細

| 項目 | 変更前 | 変更後 |
|---|---|---|
| `innerRadius` | 110 | 100 |
| `outerRadius` | 130 | 120 |
| 時間トラック幅 | 20pt | 20pt（維持） |
| canvas size | 280×280 | 280×280（維持） |
| ウィンドウ内縁 → outer 端 | 10pt | **20pt**（余白確保） |

API シグネチャ（`center`/`innerRadius`/`outerRadius`）は不変。呼び出し側は `ClockGeometry.standard(in: size)` 経由なので自動追随。

## 5. ClockFaceCanvas 詳細

### `drawRingOutlines` の改修

```swift
// 変更前
ctx.stroke(outer, with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)
ctx.stroke(inner, with: .color(.secondary.opacity(0.4)), lineWidth: 0.5)

// 変更後（内側のみ残す）
ctx.stroke(inner, with: .color(.secondary.opacity(0.6)), lineWidth: 0.75)
```

- 外側 `Path(ellipseIn:)` の構築ごと削除（6 行ブロック）
- コメントを「二重リング輪郭」→「内側リング輪郭線。時間トラックの内縁を示す」に修正

### 他要素（無変更）
- `drawHourMarks`：`labelRadius = innerRadius - 12` 維持
- `drawEventArcs` / `drawHand` / `drawCenterDot`：ロジック無変更
- 描画順：リング輪郭 → 時刻マーク → イベント円弧 → 針 → 中心ドット（既存維持）

### light/dark 両対応
`Color.secondary` がシステムテーマで適応的に切り替わるため、`.opacity(0.6)` をそのまま掛ければ両方で同程度の視認性が出る見込み。確証は実機目視。

## 6. NextEventLine 詳細

### 変更

```swift
// 変更前
.lineLimit(1)
.truncationMode(.tail)

// 変更後
.lineLimit(2)
.truncationMode(.tail)
```

`.truncationMode(.tail)` 維持により「2 行に収まる→全文表示」「2 行にも収まらない→2 行目末尾 `…`」。

### レイアウト検証
- HStack alignment：初期は指定なし（`.center`）で着手、実機で「次」ラベルが右テキスト 1 行目と揃わず違和感あれば `HStack(alignment: .firstTextBaseline)` を 1 行追加
- `.frame(height: 40)`：11pt × 2 行 ≈ 26pt なので 40pt あれば収まる見込み、不足時のみ ClockView 側で 44pt に拡張

## 7. SPEC.md 訂正詳細

| 箇所 | 現状 | 変更後 |
|---|---|---|
| §2「ウィンドウ」line 26 | `サイズ：280 × 320 px（時計直径 約240px + 上下余白）` | 無変更（240px のままで OK） |
| §2「時計」line 35 | `二重円のリング（内径 220px、外径 260px）が「時間トラック」` | `二重円のリング（内径 200px、外径 240px）が「時間トラック」` |
| §7 line 274 | `let outerR: CGFloat = 130` | `let outerR: CGFloat = 120` |
| §7 line 275 | `let innerR: CGFloat = 110` | `let innerR: CGFloat = 100` |

直径換算：`100*2=200` / `120*2=240`、§1「直径 約240px」と一致。

### 別 commit 分離
spec 002 §AC「SPEC 整合性」で「表記訂正は別 commit として実装変更と分離」と明示。`docs(spec): ...` を最初の commit として独立させる。

## 8. 実装フェーズ順序

1 タスク = 1 commit、Conventional Commits + scope。順序依存あり。

### Task 1: `docs(spec): SPEC.md リング径の表記矛盾を訂正`
- 対象：`SPEC.md` §2 line 35、§7 line 274-275
- 完了条件：内径 200 / 外径 240 / `innerR: 100` / `outerR: 120` で統一
- 依存：なし
- リスク：LOW（ドキュメントのみ）

### Task 2: `style(ui): ClockGeometry のリング径を 100/120 に変更`
- 対象：`Sources/Toki/UI/ClockGeometry.swift`
- **着手前チェック**：`Sources/Toki/Composition/ClockViewModel.swift` の `handleArcTap` を Read し、ハードコード値 110/130 が使われていないことを確認。使われていたら別 commit `fix(composition): ...` を追加
- 完了条件：`innerRadius: 100` / `outerRadius: 120`、`swift build` pass、`swift test` 36 ケース pass
- 依存：Task 1（SPEC と実装の整合性維持）
- リスク：LOW

### Task 3: `style(ui): ClockFaceCanvas の外側リング輪郭を削除、内側を強調`
- 対象：`Sources/Toki/UI/ClockFaceCanvas.swift` の `drawRingOutlines`
- 完了条件：外側 stroke 削除、内側 stroke を α 0.6 / lineWidth 0.75 に、`swift build` pass、`./scripts/build-app.sh && open .build/Toki.app` で実機目視確認（外側輪郭が見えない / 内側輪郭が見える）。**Task 3 内で light/dark 両方確認、α 不足なら 1 行差分で 0.7 等に微調整**
- 依存：Task 2
- リスク：MED（内側輪郭濃度の実機確認）

### Task 4: `style(ui): NextEventLine を 2 行 wrap 可に変更`
- 対象：`Sources/Toki/UI/NextEventLine.swift`
- 完了条件：`.lineLimit(2)`、`swift build` pass、実機で長文タイトルが 2 行 wrap、短文は 1 行のままレイアウト崩れなし
- **必要なら**：`ClockView.swift` の `.frame(height: 40)` を `44` に拡張（同 commit 内で）、または `HStack(alignment: .firstTextBaseline)` を追加
- 依存：なし（Task 2/3 と独立、コミット順序的に最後）
- リスク：LOW

### 全タスク完了後
- `swift test`：Domain 36 ケース全 pass
- `swift run` / `open .build/Toki.app`：spec 002 §Acceptance Criteria 13 項目を目視 walkthrough
- 必要なら `code-reviewer` agent 実行

## 9. リスク

| Risk | 重大度 | 緩和策 |
|---|---|---|
| 内側リング輪郭線の濃度が light/dark で両方視認できないかも | **MED** | Task 3 内で両テーマ目視、α を 0.5 ↔ 0.7 で 1 行調整 |
| 次の予定ライン 2 行 wrap で `.frame(height: 40)` が足りないかも | LOW | Task 4 で `ClockView` の高さを 44 に拡張（ウィンドウ 320pt 維持の範囲内） |
| 既存 Domain テストへの影響 | LOW | UI 層のみ、Domain 無変更。Task 2 完了時に `swift test` 必須 |
| リング径縮小でハンドが短く見える | LOW | 仕様変更の意図的副作用。違和感あれば後続 polish で針 lineWidth を 1.5→2.0 に上げる（本 polish スコープ外） |
| HStack alignment が 2 行 wrap で崩れる | LOW | Task 4 内で `.firstTextBaseline` を 1 行追加 |
| `ClockViewModel.handleArcTap` のヒットテストが新 geometry に追随しない | LOW | Task 2 着手前に Read で確認、ハードコードなら `fix(composition): ...` を別 commit で追加 |

## 10. テスト方針

### 自動テスト
- `swift test`：Domain 36 ケース、Task 2/3/4 完了後それぞれで実行

### 手動目視チェックリスト（全タスク完了時）
- [ ] ウィンドウ内縁とイベント円弧最外端の余白が ≥ 20pt
- [ ] 内側リング輪郭線が light テーマで視認可能
- [ ] 内側リング輪郭線が dark テーマで視認可能
- [ ] 外側リング輪郭線が描画されていない
- [ ] 短い次の予定タイトルが 1 行で表示
- [ ] 長い次の予定タイトルが 2 行 wrap して全文表示
- [ ] 超長文が 2 行目末尾 `…` で省略
- [ ] 「次」ラベルが左端固定、wrap 時もレイアウト破綻なし
- [ ] 時刻マーク（0/6/12/18）と中央テキストが重ならない
- [ ] 針が中心から外径まで描画
- [ ] イベント円弧クリック → 純正カレンダー.app 起動
- [ ] 中央テキストレイアウト維持
- [ ] 右クリック → 終了メニュー動作
- [ ] メニューバーアイコントグル動作

## 11. Out of scope 確認

spec 002 Non-goals 再掲（本 polish では touch しない）：

- 色相・フォントの変更
- 針のスタイル変更
- 中央テキストの再レイアウト
- イベント円弧の角丸化 / ピル状化
- ウィンドウサイズの変更（280×320 維持）
- メニューバーアイコンのデザイン変更
- 次の予定 3 行以上の折り返し（2 行を上限）
- ホバー時の中央表示切替（Phase 2 行き）

## 参考ファイル

- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/specs/002-visual-polish.md`
- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/SPEC.md`
- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/Sources/Toki/UI/ClockGeometry.swift`
- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/Sources/Toki/UI/ClockFaceCanvas.swift`
- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/Sources/Toki/UI/NextEventLine.swift`
- `/Users/oouchinaoki/Documents/Projects/Git/work-kojin/toki/Sources/Toki/UI/ClockView.swift`

次のステップ：`/tasks 002-visual-polish` で atomic task 分解 → `specs/002-visual-polish-tasks.md` を生成。
