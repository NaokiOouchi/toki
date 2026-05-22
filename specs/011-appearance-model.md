# 011 — AppearanceModel リファクタ（Phase 3 構造改善）

## Why

spec 009 / spec 010 のレビューで蓄積された構造的負債 4 件を一括解消する Phase 3 リファクタ。機能変更ゼロ、ユーザー体験は完全に維持しつつ、内部構造を SwiftUI 標準パターンに整える。

### 解決する問題（spec 009 + spec 010 review 由来）

#### H-1：AppSettings 439 行 / 責務肥大
`Composition/AppSettings.swift` が：
- UserDefaults wrapper（永続化）
- 7 個の表示用 enum（ThemeColor / MaterialStrength / ColorSchemeMode / TextScale / RingThickness / HandThickness / CircleOutlineThickness）
- 拡張 Notification.Name
- Color RGB 永続化 helpers

を 1 ファイルに抱えている。CLAUDE.md「200-400 行典型、800 max」内だが責務が 4 層混在。

#### H-2：ClockView の `@State` 13 個 + 手動 broadcast
`UI/ClockView.swift` が 13 個の `@State` プロパティを抱え、`.onReceive(.tokiAppearanceChanged)` 内で 12 行の手動代入で再同期している：

```swift
@State private var opacity: Double = AppSettings.shared.opacity
@State private var themeColorValue: Color = AppSettings.shared.themeColor.color
@State private var materialStrength: MaterialStrength = AppSettings.shared.materialStrength
// ... 計 13 個

.onReceive(NotificationCenter.default.publisher(for: .tokiAppearanceChanged)) { _ in
    themeColorValue = AppSettings.shared.themeColor.color
    materialStrength = AppSettings.shared.materialStrength
    // ... 計 12 行
}
```

新規軸が増えるたびに「ClockView の `@State` + onReceive 内代入 + SettingsView の `@State` + onChange」の 4 箇所を同期する必要があり、ヒューマンエラーの温床。

#### H-3：SettingsView 11 セクション
`UI/SettingsView.swift` が 11 個の `private var ...: some View` を 1 ファイルに保持。各 section で `AppSettings.shared.X = newValue` + `NotificationCenter.default.post(...)` のボイラープレートが繰り返される。

#### H-4：ThemeColor の循環依存
`enum ThemeColor.color` の `.custom` ケースが `AppSettings.shared.customThemeColor` を読み戻す：

```swift
var color: Color {
    switch self {
    case .accent: return .accentColor
    // ...
    case .custom: return AppSettings.shared.customThemeColor   // ← 値型 enum がグローバル状態を読む
    }
}
```

- 純粋性のない getter（呼び出し位置で返り値が変わる）
- ClockView で「enum 値が `.custom` のままで色だけ変わるケース」のために `@State Color themeColorValue` を別途分離する原因

## Goal

Phase 3.1（本 iteration 完了時）に達成する状態：

1. **AppearanceModel 化**：`@MainActor final class AppearanceModel: ObservableObject` を Composition 配下に新設、`@Published` で 13 プロパティを集約管理
2. **AppSettings 構造分割**：3 ファイルに整理
   - `Composition/SettingsStore.swift`：UserDefaults wrapper（Foundation のみ）
   - `Composition/AppearanceModel.swift`：`ObservableObject` + 設定変更ハンドラ
   - `UI/AppearanceTokens.swift`：UI 用 enum 群（SwiftUI / AppKit 依存）
3. **ClockView を `@StateObject` ベースに**：13 個の `@State` + `.onReceive` を `@StateObject AppearanceModel` 1 つに集約、`@Published` の自動 binding に変更
4. **SettingsView 細分化**：11 セクションを `UI/Settings/` 配下のサブ View に分割、`@ObservedObject AppearanceModel` で各 section が `@Binding` 1 つを受けるだけのシンプルな構造に
5. **ThemeColor 循環依存解消**：`AppSettings.shared` への読み戻しを廃止、`AppearanceModel.resolvedThemeColor: Color` を一意の供給源にする
6. **通知 broadcast 廃止**：`tokiAppearanceChanged` 通知を削除（`@Published` の自動 binding で代替）。`tokiOpacityChanged` も同様。
7. **既存挙動の完全維持**：機能変更ゼロ、視覚 / 操作変化なし
8. **Domain テスト 36 ケース無変更で全 pass**：Domain 層は 1 行も触らない

## Non-goals

本 iteration では明示的にやらない：

- **機能追加 / 削除**：設定 UI 11 軸の各機能は完全維持、新軸追加なし
- **UI デザイン変更**：見た目・レイアウト・色・アニメーションは無変更
- **UserDefaults キー rename**（spec 009 H-5）：マイグレーションが絡むので別 spec（012 候補）
- **`tokiGlassBackground(material:)` 化**（spec 009 H-6）：別 spec（012 候補）
- **`@MainActor` 付与**（spec 009 H-7）：`AppearanceModel` で集約するので副次的に解消、AppSettings struct への明示付与は別 spec
- **円の色既定値集約**（spec 009 H-8）：`AppearanceModel` への移動で副次的に集約される
- **popover / tooltip 動的サイズ対応**（spec 010 H-010-1）：別 spec（013 候補）
- **ClockViewModel の責務分割**（spec 010 H-010-3）：別 spec
- **spec 010 §AC 更新（busy block で popover 表示）**（spec 010 M-010-1）：docs only、別 commit で同梱可
- **アクセシビリティ拡張 / i18n / 複数プロファイル**：Phase 3 のさらに後
- **新規 protocol 切り出し**：CLAUDE.md「protocol を念のため切らない」継続
- **外部ライブラリ追加**：禁止継続

## Acceptance Criteria

### ファイル構造

- The `Sources/Toki/Composition/AppSettings.swift` が削除されている（または `SettingsStore.swift` に rename）
- The `Sources/Toki/Composition/SettingsStore.swift` が新規追加され、Foundation のみ依存（SwiftUI / AppKit import なし）
- The `Sources/Toki/Composition/AppearanceModel.swift` が新規追加され、`@MainActor final class AppearanceModel: ObservableObject` を提供
- The `Sources/Toki/UI/AppearanceTokens.swift` が新規追加され、7 個の表示用 enum を集約（SwiftUI / AppKit 依存 OK）
- The `Sources/Toki/UI/Settings/` ディレクトリが新規作成され、11 個のサブ View ファイルを配置
- The 既存 `Sources/Toki/UI/SettingsView.swift` は ScrollView + サブ View 並び替えのみのコンテナ View に縮小

### AppearanceModel の責務

- The `AppearanceModel` が以下の `@Published` プロパティを持つ：
  - `opacity: Double`
  - `themeColor: ThemeColor`
  - `customThemeColor: Color`
  - `materialStrength: MaterialStrength`
  - `colorSchemeMode: ColorSchemeMode`
  - `useCustomBackground: Bool`
  - `customBackgroundColor: Color`
  - `useCustomTextColor: Bool`
  - `customTextColor: Color`
  - `textScale: TextScale`
  - `ringThickness: RingThickness`
  - `handThickness: HandThickness`
  - `circleOutlineThickness: CircleOutlineThickness`
  - `useCustomCircleColor: Bool`
  - `customCircleColor: Color`
- The 各 `@Published` プロパティの `didSet` で `SettingsStore` に永続化する
- The `init()` で `SettingsStore` から全プロパティを読み込む
- The `resolvedThemeColor: Color` computed property を提供（`themeColor == .custom` のとき `customThemeColor` を返す、それ以外は `themeColor.color`）

### ThemeColor 循環依存解消

- The `enum ThemeColor.color` の `.custom` ケースが `AppSettings.shared` を読み戻さない構造になる
- The 解決済み `Color` は `AppearanceModel.resolvedThemeColor` を介して提供される
- The `ClockView` / `ClockFaceCanvas` 等は `themeColor` enum ではなく resolved `Color` を受け取る

### ClockView の変更

- The `ClockView` が `@StateObject private var appearance = AppearanceModel()` を持つ
- The 13 個の `@State` プロパティを撤廃
- The `.onReceive(.tokiAppearanceChanged)` / `.onReceive(.tokiOpacityChanged)` を撤廃
- The 各設定値は `appearance.$xxx` 経由で `@Published` の自動 binding により再描画される
- The `AppSettings.shared` への直接参照を ClockView から削除（resolved 値は `appearance.xxx` 経由）

### SettingsView の変更

- The `SettingsView` が `@ObservedObject var appearance: AppearanceModel` を受け取る
- The 11 セクションがそれぞれ独立した View ファイルに分割：
  - `UI/Settings/OpacitySection.swift`
  - `UI/Settings/ThemeColorSection.swift`
  - `UI/Settings/ColorSchemeSection.swift`
  - `UI/Settings/MaterialStrengthSection.swift`
  - `UI/Settings/CustomBackgroundSection.swift`
  - `UI/Settings/CustomTextColorSection.swift`
  - `UI/Settings/TextScaleSection.swift`
  - `UI/Settings/RingThicknessSection.swift`
  - `UI/Settings/HandThicknessSection.swift`
  - `UI/Settings/CircleOutlineThicknessSection.swift`
  - `UI/Settings/CustomCircleColorSection.swift`
- The 各サブ View は `@ObservedObject var appearance: AppearanceModel` を受け取り、`@Binding` 不要（`appearance.$xxx` で直接 binding）
- The 各 section の `.onChange` ハンドラ（`AppSettings.shared.X = newValue` + `NotificationCenter.post`）を撤廃、`@Published` の `didSet` で永続化に集約

### AppDelegate の変更

- The `AppDelegate.handleOpenSettings` で生成する `SettingsView` に `appearance` を渡す
- The `AppDelegate` の `viewModel?.start()` から ViewModel ↔ AppearanceModel の経路を構築（具体的には `ClockViewModel` も AppearanceModel を `@ObservedObject` で受け取る、または ClockView で直接 inject）

### 通知の撤廃

- The `Notification.Name.tokiOpacityChanged` を削除
- The `Notification.Name.tokiAppearanceChanged` を削除
- The 各 View の `.onReceive` 関連コードを撤廃

### 既存挙動の維持（機能変更ゼロ）

- The 設定 UI 11 軸の見た目・操作・即時反映は完全に同一
- The 透過率スライダー / カラーピッカー / セグメンテッドピッカーは無変更で動作
- The アプリ再起動後に全設定が復元される
- The ホバーツールチップ / popover / 円弧描画 / 中央テキスト / 「次の予定」/ 「最終更新 X 分前」は無変更
- The OAuth フロー / メニュー / リサイズ / 位置記憶は無変更
- The Liquid Glass / Material fallback は無変更

### コード品質

- The `AppearanceModel.swift` は 200 行以内
- The `SettingsStore.swift` は 150 行以内
- The `AppearanceTokens.swift` は 250 行以内（7 個の enum + displayName / factor / color 等の computed）
- The 各 `UI/Settings/*.swift` は 50 行以内
- The `SettingsView.swift` は 60 行以内（サブ View 並び替えのみ）
- The `ClockView.swift` は 200 行以内（@State 削減 + 不要 import 削除）
- The Domain テスト 36 ケース全 pass

## Domain Model

本 iteration は Domain 層に変更を入れない。Composition / UI 層のみ変更。

## Open Questions

実装着手前に判断したい論点：

### AppearanceModel 設計
1. **`AppearanceModel` の `@Published` 永続化方式**：`didSet` で書き込む vs Combine sink で書き込む。**`didSet` 推奨**（シンプル）
2. **`AppearanceModel.shared` シングルトン vs `@StateObject` 内蔵 vs DI**：ClockView と SettingsView の両方が同じインスタンスを参照する必要がある。**AppDelegate で生成 → ClockView と SettingsView に `@ObservedObject` で渡す**推奨。ただし ClockView は `@StateObject` で内部に持って、SettingsView は AppDelegate 経由で同じインスタンス参照、という形でも OK
3. **`resolvedThemeColor` の場所**：`AppearanceModel` の computed property / `ThemeColor` enum の method / 別 helper。**`AppearanceModel.resolvedThemeColor`** 推奨（model が一意の supply 源）

### ThemeColor 改修
4. **`ThemeColor.color` の `.custom` ケースの扱い**：完全削除（accent ケース等のみ提供）/ パラメータで受け取る（`func color(customFallback: Color) -> Color`）。**完全削除**推奨：`.custom` のときは `AppearanceModel.resolvedThemeColor` で解決、enum 自体は preset 用に純化
5. **`ThemeColor.allCases` への `.custom` の存在**：UI 側で「カスタム」プリセットボタンの表示に必要。Picker 上は `.custom` を選択できるが、`color` プロパティ呼び出しは不可（fatalError？ or accentColor フォールバック？）。**`.custom` ケース存在維持、`color` は accentColor フォールバック（呼び出し側は `resolvedThemeColor` を使う前提）**

### ClockView 整理
6. **`AppearanceModel` の inject 方法**：`@StateObject` で ClockView 内に閉じる vs AppDelegate 注入。**AppDelegate 注入** 推奨（SettingsView との共有が容易、ViewModel との結合も明示的）
7. **`ClockViewModel` への適用**：ClockViewModel も `AppearanceModel` 参照すべきか。**ClockViewModel は触らない**（テーマカラー等は View レイヤーの責務、ViewModel は Domain 中心）。`previewedEvent` 等のロジック state は維持

### SettingsView 分割
8. **サブ View ファイル名**：`UI/Settings/<Topic>Section.swift` / `UI/Settings/<Topic>SettingsRow.swift`。**`Section.swift` 接尾辞** 推奨（既存命名と整合）
9. **サブ View の構造**：各 View 内で `appearance.$xxx` バインドを使う / `@Binding` で渡す。**`@ObservedObject AppearanceModel` を全 View で受け取り、Picker / Slider に `appearance.$xxx` を直接バインド** 推奨

### 通知撤廃
10. **`tokiOpacityChanged` / `tokiAppearanceChanged` の削除タイミング**：AppearanceModel 移行完了直後に同 commit で削除 / 別 commit で削除。**同 commit 内で削除** 推奨（通知購読側を全て撤廃するタスクと同じ範囲）

### 互換性
11. **UserDefaults キーの維持**：`AppearanceModel.didSet` 内で書き込む UserDefaults キーは現状と同じ rawValue を維持する（spec 011 §Non-goals「UserDefaults キー rename は別 spec」）。**完全互換、既存ユーザーは設定そのまま** 推奨
12. **`Notification.Name` extension 自体**：`tokiOpacityChanged` / `tokiAppearanceChanged` を撤廃するが、`Notification.Name` extension 全体は他で使われないなら削除可。**全削除** 推奨（残骸を残さない）

### コード規模
13. **段階的 commit 分割**：「AppearanceModel 新規作成」「AppSettings 撤廃」「ClockView 移行」「SettingsView 分割」を別 commit にする vs まとめる。**段階的 commit**（plan で 10〜15 task に分解する想定）

[NEEDS INPUT] は最大 3 件以下に絞る → 0 件、すべて [CONFIDENT] で着手可能。

## Out of scope / Phase 3 以降

参考：

- **spec 012 候補**：
  - `tokiGlassBackground(material:)` 化（spec 009 H-6）
  - UserDefaults キー rename + マイグレーション（spec 009 H-5）
  - `@MainActor` 付与 を `SettingsStore` にも明示（spec 009 H-7）
  - 円の色既定値集約は spec 011 で副次的に解消されるはず
- **spec 013 候補**：
  - popover / tooltip 動的サイズ対応（spec 010 H-010-1）
  - ClockViewModel 責務分割（spec 010 H-010-3）
  - spec 010 §AC 更新（spec 010 M-010-1、docs only）
- **Phase 3 後半**：
  - Dynamic Type 連動
  - VoiceOver 対応
  - i18n
  - 設定プロファイル切替
  - 設定エクスポート / インポート

---

## 補足：本 spec の効果

機能変更ゼロだが、内部構造的には以下が改善される：

| Before | After |
|---|---|
| `AppSettings.swift` 439 行 | 3 ファイル分割（各 < 250 行） |
| ClockView の `@State` 13 個 + 通知 1 本 broadcast | `@StateObject AppearanceModel` 1 つ |
| SettingsView 11 セクション 292 行 | 11 サブ View 各 < 50 行 + コンテナ 60 行 |
| `ThemeColor.color` が `AppSettings.shared` を循環参照 | `AppearanceModel.resolvedThemeColor` で一意供給 |
| 新規設定軸追加で 4 箇所同期が必要 | `AppearanceModel` に `@Published` 1 行追加 + サブ View 1 ファイル追加で完結 |

将来の設定軸追加 / レビュー指摘の解消 / 構造的負債整理が大幅に楽になる。
