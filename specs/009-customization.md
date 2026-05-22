# 009 — 設定 UI カスタマイズ拡張（後追い spec）

## Why

spec 008 完了後、ユーザーから「テーマカラー / 文字色 / 背景色 / 文字サイズ / 円の太さなどを自分で試して決めたい」というフィードバックを受け、`/specify` を経由せず実験的に 7 commits で 11 軸の設定項目を追加した：

```
b86d2c7 feat(ui): 円自体の色をカスタマイズ可能に
059d640 feat(ui): 円自体（リング輪郭線）の太さを設定可能に
cce2dea feat(ui): 文字サイズ / リングの太さ / 針の太さの設定軸を追加
5f7fbb1 feat(ui): 背景色 / 文字色カスタム + ColorPicker 即時反映 + 透過率 5% 下限
178cd60 feat(ui): カスタムカラーピッカー / 透過率 0% / 自動署名 ID 解決
a79341a feat(ui): 配色モード（自動 / ライト / ダーク）を設定 UI に追加
d07df60 feat(ui): テーマカラー / 背景マテリアル濃度を設定 UI で調整可能に
```

これは CLAUDE.md の以下 2 つの禁止事項に抵触している：
- **設定 UI**：MVP では作らない、Phase 3 で必要なら
- **vibe coding**：spec / plan / tasks を飛ばして実装に行かない

ただし、実装した設定 UI は実用上有用（特に「白背景での視認性」「個人の好み合わせ」）であり、削除するのは惜しい。本 spec で **後追い的にドキュメント化**し、構造的負債を整理する根拠を残す。

## Goal

Phase 2.5（本 iteration 完了時）に達成する状態：

1. **後追い spec 化**：実装済みの 11 軸の設定項目を Acceptance Criteria として明文化、Non-goals を整理
2. **C-1 対応**：`AppSettings.swift` を Infrastructure → Composition に移動し、依存方向違反を解消
3. **HIGH 修正の延期記録**：レビュー指摘 H-1〜H-8 を Out of scope として明示、Phase 3 で対応
4. **既存挙動の維持**：機能変更ゼロ、リファクタは別 iteration
5. **Domain テスト 36 ケース全 pass**

## Non-goals

本 iteration では明示的にやらない：

- **AppSettings の構造分割**：`Composition/SettingsStore.swift`（永続化）+ `UI/AppearanceTokens.swift`（enum 群）+ `Composition/AppearanceModel.swift`（`@MainActor ObservableObject`）への分割は Phase 3
- **ClockView の @State 集約**：13 個の `@State` → `@StateObject AppearanceModel` への移行は Phase 3
- **SettingsView のサブ View 分割**：11 セクション → 11 ファイルの分割は Phase 3
- **`tokiGlassBackground(material:)` 化**：EventTooltip / SettingsView に materialStrength 反映は Phase 3
- **UserDefaults キー rename**：`customColor.r` → `customThemeColor.r` 等の整理は Phase 3
- **ThemeColor.color の循環依存解消**：`.custom` ケースが `AppSettings.shared` を読み戻す構造は Phase 3
- **新規設定軸の追加**：12 軸目以降は本 iteration では追加しない
- **アクセシビリティ拡張**：Dynamic Type 連動 / VoiceOver 対応は Phase 3
- **i18n / 多言語化**：日本語固定
- **複数プロファイル**：設定セット切替は対象外
- **Phase 3 機能の前倒し**：複数アカウント / Outlook 等は無関係

## Acceptance Criteria

### 後追い 11 軸の明文化

実装済みの設定項目：

| # | 項目 | 型 | UserDefaults キー | 反映先 |
|---|---|---|---|---|
| 1 | 透過率 | Double (0.05〜1.0) | `toki.opacity` | ClockView 背景レイヤーの `.opacity()` |
| 2 | テーマカラー | enum + ColorPicker | `toki.themeColor`, `customColor.r/g/b` | 針 / 中心ドット / ボーダー |
| 3 | 配色モード | enum (auto/light/dark) | `toki.colorSchemeMode` | `.preferredColorScheme()` |
| 4 | 背景の濃さ | enum (5 段階) | `toki.materialStrength` | ClockView の `.fill(material)` |
| 5 | 背景色を上書き | Bool + ColorPicker | `useCustomBackground`, `customBackground.r/g/b` | ClockView 背景の solid color |
| 6 | 文字色を上書き | Bool + ColorPicker | `useCustomTextColor`, `customText.r/g/b` | ClockView ルートの `.foregroundStyle()` |
| 7 | 文字サイズ | enum (4 段階) | `toki.textScale` | 各 Text の font size factor |
| 8 | リングの太さ | enum (4 段階) | `toki.ringThickness` | ClockGeometry の `outerRadius - innerRadius` |
| 9 | 針の太さ | enum (4 段階) | `toki.handThickness` | drawHand の lineWidth |
| 10 | 円の太さ | enum (4 段階) | `toki.circleOutlineThickness` | drawRingOutlines の lineWidth |
| 11 | 円の色を上書き | Bool + ColorPicker | `useCustomCircleColor`, `customCircle.r/g/b` | drawRingOutlines の color |

- The 11 軸全て SettingsView から調整可能で、即時反映される（ColorPicker は @State Color で resolve）
- The 全設定は UserDefaults に永続化され、アプリ再起動後も維持される

### レイヤー違反の解消（C-1）

- The `AppSettings.swift` を `Sources/Toki/Infrastructure/` から `Sources/Toki/Composition/` に移動する
- The Infrastructure 配下に SwiftUI / AppKit を import するファイルがゼロになる
- The 既存挙動は無変更（同一 module 内なので参照は維持される）

### 既存挙動の維持

- The Domain テスト 36 ケースは無変更で全 pass
- The spec 003〜008 で達成した挙動（クリック→ブラウザ / ホバーツールチップ / ウィンドウリサイズ・位置記憶 / Liquid Glass / 5 分→2 分ポーリング / busy block fallback / 接続中スピナー / 最終更新表示）はすべて維持

### Phase 3 の refactor 候補ドキュメント化（Out of scope だが記録）

レビュー指摘 HIGH 8 件を Phase 3 候補として SPEC.md §6 に追記：

- H-1: AppSettings 439 行責務肥大 → 3 ファイル分割
- H-2: ClockView の `@State` 13 個 → `@StateObject AppearanceModel`
- H-3: SettingsView 11 セクション → サブ View 11 ファイル
- H-4: `ThemeColor.color` が `AppSettings.shared` を読む循環依存 → `resolvedColor(customFallback:)` 化
- H-5: UserDefaults キー命名揺れ（`customColor.r` のみ何の色か不明） → rename + マイグレーション
- H-6: `materialStrength` が EventTooltip / SettingsView に未反映 → `tokiGlassBackground(material:)` 化
- H-7: `AppSettings.shared` のスレッド安全性未保証 → `@MainActor` 付与
- H-8: 円の色既定値がリテラル分散 → AppSettings へ集約

## Open Questions

実装着手前に判断したい論点：

### レイヤー違反対応の範囲
1. **`AppSettings.swift` の移動先**：Composition / 新規 Configuration 層 / そのまま Infrastructure に留めて分割
   - **判断**：Composition に移動（最小変更、SwiftUI import が許される層）。Phase 3 で改めて分割を検討
2. **UI 層から `AppSettings.shared` を直接参照する構造**：本 spec で直すか Phase 3 か
   - **判断**：Phase 3。本 spec では位置移動のみ
3. **`ThemeColor` 等 UI 用 enum の置き場所**：UI に分離するか Composition に同居するか
   - **判断**：Phase 3 でまとめて整理（`UI/AppearanceTokens.swift` 新規）

### Phase 3 計画
4. **次の spec で AppearanceModel 化を主軸にするか**：別途切る、または既存 spec 内で対応
   - **判断**：Phase 3 で独立 spec として起こす（`010-appearance-model-refactor.md` 等）

[NEEDS INPUT] は最大 3 件以下に絞る → 0 件、すべて [CONFIDENT] で確定可能。

## Out of scope / Phase 3 以降

参考：

- **Phase 3**：
  - AppSettings の構造分割（H-1）
  - AppearanceModel への移行（H-2）
  - SettingsView の細分化（H-3）
  - ThemeColor 循環依存解消（H-4）
  - UserDefaults キー rename（H-5）
  - tokiGlassBackground material 受け取り（H-6）
  - `@MainActor` 付与（H-7）
  - 円の色既定値集約（H-8）
  - Dynamic Type 連動
  - VoiceOver 対応
  - i18n
  - 設定プロファイル切替
- **将来検討**：
  - 設定エクスポート / インポート機能
  - シーン別自動切替（時間帯 / アプリフォーカス先に応じて）
  - クラウド同期（iCloud Drive）
