import AppKit
import SwiftUI

/// 全ての UI 設定値を集約する ObservableObject。
/// 各 @Published の didSet で SettingsStore に永続化する。
/// AppDelegate が単一インスタンスを生成し、ClockView と SettingsView に @ObservedObject で渡す。
/// spec 011 で導入。spec 009 H-2 / H-4 を解消、H-7 / H-8 を副次解消。
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
        // backing storage 直接代入で didSet を回避（init 中の冗長な書き戻し防止）。
        // Apple 標準パターン：`self._xxx = Published(initialValue: ...)`
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

    // MARK: - Resolved values

    /// テーマカラーの解決済み Color。`.custom` のときは customThemeColor を返す。
    /// ClockView 等はこれを使い、enum 値を直接 `.color` 経由で評価しない。
    /// spec 011 H-4（ThemeColor 循環依存）の正規解決源。
    var resolvedThemeColor: Color {
        themeColor == .custom ? customThemeColor : themeColor.color
    }

    /// 円自体の輪郭色の解決済み Color。useCustomCircleColor で分岐。
    /// spec 011 で `.secondary.opacity(0.6)` の既定リテラル分散（spec 009 H-8）を副次解消。
    var resolvedCircleOutlineColor: Color {
        useCustomCircleColor ? customCircleColor : .secondary.opacity(0.6)
    }
}
