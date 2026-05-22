# 011 — AppearanceModel リファクタ 技術プラン

`specs/011-appearance-model.md` を技術プランに展開したもの。`/tasks` で atomic task に分解する元となる。

## 0. 確定済み設計判断（13 項目すべて [CONFIDENT]）

| # | 論点 | 判断 |
|---|---|---|
| 1 | `@Published` 永続化方式 | `didSet` で `SettingsStore` に書き込む |
| 2 | AppearanceModel 生成 / 注入 | AppDelegate で生成 → ClockView と SettingsView に `@ObservedObject` で共有 |
| 3 | `resolvedThemeColor` の場所 | `AppearanceModel` の computed property |
| 4 | `ThemeColor.color` の `.custom` ケース | `.accentColor` フォールバック |
| 5 | `ThemeColor.allCases` の `.custom` 存在 | 維持 |
| 6 | ClockView への inject | AppDelegate 注入 |
| 7 | ClockViewModel への適用 | 触らない |
| 8 | サブ View 命名 | `UI/Settings/<Topic>Section.swift` |
| 9 | サブ View 構造 | `@ObservedObject AppearanceModel` + `appearance.$xxx` バインド |
| 10 | 通知撤廃 | ClockView 移行と同 commit で削除 |
| 11 | UserDefaults キー互換 | rawValue 完全維持 |
| 12 | `Notification.Name` extension | 全削除 |
| 13 | commit 分割 | 段階的 11 task |

## 1. Requirements restatement

`AppSettings.swift` 439 行を 3 ファイル分割し、`ClockView` の `@State` 13 個 + 通知 broadcast を `@ObservedObject AppearanceModel` 1 つに集約。`SettingsView` 11 セクションを `UI/Settings/<Topic>Section.swift` 11 ファイルに分割。`ThemeColor.color` の循環依存を解消し `AppearanceModel.resolvedThemeColor` を一意供給源にする。機能変更ゼロ、UserDefaults キー互換維持、Domain 36 テスト無変更で全 pass。

## 2. ファイル別変更計画

### 新規（3 + サブ View 11 = 14 ファイル）

| パス | 役割 | 想定行数 |
|---|---|---|
| `Composition/SettingsStore.swift` | UserDefaults wrapper、永続化レイヤー | ~150 |
| `Composition/AppearanceModel.swift` | `@MainActor ObservableObject` + @Published 15 + didSet + resolved props | ~200 |
| `UI/AppearanceTokens.swift` | 7 enum 集約（`.custom` は accentColor fallback） | ~250 |
| `UI/Settings/OpacitySection.swift` | 透過率 | ~30 |
| `UI/Settings/ThemeColorSection.swift` | テーマカラー + ColorPicker | ~50 |
| `UI/Settings/ColorSchemeSection.swift` | 配色モード | ~25 |
| `UI/Settings/MaterialStrengthSection.swift` | 背景の濃さ | ~25 |
| `UI/Settings/CustomBackgroundSection.swift` | 背景色 Toggle + Picker | ~35 |
| `UI/Settings/CustomTextColorSection.swift` | 文字色 Toggle + Picker | ~35 |
| `UI/Settings/TextScaleSection.swift` | 文字サイズ | ~25 |
| `UI/Settings/RingThicknessSection.swift` | リング太さ | ~25 |
| `UI/Settings/HandThicknessSection.swift` | 針太さ | ~25 |
| `UI/Settings/CircleOutlineThicknessSection.swift` | 円輪郭太さ | ~25 |
| `UI/Settings/CustomCircleColorSection.swift` | 円色 Toggle + Picker | ~35 |

### 編集（4 ファイル）

| パス | 編集内容 |
|---|---|
| `UI/ClockView.swift` | `@State` 13 個撤廃 / `.onReceive` 2 個撤廃 / `init(viewModel:appearance:)` で `@ObservedObject` 受け取り |
| `UI/SettingsView.swift` | 11 セクション撤廃 / `init(appearance:)` / ScrollView + サブ View 並び替えのみ |
| `App/AppDelegate.swift` | `appearance: AppearanceModel?` プロパティ追加 / ClockView と SettingsView に注入 / `SettingsStore.shared.windowFrame` に切替 |
| `Composition/ClockViewModel.swift` | 無変更（確認のみ） |

### 削除（1 ファイル）

| パス | 理由 |
|---|---|
| `Composition/AppSettings.swift` | 内容を 3 ファイルに完全移行後、削除 |

## 3. AppearanceModel 詳細

```swift
@MainActor
final class AppearanceModel: ObservableObject {
    private let store: SettingsStore

    @Published var opacity: Double { didSet { store.opacity = opacity } }
    @Published var themeColor: ThemeColor { didSet { store.themeColor = themeColor } }
    @Published var customThemeColor: Color { didSet { store.customThemeColor = customThemeColor } }
    // ... 15 個

    init(store: SettingsStore = .shared) {
        self.store = store
        // backing storage 直接代入で didSet 回避
        self._opacity = Published(initialValue: store.opacity)
        self._themeColor = Published(initialValue: store.themeColor)
        // ... 15 個
    }

    var resolvedThemeColor: Color {
        themeColor == .custom ? customThemeColor : themeColor.color
    }

    /// 円自体の輪郭色。useCustomCircleColor で分岐。
    /// spec 009 H-8（円の色既定値リテラル分散）を副次解消。
    var resolvedCircleOutlineColor: Color {
        useCustomCircleColor ? customCircleColor : .secondary.opacity(0.6)
    }
}
```

## 4. SettingsStore 詳細

`@MainActor final class SettingsStore`、`shared` シングルトン。

- 既存 `AppSettings.swift` の永続化ロジックをそのまま移植
- キー名は `AppSettings.Key` と完全一致（rawValue 互換）
- Color プロパティを公開、内部で NSColor → R/G/B Double 分解（既存 `readColor` / `writeColor` 移植）
- `windowFrame` も同居（AppDelegate が直接利用）
- `@MainActor` 付与で spec 009 H-7 副次解消

## 5. AppearanceTokens 詳細

7 enum を `UI/AppearanceTokens.swift` に集約。`ThemeColor.color` の `.custom` を `.accentColor` フォールバックに変更：

```swift
case .custom: return .accentColor  // resolvedThemeColor 経由で解決される前提
```

ファイル長 ~250 行。

## 6. ClockView 移行詳細

```swift
struct ClockView: View {
    @ObservedObject var viewModel: ClockViewModel
    @ObservedObject var appearance: AppearanceModel

    var body: some View {
        // @State 13 個 → appearance.xxx 参照
        // .onReceive 2 個 → 削除（@Published 自動 binding）
        ClockFaceCanvas(
            themeColor: appearance.resolvedThemeColor,
            circleOutlineColor: appearance.resolvedCircleOutlineColor,
            // ...
        )
    }
}
```

## 7. SettingsView 細分化

```swift
struct SettingsView: View {
    @ObservedObject var appearance: AppearanceModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                OpacitySection(appearance: appearance)
                ThemeColorSection(appearance: appearance)
                // ... 11 サブ View
            }
            .padding(20)
        }
        .frame(width: 340, height: 860)
        .tokiGlassBackground(cornerRadius: 12)
    }
}
```

各サブ View（例 `OpacitySection`）：
```swift
struct OpacitySection: View {
    @ObservedObject var appearance: AppearanceModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("透過率").font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(appearance.opacity * 100))%").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Slider(value: $appearance.opacity, in: 0.05...1.0)
        }
    }
}
```

`.onChange` 撤廃（永続化は `didSet`）。

## 8. 実装フェーズ順序

11 task：

1. `feat(ui): AppearanceTokens を新規作成（7 enum 集約、.custom を accentColor fallback に）`
2. `feat(composition): SettingsStore を新規作成（UserDefaults wrapper、@MainActor）`
3. `feat(composition): AppearanceModel を新規作成（@Published 15 + didSet + init + resolved props）`
4. `feat(app): AppDelegate で AppearanceModel を生成 / 注入`
5. `refactor(ui): ClockView を AppearanceModel ベースに移行`
6. `refactor(ui): SettingsView から 4 セクション分割（Opacity / Theme / ColorScheme / Material）`
7. `refactor(ui): SettingsView から 4 セクション分割（Background / Text / TextScale / Ring）`
8. `refactor(ui): SettingsView から 3 セクション分割 + コンテナ縮小（Hand / Circle / CustomCircle）`
9. `refactor(composition): AppSettings.swift を削除`
10. `refactor(composition): Notification.Name extension を削除`
11. `docs(spec): SPEC.md spec 011 完了反映`

## 9. リスク

| # | リスク | 重大度 | 緩和策 |
|---|---|---|---|
| R1 | `@Published didSet` が init 中も発火 | 中 | `_opacity = Published(initialValue:)` で回避 |
| R2 | ClockView / SettingsView signature 変更影響 | 中 | grep で全呼び出し箇所洗い出し、AppDelegate 2 箇所のみ |
| R3 | `@State` 撤廃で再描画タイミング誤認 | 低 | `@ObservedObject` 標準パターン |
| R4 | サブ View 分割で hierarchy 複雑化 | 低 | フラット構造、SwiftUI が最適化 |
| R5 | Color 永続化のレイヤー境界 | 中 | SettingsStore 内で NSColor 分解完結 |
| R6 | Domain テスト影響 | 0 | Domain 無変更 |
| R7 | 通知購読側残骸 | 低 | grep で全参照削除 |
| R8 | AppearanceModel 200 行超え | 中 | 1 行 @Published で 15 行、init 20 行、computed 10 行、コメント込みで ~150 行 |
| R9 | `ThemeColor.color` 変更影響 | 中 | grep で `.themeColor.color` 参照を `resolvedThemeColor` に置換 |
| R10 | UserDefaults キー互換崩れ | **高** | キー名 1:1 完全一致、Task 2 後に手動確認 |
| R11 | `@MainActor` 付与で非 isolation 呼び出しエラー | 低 | AppDelegate / NotificationCenter callback は main thread |
| R12 | SwiftPM target 設定漏れ | 低 | `Sources/Toki/` 配下は自動収集 |

## 10. テスト方針

### 自動
- Domain 36 ケース無変更で全 pass
- 新規テスト追加なし（既存スタンス継承）

### 手動チェックリスト
- 設定 11 軸の即時反映が変わらない
- アプリ再起動で全 15 軸の値が復元される
- UserDefaults キーが従来のまま（既存ユーザーの設定リセットなし）
- ホバー / popover / 円弧描画 / 中央テキスト / 「次の予定」/「最終更新」は無変更
- OAuth フロー / メニュー / リサイズ / 位置記憶は無変更
- Liquid Glass / Material fallback は無変更

### 残骸チェック
- `grep -r "AppSettings" Sources/` が 0 件
- `grep -r "tokiOpacityChanged\|tokiAppearanceChanged" Sources/` が 0 件

## 11. Out of scope

spec 011 §Non-goals 再掲：
- 機能追加 / 削除なし
- UI デザイン変更なし
- UserDefaults キー rename（spec 012）
- `tokiGlassBackground(material:)` 化（spec 012）
- AppSettings struct への `@MainActor` 明示（class への付与は副次解消済み）
- 円の色既定値集約（resolvedCircleOutlineColor で副次解消）
- popover / tooltip 動的サイズ（spec 013）
- ClockViewModel 責務分割（別 spec）
- アクセシビリティ拡張 / i18n / 複数プロファイル

## 参考ファイル

- `specs/011-appearance-model.md`
- `specs/009-customization.md`
- `specs/010-event-preview-plan.md`

次のステップ：`/tasks 011-appearance-model` で 11 atomic task ファイル化。
