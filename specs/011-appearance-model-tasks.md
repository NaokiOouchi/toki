# 011 — appearance-model: Tasks

参照: `specs/011-appearance-model.md` / `specs/011-appearance-model-plan.md`

合計: **11 tasks**

実装順序：上から順に。各 task は fresh subagent に渡して 1 commit ずつ。

新規 14 ファイル（Composition 2 + UI 12）+ 編集 3 ファイル + 削除 1 ファイル。Domain 36 テスト無変更で全 pass 維持。UserDefaults キー完全互換、既存ユーザーの設定をリセットしない。

---

## Task 1: AppearanceTokens を新規作成

**Commit**: `feat(ui): AppearanceTokens を新規作成（7 enum 集約、.custom を accentColor fallback に）`

**目的**: 既存 `AppSettings.swift` 内の 7 個の表示用 enum を `UI/AppearanceTokens.swift` に新規追加（同居、AppSettings 側はまだ削除しない）。`ThemeColor.color` の `.custom` ケースを `.accentColor` フォールバックに変更（resolvedThemeColor 経由で解決される前提）。

**コンテキスト**:
- 既存 `Sources/Toki/Composition/AppSettings.swift` の 7 enum を Read で確認、内容をそのまま移植
- `ThemeColor.color` の `.custom` ケースだけ変更
- 既存 AppSettings 側の enum は **まだ削除しない**（Task 9 で AppSettings.swift 全体削除時に消える、衝突回避のため後段で）

**実装**:

ファイル: `Sources/Toki/UI/AppearanceTokens.swift`（新規）

```swift
import AppKit
import SwiftUI

// MARK: - ThemeColor

/// テーマカラーのプリセット。針 / 中心ドット等に使う SwiftUI Color を提供。
/// `.custom` の解決済み Color は AppearanceModel.resolvedThemeColor 経由で得る。
enum ThemeColor: String, CaseIterable, Identifiable, Hashable {
    case accent, indigo, blue, cyan, teal, mint, green, yellow, orange, red, pink, purple, brown, gray, custom

    var id: String { rawValue }

    var displayName: String {
        // 既存 AppSettings の implementation を完全移植
    }

    /// プリセット色を返す。`.custom` は呼び出し側で resolvedThemeColor を使う前提のため、
    /// fallback として .accentColor を返す（クラッシュさせない）。
    var color: Color {
        switch self {
        case .accent: return .accentColor
        // ... 既存 case 移植
        case .custom: return .accentColor  // ← spec 011 で循環依存解消
        }
    }
}

// MARK: - MaterialStrength / ColorSchemeMode / TextScale / RingThickness / HandThickness / CircleOutlineThickness

// 既存 AppSettings 側の enum をそのまま移植
```

**完了条件**:
```bash
grep -n "enum ThemeColor" Sources/Toki/UI/AppearanceTokens.swift
# → 1 件

grep -n "enum MaterialStrength" Sources/Toki/UI/AppearanceTokens.swift
grep -n "enum ColorSchemeMode" Sources/Toki/UI/AppearanceTokens.swift
grep -n "enum TextScale" Sources/Toki/UI/AppearanceTokens.swift
grep -n "enum RingThickness" Sources/Toki/UI/AppearanceTokens.swift
grep -n "enum HandThickness" Sources/Toki/UI/AppearanceTokens.swift
grep -n "enum CircleOutlineThickness" Sources/Toki/UI/AppearanceTokens.swift
# → 各 1 件

# .custom が accentColor フォールバック
grep -nA 1 "case .custom:" Sources/Toki/UI/AppearanceTokens.swift
# → "return .accentColor" を含む

# ファイル長 < 300 行
wc -l Sources/Toki/UI/AppearanceTokens.swift

swift build  # AppSettings の enum と衝突するため初回ビルドは失敗するかも
              # → AppSettings 側の enum 名を一時的に prefix 等で衝突回避するか、
              # Task 2 以降と組み合わせて段階移行する設計検討必要
```

**重要な実装ノート**:
- AppSettings 内の既存 enum と **同名衝突** が発生する可能性が高い
- 解決策：本 task では AppearanceTokens.swift のみ追加し、AppSettings 側の enum は **そのまま残す**。Swift の同一 module 内で同名 enum 重複はエラーになるため、**AppSettings 側の enum を本 task 内で削除する** 形にする

修正版実装手順：
1. `AppearanceTokens.swift` を新規追加（既存 enum と同名）
2. **同 commit で** AppSettings.swift から 7 個の enum 定義のみ削除（struct AppSettings 内のプロパティで参照されているため、`AppSettings.swift` の enum 削除のみで build エラーにならない）
3. ビルド確認、Domain テスト pass

**コミット**:
```bash
git add Sources/Toki/UI/AppearanceTokens.swift Sources/Toki/Composition/AppSettings.swift
git commit -m "feat(ui): AppearanceTokens を新規作成（7 enum 集約、.custom を accentColor fallback に）"
```

**依存**: なし

---

## Task 2: SettingsStore を新規作成

**Commit**: `feat(composition): SettingsStore を新規作成（UserDefaults wrapper、@MainActor）`

**目的**: 既存 `AppSettings.swift` の永続化ロジックを `Composition/SettingsStore.swift` に新規追加。`@MainActor final class` で UserDefaults wrapper を実装、Color プロパティを公開（内部で R/G/B Double 分解）。

**コンテキスト**:
- 既存 AppSettings の永続化部分（プロパティ getter / setter + readColor / writeColor helper）を移植
- キー名は AppSettings.Key.\* と完全一致を維持（UserDefaults rawValue 互換）
- `nonmutating set` を通常の var setter に変更（class なので）
- AppSettings.swift は **まだ削除しない**（Task 9 で削除）。本 task では SettingsStore を追加し、AppSettings を温存（並行存在）

**実装**:

ファイル: `Sources/Toki/Composition/SettingsStore.swift`（新規）

```swift
import AppKit
import Foundation
import SwiftUI

/// UserDefaults wrapper。AppearanceModel が単一の永続化バックエンドとして利用する。
/// SwiftUI Color の R/G/B 分解は内部で完結する（呼び出し側は Color のみ扱う）。
/// キー名は AppSettings 時代の rawValue を完全維持（spec 011 §Non-goals）。
@MainActor
final class SettingsStore {
    static let shared = SettingsStore()
    private let defaults = UserDefaults.standard

    private enum Key {
        // 既存 AppSettings.Key と 1:1 完全一致（rawValue 互換）
        static let opacity = "toki.opacity"
        static let windowFrameX = "toki.windowFrame.x"
        // ... 全 27 キー
    }

    // 既存 AppSettings.swift のプロパティ getter/setter を完全移植
    // nonmutating set を通常の setter に変更
    
    var opacity: Double {
        get { /* 既存ロジック */ }
        set { /* 既存ロジック */ }
    }
    // ... 15 プロパティ + windowFrame
    
    // 既存 readColor / writeColor helper も完全移植
    private static func readColor(...) -> Color { /* 既存 */ }
    private static func writeColor(...) { /* 既存 */ }
}
```

**完了条件**:
```bash
grep -n "final class SettingsStore" Sources/Toki/Composition/SettingsStore.swift
# → 1 件

grep -n "@MainActor" Sources/Toki/Composition/SettingsStore.swift
# → 1 件以上

grep -n "static let shared" Sources/Toki/Composition/SettingsStore.swift
# → 1 件

# UserDefaults キーが AppSettings と一致（rawValue 互換）
grep -n 'static let opacity = "toki.opacity"' Sources/Toki/Composition/SettingsStore.swift
# → 1 件
grep -n 'static let themeColor = "toki.themeColor"' Sources/Toki/Composition/SettingsStore.swift
# → 1 件
# ...（主要キーを確認）

# ファイル長 < 200 行
wc -l Sources/Toki/Composition/SettingsStore.swift

swift build  # AppSettings と SettingsStore 並行存在、両方ビルドOK
swift test   # 36 ケース pass
```

**コミット**:
```bash
git add Sources/Toki/Composition/SettingsStore.swift
git commit -m "feat(composition): SettingsStore を新規作成（UserDefaults wrapper、@MainActor）"
```

**依存**: Task 1（AppearanceTokens の enum 型を SettingsStore が参照）

---

## Task 3: AppearanceModel を新規作成

**Commit**: `feat(composition): AppearanceModel を新規作成（@Published 15 + didSet + init + resolved props）`

**目的**: `Composition/AppearanceModel.swift` を新規追加。`@MainActor final class ObservableObject` で 15 個の `@Published` プロパティを持ち、`didSet` で `SettingsStore` に永続化、`resolvedThemeColor` / `resolvedCircleOutlineColor` を提供。

**実装**:

ファイル: `Sources/Toki/Composition/AppearanceModel.swift`（新規）

```swift
import AppKit
import SwiftUI

/// 全ての UI 設定値を集約する ObservableObject。
/// 各 @Published の didSet で SettingsStore に永続化する。
/// AppDelegate が単一インスタンスを生成し、ClockView と SettingsView に @ObservedObject で渡す。
@MainActor
final class AppearanceModel: ObservableObject {
    private let store: SettingsStore

    @Published var opacity: Double { didSet { store.opacity = opacity } }
    @Published var themeColor: ThemeColor { didSet { store.themeColor = themeColor } }
    @Published var customThemeColor: Color { didSet { store.customThemeColor = customThemeColor } }
    @Published var materialStrength: MaterialStrength { didSet { store.materialStrength = materialStrength } }
    @Published var colorSchemeMode: ColorSchemeMode { didSet { store.colorSchemeMode = colorSchemeMode } }
    @Published var useCustomBackground: Bool { didSet { store.useCustomBackground = useCustomBackground } }
    @Published var customBackgroundColor: Color { didSet { store.customBackgroundColor = customBackgroundColor } }
    @Published var useCustomTextColor: Bool { didSet { store.useCustomTextColor = useCustomTextColor } }
    @Published var customTextColor: Color { didSet { store.customTextColor = customTextColor } }
    @Published var textScale: TextScale { didSet { store.textScale = textScale } }
    @Published var ringThickness: RingThickness { didSet { store.ringThickness = ringThickness } }
    @Published var handThickness: HandThickness { didSet { store.handThickness = handThickness } }
    @Published var circleOutlineThickness: CircleOutlineThickness { didSet { store.circleOutlineThickness = circleOutlineThickness } }
    @Published var useCustomCircleColor: Bool { didSet { store.useCustomCircleColor = useCustomCircleColor } }
    @Published var customCircleColor: Color { didSet { store.customCircleColor = customCircleColor } }

    init(store: SettingsStore = .shared) {
        self.store = store
        // backing storage 直接代入で didSet を回避（init 中の冗長な書き戻し防止）
        self._opacity = Published(initialValue: store.opacity)
        self._themeColor = Published(initialValue: store.themeColor)
        self._customThemeColor = Published(initialValue: store.customThemeColor)
        self._materialStrength = Published(initialValue: store.materialStrength)
        self._colorSchemeMode = Published(initialValue: store.colorSchemeMode)
        self._useCustomBackground = Published(initialValue: store.useCustomBackground)
        self._customBackgroundColor = Published(initialValue: store.customBackgroundColor)
        self._useCustomTextColor = Published(initialValue: store.useCustomTextColor)
        self._customTextColor = Published(initialValue: store.customTextColor)
        self._textScale = Published(initialValue: store.textScale)
        self._ringThickness = Published(initialValue: store.ringThickness)
        self._handThickness = Published(initialValue: store.handThickness)
        self._circleOutlineThickness = Published(initialValue: store.circleOutlineThickness)
        self._useCustomCircleColor = Published(initialValue: store.useCustomCircleColor)
        self._customCircleColor = Published(initialValue: store.customCircleColor)
    }

    /// テーマカラーの解決済み Color。`.custom` のときは customThemeColor を返す。
    /// ClockView 等は this を使い、enum 値を直接 .color 経由で評価しない。
    var resolvedThemeColor: Color {
        themeColor == .custom ? customThemeColor : themeColor.color
    }

    /// 円自体の輪郭色の解決済み Color。useCustomCircleColor で分岐。
    /// spec 009 H-8（円の色既定値リテラル分散）の副次解消。
    var resolvedCircleOutlineColor: Color {
        useCustomCircleColor ? customCircleColor : .secondary.opacity(0.6)
    }
}
```

**完了条件**:
```bash
grep -n "final class AppearanceModel" Sources/Toki/Composition/AppearanceModel.swift
# → 1 件

grep -n ": ObservableObject" Sources/Toki/Composition/AppearanceModel.swift
# → 1 件

# @Published 15 個
grep -c "@Published var" Sources/Toki/Composition/AppearanceModel.swift
# → 15

# resolved properties
grep -n "var resolvedThemeColor: Color" Sources/Toki/Composition/AppearanceModel.swift
grep -n "var resolvedCircleOutlineColor: Color" Sources/Toki/Composition/AppearanceModel.swift
# → 各 1 件

# init で backing storage 代入
grep -c "self._" Sources/Toki/Composition/AppearanceModel.swift
# → 15

# ファイル長 < 250 行
wc -l Sources/Toki/Composition/AppearanceModel.swift

swift build && swift test  # 36 ケース pass
```

**コミット**:
```bash
git add Sources/Toki/Composition/AppearanceModel.swift
git commit -m "feat(composition): AppearanceModel を新規作成（@Published 15 + didSet + init + resolved props）"
```

**依存**: Task 1, 2

---

## Task 4: AppDelegate で AppearanceModel を生成 / 注入

**Commit**: `feat(app): AppDelegate で AppearanceModel を生成 / 注入（ClockView と SettingsView）`

**目的**: AppDelegate が `AppearanceModel` を 1 度生成し、ClockView と SettingsView に同じインスタンスを `@ObservedObject` で共有させる。`AppSettings.shared.windowFrame` を `SettingsStore.shared.windowFrame` に切替。

**コンテキスト**:
- ClockView と SettingsView の signature 変更は **本 task では行わない**（Task 5 / 6-8 で実施）。本 task では AppearanceModel の生成と保持のみ。
- windowFrame の参照を `SettingsStore.shared` に切替（6 箇所程度）

**実装**:

ファイル: `Sources/Toki/App/AppDelegate.swift`（編集）

#### Step 1: プロパティ追加

```swift
/// アプリ全体で共有する AppearanceModel。ClockView と SettingsView が同インスタンスを参照する。
private var appearance: AppearanceModel?
```

#### Step 2: applicationDidFinishLaunching で生成

```swift
let appearance = AppearanceModel()
self.appearance = appearance
```

ViewModel 生成と FloatingClockWindow.make の間の任意の位置。

#### Step 3: windowFrame 参照を SettingsStore に切替

`AppSettings.shared.windowFrame` を `SettingsStore.shared.windowFrame` に置換。同様に `AppSettings.shared.setWindowFrame(_:)` を `SettingsStore.shared.setWindowFrame(_:)` に置換。

**重要**: ClockView と SettingsView の signature 変更は Task 5 / 8 で行う。本 task では呼び出し箇所はそのまま（`ClockView(viewModel: vm)` / `SettingsView()` のまま）、`appearance` プロパティを保持するだけ。

**完了条件**:
```bash
grep -n "private var appearance: AppearanceModel?" Sources/Toki/App/AppDelegate.swift
# → 1 件

grep -n "let appearance = AppearanceModel()" Sources/Toki/App/AppDelegate.swift
# → 1 件

# windowFrame の切替
grep -c "SettingsStore.shared.windowFrame" Sources/Toki/App/AppDelegate.swift
# → 1 件以上

grep -c "AppSettings.shared.windowFrame" Sources/Toki/App/AppDelegate.swift
# → 0 件

grep -c "SettingsStore.shared.setWindowFrame" Sources/Toki/App/AppDelegate.swift
# → 1 件以上

grep -c "AppSettings.shared.setWindowFrame" Sources/Toki/App/AppDelegate.swift
# → 0 件

swift build && swift test
./scripts/build-app.sh
```

実機目視（subagent 範囲外）：
- アプリ起動 → 既存通り
- ウィンドウ位置 / サイズ復元 → 既存通り

**コミット**:
```bash
git add Sources/Toki/App/AppDelegate.swift
git commit -m "feat(app): AppDelegate で AppearanceModel を生成 / 注入（ClockView と SettingsView）"
```

**依存**: Task 2, 3

---

## Task 5: ClockView を AppearanceModel ベースに移行

**Commit**: `refactor(ui): ClockView を AppearanceModel ベースに移行（@State 13 個 + onReceive 2 個を撤廃）`

**目的**: ClockView の `@State` 13 個 + `.onReceive` 2 個を撤廃し、`@ObservedObject AppearanceModel` 1 つで集約。各設定値は `appearance.xxx` 経由で参照、`@Published` の自動 binding で再描画される。

**コンテキスト**:
- ClockView 内の `AppSettings.shared` 直接参照を全て削除
- `themeColorValue` (resolved Color) を `appearance.resolvedThemeColor` に置換
- `useCustomCircleColor ? customCircleColor : .secondary.opacity(0.6)` を `appearance.resolvedCircleOutlineColor` に置換
- AppDelegate 側の `ClockView(viewModel:)` 呼び出しを `ClockView(viewModel:appearance:)` に変更（FloatingClockWindow.make 経由）
- `.onReceive(.tokiOpacityChanged)` / `.onReceive(.tokiAppearanceChanged)` を撤廃

**実装**:

### ファイル 1: `Sources/Toki/UI/ClockView.swift`（編集）

```swift
struct ClockView: View {
    @ObservedObject var viewModel: ClockViewModel
    @ObservedObject var appearance: AppearanceModel
    
    // @State 13 個を撤廃

    var body: some View {
        ZStack(alignment: .topLeading) {
            glassBackgroundLayer
            VStack(spacing: 0) {
                ZStack {
                    ClockFaceCanvas(
                        nowAngle: viewModel.nowAngle,
                        events: viewModel.canvasEvents,
                        themeColor: appearance.resolvedThemeColor,
                        ringThickness: appearance.ringThickness.factor,
                        handLineWidth: appearance.handThickness.lineWidth,
                        textScale: appearance.textScale.factor,
                        circleOutlineLineWidth: appearance.circleOutlineThickness.lineWidth,
                        circleOutlineColor: appearance.resolvedCircleOutlineColor,
                        onTap: { /* ... */ },
                        onHover: { /* ... */ }
                    )
                    CurrentEventLabel(state: viewModel.centerState, textScale: appearance.textScale.factor)
                        .allowsHitTesting(false)
                }
                // ...
            }
            // popover / tooltip の textScale も appearance.textScale.factor に置換
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(appearance.resolvedThemeColor.opacity(0.5), lineWidth: 0.75)
        )
        .foregroundStyle(appearance.useCustomTextColor ? appearance.customTextColor : .primary)
        .preferredColorScheme(appearance.colorSchemeMode.swiftUIColorScheme)
        // .onReceive 2 個を撤廃
    }
    
    @ViewBuilder
    private var glassBackgroundLayer: some View {
        if appearance.useCustomBackground {
            RoundedRectangle(cornerRadius: 12)
                .fill(appearance.customBackgroundColor)
                .opacity(appearance.opacity)
        } else if #available(macOS 26.0, *) {
            Rectangle()
                .fill(appearance.materialStrength.swiftUIMaterial)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                .opacity(appearance.opacity)
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(appearance.materialStrength.swiftUIMaterial)
                .opacity(appearance.opacity)
        }
    }
}
```

### ファイル 2: `Sources/Toki/App/AppDelegate.swift`（編集）

```swift
let w = FloatingClockWindow.make(contentView: ClockView(viewModel: vm, appearance: appearance))
```

`ClockView(viewModel: vm)` → `ClockView(viewModel: vm, appearance: appearance)` に変更。

**完了条件**:
```bash
# @State 撤廃
grep -c "@State private var" Sources/Toki/UI/ClockView.swift
# → 0 件

# @ObservedObject 追加
grep -n "@ObservedObject var appearance: AppearanceModel" Sources/Toki/UI/ClockView.swift
# → 1 件

# AppSettings.shared 参照ゼロ
grep -n "AppSettings.shared" Sources/Toki/UI/ClockView.swift
# → 0 件

# .onReceive 撤廃
grep -c "tokiOpacityChanged\|tokiAppearanceChanged" Sources/Toki/UI/ClockView.swift
# → 0 件

# resolved* の使用
grep -n "appearance.resolvedThemeColor" Sources/Toki/UI/ClockView.swift
grep -n "appearance.resolvedCircleOutlineColor" Sources/Toki/UI/ClockView.swift
# → 各 1 件以上

# AppDelegate 側の signature 変更
grep -n "ClockView(viewModel:.*appearance:" Sources/Toki/App/AppDelegate.swift
# → 1 件

# ファイル長 < 250 行
wc -l Sources/Toki/UI/ClockView.swift

swift build && swift test  # 36 ケース pass
./scripts/build-app.sh
```

**コミット**:
```bash
git add Sources/Toki/UI/ClockView.swift Sources/Toki/App/AppDelegate.swift
git commit -m "refactor(ui): ClockView を AppearanceModel ベースに移行（@State 13 個 + onReceive 2 個を撤廃）"
```

**依存**: Task 4

---

## Task 6: SettingsView から 4 セクション分割（Opacity / Theme / ColorScheme / Material）

**Commit**: `refactor(ui): SettingsView から 4 セクション分割（Opacity / Theme / ColorScheme / Material）`

**目的**: SettingsView の最初の 4 セクションを `UI/Settings/<Topic>Section.swift` に分離。AppearanceModel 経由のバインドに移行。

**実装**:

新規 4 ファイル：
- `Sources/Toki/UI/Settings/OpacitySection.swift`
- `Sources/Toki/UI/Settings/ThemeColorSection.swift`
- `Sources/Toki/UI/Settings/ColorSchemeSection.swift`
- `Sources/Toki/UI/Settings/MaterialStrengthSection.swift`

各サブ View の型例（`OpacitySection.swift`）：

```swift
import SwiftUI

/// 透過率セクション（0.05〜1.0、5%〜100%）。
/// appearance.opacity に直接バインドし、didSet で SettingsStore に永続化される。
struct OpacitySection: View {
    @ObservedObject var appearance: AppearanceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("透過率")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(appearance.opacity * 100))%")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $appearance.opacity, in: 0.05...1.0)
        }
    }
}
```

`ThemeColorSection.swift` だけは少し複雑：
```swift
struct ThemeColorSection: View {
    @ObservedObject var appearance: AppearanceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("テーマカラー").font(.system(size: 12, weight: .medium))
                Spacer()
                if appearance.themeColor == .custom {
                    ColorPicker("", selection: $appearance.customThemeColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 32, height: 20)
                }
            }
            Picker("", selection: $appearance.themeColor) {
                ForEach(ThemeColor.allCases) { color in
                    HStack {
                        Circle()
                            .fill(color == .custom ? appearance.customThemeColor : color.color)
                            .frame(width: 10, height: 10)
                        Text(color.displayName)
                    }
                    .tag(color)
                }
            }
            .labelsHidden()
        }
    }
}
```

### `SettingsView.swift`（編集）

`opacitySection` / `themeColorSection` / `colorSchemeSection` / `materialSection` の computed property 4 つを削除、body 内のそれらの呼び出しを新規サブ View に置換：

```swift
var body: some View {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            OpacitySection(appearance: appearance)
            ThemeColorSection(appearance: appearance)
            ColorSchemeSection(appearance: appearance)
            MaterialStrengthSection(appearance: appearance)
            // 残り 7 セクションは旧 computed property のまま（Task 7-8 で分割）
            customBackgroundSection
            customTextColorSection
            textScaleSection
            ringThicknessSection
            handThicknessSection
            circleOutlineThicknessSection
            customCircleColorSection
        }
        .padding(20)
    }
    .frame(width: 340, height: 860)
    .tokiGlassBackground(cornerRadius: 12)
}
```

@State は本 task では残す（最終 task 8 で SettingsView コンテナ縮小時にすべて撤廃）。

**注意**: `SettingsView` が `AppearanceModel` を受け取るには signature 変更が必要：
```swift
struct SettingsView: View {
    @ObservedObject var appearance: AppearanceModel
    // 既存の @State は Task 8 で完全削除、本 task では 4 セクション分のみ削除
}
```

AppDelegate 側の `SettingsView()` 呼び出しも `SettingsView(appearance: appearance)` に変更。

**完了条件**:
```bash
# 4 サブ View 新規
ls Sources/Toki/UI/Settings/OpacitySection.swift Sources/Toki/UI/Settings/ThemeColorSection.swift Sources/Toki/UI/Settings/ColorSchemeSection.swift Sources/Toki/UI/Settings/MaterialStrengthSection.swift
# → 全て存在

# SettingsView から該当 4 section 削除（旧 computed property）
grep -c "private var opacitySection\|private var themeColorSection\|private var colorSchemeSection\|private var materialSection" Sources/Toki/UI/SettingsView.swift
# → 0 件

# SettingsView から 4 サブ View 呼び出し
grep -c "OpacitySection(appearance: appearance)\|ThemeColorSection(appearance: appearance)\|ColorSchemeSection(appearance: appearance)\|MaterialStrengthSection(appearance: appearance)" Sources/Toki/UI/SettingsView.swift
# → 4 件

# AppDelegate 側の signature 変更
grep -n "SettingsView(appearance:" Sources/Toki/App/AppDelegate.swift
# → 1 件

swift build && swift test
./scripts/build-app.sh
```

**コミット**:
```bash
git add Sources/Toki/UI/Settings/OpacitySection.swift \
        Sources/Toki/UI/Settings/ThemeColorSection.swift \
        Sources/Toki/UI/Settings/ColorSchemeSection.swift \
        Sources/Toki/UI/Settings/MaterialStrengthSection.swift \
        Sources/Toki/UI/SettingsView.swift \
        Sources/Toki/App/AppDelegate.swift
git commit -m "refactor(ui): SettingsView から 4 セクション分割（Opacity / Theme / ColorScheme / Material）"
```

**依存**: Task 5

---

## Task 7: SettingsView から 4 セクション分割（Background / Text / TextScale / Ring）

**Commit**: `refactor(ui): SettingsView から 4 セクション分割（Background / Text / TextScale / Ring）`

**目的**: 残り 7 セクションのうち 4 つを分離。

**実装**:

新規 4 ファイル：
- `Sources/Toki/UI/Settings/CustomBackgroundSection.swift`
- `Sources/Toki/UI/Settings/CustomTextColorSection.swift`
- `Sources/Toki/UI/Settings/TextScaleSection.swift`
- `Sources/Toki/UI/Settings/RingThicknessSection.swift`

各サブ View は Task 6 と同パターン（`@ObservedObject var appearance: AppearanceModel` + 既存ロジック移植）。Toggle 系は `Toggle(isOn: $appearance.useCustomBackground)` 等で直接バインド。

SettingsView から該当 4 section の computed property を削除、body 内でサブ View 呼び出し。

**完了条件**: Task 6 と同パターン、4 ファイル新規 + SettingsView 変更。

**コミット**: 同パターン。

**依存**: Task 6

---

## Task 8: SettingsView から残り 3 セクション分割 + コンテナ縮小

**Commit**: `refactor(ui): SettingsView から 3 セクション分割 + コンテナ View に縮小`

**目的**: 残り 3 セクションを分離し、SettingsView を ScrollView + サブ View 並び替えのみの簡素なコンテナに縮小。

**実装**:

新規 3 ファイル：
- `Sources/Toki/UI/Settings/HandThicknessSection.swift`
- `Sources/Toki/UI/Settings/CircleOutlineThicknessSection.swift`
- `Sources/Toki/UI/Settings/CustomCircleColorSection.swift`

`SettingsView.swift` を以下に縮小：

```swift
import SwiftUI

/// 設定パネル。サブ View を並べるだけのコンテナ。
/// AppDelegate が AppearanceModel を生成し、ClockView と共有して渡す。
struct SettingsView: View {
    @ObservedObject var appearance: AppearanceModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                OpacitySection(appearance: appearance)
                ThemeColorSection(appearance: appearance)
                ColorSchemeSection(appearance: appearance)
                MaterialStrengthSection(appearance: appearance)
                CustomBackgroundSection(appearance: appearance)
                CustomTextColorSection(appearance: appearance)
                TextScaleSection(appearance: appearance)
                RingThicknessSection(appearance: appearance)
                HandThicknessSection(appearance: appearance)
                CircleOutlineThicknessSection(appearance: appearance)
                CustomCircleColorSection(appearance: appearance)
            }
            .padding(20)
        }
        .frame(width: 340, height: 860)
        .tokiGlassBackground(cornerRadius: 12)
    }
}
```

全 @State / 全 computed property section / すべての `.onChange` ハンドラを削除。ファイル長 < 60 行を達成。

**完了条件**:
```bash
# 残り 3 サブ View 新規
ls Sources/Toki/UI/Settings/HandThicknessSection.swift Sources/Toki/UI/Settings/CircleOutlineThicknessSection.swift Sources/Toki/UI/Settings/CustomCircleColorSection.swift
# → 全て存在

# SettingsView は @State / computed property / .onChange なし
grep -c "@State private var" Sources/Toki/UI/SettingsView.swift
# → 0 件

grep -c "private var.*Section: some View" Sources/Toki/UI/SettingsView.swift
# → 0 件

grep -c "onChange" Sources/Toki/UI/SettingsView.swift
# → 0 件

# 11 サブ View 呼び出し
grep -c "Section(appearance: appearance)" Sources/Toki/UI/SettingsView.swift
# → 11 件

# ファイル長 < 60 行
wc -l Sources/Toki/UI/SettingsView.swift

swift build && swift test
./scripts/build-app.sh
```

**コミット**: 上記 grep を全て満たす状態で commit。

**依存**: Task 7

---

## Task 9: AppSettings.swift を削除

**Commit**: `refactor(composition): AppSettings.swift を削除`

**目的**: AppSettings.swift を完全削除。永続化は SettingsStore に、enum は AppearanceTokens に、ObservableObject は AppearanceModel に完全移行済み。

**コンテキスト**:
- Task 1〜8 で AppSettings.swift の全機能が他ファイルに移行済み
- 残るのは Notification.Name extension のみ → Task 10 で削除
- 削除前に `grep -r "AppSettings" Sources/` でゼロ件を確認

**実装**:

```bash
# 参照確認
grep -r "AppSettings" Sources/
# → 0 件（または Notification.Name extension の参照のみ）

# 削除
git rm Sources/Toki/Composition/AppSettings.swift
```

ただし、`Notification.Name` extension のみ別ファイルに残す必要がある場合は Task 9 では AppSettings.swift 全体を削除せず、enum / 永続化部分のみ削除 → Task 10 で extension も削除して `git rm` する手順を取る。

**簡略化**: Task 9 と 10 を 1 commit に統合する：

`refactor(composition): AppSettings.swift を削除し Notification.Name extension を撤廃`

これにより：
- AppSettings.swift 全体削除
- 関連 `.onReceive` 撤廃（Task 5 で既に削除済み）
- `NotificationCenter.default.post` 関連コード撤廃（Task 6-8 で既にサブ View から削除されている）

**完了条件**:
```bash
ls Sources/Toki/Composition/AppSettings.swift 2>&1
# → No such file

grep -rn "AppSettings" Sources/
# → 0 件

grep -rn "tokiOpacityChanged\|tokiAppearanceChanged" Sources/
# → 0 件

swift build && swift test
./scripts/build-app.sh
```

**コミット**:
```bash
git rm Sources/Toki/Composition/AppSettings.swift
git commit -m "refactor(composition): AppSettings.swift を削除し Notification.Name extension を撤廃"
```

**依存**: Task 5, 8

---

## Task 10: SPEC.md を spec 011 完了状態に追従更新

**Commit**: `docs(spec): SPEC.md を spec 011 完了状態に追従更新`

**目的**: SPEC.md §6 Phase 3 リファクタ候補から 11-1〜11-4 を「✅ 完了 spec 011」に更新。spec 009 H-7 / H-8 の副次解消も明記。

**実装**:

ファイル: `SPEC.md`（編集）

§6 Phase 3 リスト内の以下を「✅ 完了 spec 011」マーク：
- AppSettings の構造分割（H-1）
- AppearanceModel への移行（H-2）
- SettingsView の細分化（H-3）
- ThemeColor 循環依存解消（H-4）
- 円の色既定値集約（H-8、副次解消）
- `@MainActor` 付与（H-7、SettingsStore で適用）

**完了条件**:
```bash
grep -nE "spec 011" SPEC.md
# → 5 件以上

swift build && swift test
```

**コミット**:
```bash
git add SPEC.md
git commit -m "docs(spec): SPEC.md を spec 011 完了状態に追従更新"
```

**依存**: Task 9

---

## 全 task 完了後

### 回帰確認

- [ ] `swift test`：Domain 36 ケース全 pass
- [ ] `./scripts/build-app.sh && open .build/Toki.app`：実機目視で spec 011 §AC walkthrough

### 手動チェックリスト

| # | 項目 | 期待 |
|---|---|---|
| 1 | 全 15 設定軸の即時反映 | 既存挙動と同一 |
| 2 | アプリ再起動 | 全設定値が復元される |
| 3 | UserDefaults キー互換 | `defaults read com.<bundle>` で `toki.*` キーが従来通り |
| 4 | ホバーツールチップ | 無変更 |
| 5 | popover（円弧クリック）| 無変更 |
| 6 | OAuth 接続 / 切断 / 再読込 | 無変更 |
| 7 | ウィンドウリサイズ / 位置記憶 | 無変更 |
| 8 | focus reload | 無変更 |
| 9 | 「最終更新 X 分前」 | 無変更 |
| 10 | Liquid Glass / Material fallback | 無変更 |

### 残骸チェック

- [ ] `grep -r "AppSettings" Sources/` → 0 件
- [ ] `grep -r "tokiOpacityChanged\|tokiAppearanceChanged" Sources/` → 0 件
- [ ] `grep -r "NotificationCenter.*post" Sources/UI/Settings/` → 0 件

### ファイル構造確認

- [ ] `Sources/Toki/Composition/SettingsStore.swift` 存在
- [ ] `Sources/Toki/Composition/AppearanceModel.swift` 存在
- [ ] `Sources/Toki/UI/AppearanceTokens.swift` 存在
- [ ] `Sources/Toki/UI/Settings/` 配下に 11 ファイル
- [ ] `Sources/Toki/Composition/AppSettings.swift` 不在

### コードレビュー（任意）

`code-reviewer` agent で spec 011 全体レビュー。
