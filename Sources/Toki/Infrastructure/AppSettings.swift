import Foundation
import AppKit
import SwiftUI

/// UserDefaults wrapper for app-level settings (opacity / windowFrame / theme / material).
/// シングルトン的に `AppSettings.shared` でアクセス、struct 値型で内部状態を持たない。
/// 個別キーで UserDefaults に保存し、必要に応じて clamp / 検証する。
struct AppSettings {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let opacity = "toki.opacity"
        static let windowFrameX = "toki.windowFrame.x"
        static let windowFrameY = "toki.windowFrame.y"
        static let windowFrameW = "toki.windowFrame.w"
        static let windowFrameH = "toki.windowFrame.h"
        static let themeColor = "toki.themeColor"
        static let materialStrength = "toki.materialStrength"
        static let colorSchemeMode = "toki.colorSchemeMode"
        static let customColorR = "toki.customColor.r"
        static let customColorG = "toki.customColor.g"
        static let customColorB = "toki.customColor.b"
        static let useCustomBackground = "toki.useCustomBackground"
        static let customBackgroundR = "toki.customBackground.r"
        static let customBackgroundG = "toki.customBackground.g"
        static let customBackgroundB = "toki.customBackground.b"
        static let useCustomTextColor = "toki.useCustomTextColor"
        static let customTextR = "toki.customText.r"
        static let customTextG = "toki.customText.g"
        static let customTextB = "toki.customText.b"
        static let textScale = "toki.textScale"
        static let ringThickness = "toki.ringThickness"
        static let handThickness = "toki.handThickness"
        static let circleOutlineThickness = "toki.circleOutlineThickness"
    }

    /// ウィンドウ透過率（0.05〜1.0）。0.05 = ほぼ透明、1 = 完全不透明。
    /// 下限を 0.05 にすることで、極端な低 opacity で Liquid Glass がレンダリング
    /// 破綻したり、ウィンドウのドラッグハンドルを失う事象を回避する。
    /// 未設定（初回起動）は 1.0。
    var opacity: Double {
        get {
            guard defaults.object(forKey: Key.opacity) != nil else { return 1.0 }
            return max(0.05, min(1.0, defaults.double(forKey: Key.opacity)))
        }
        nonmutating set {
            defaults.set(max(0.05, min(1.0, newValue)), forKey: Key.opacity)
        }
    }

    /// ThemeColor.custom 選択時に使う任意色。SwiftUI Color を sRGB で 3 つの Double に分解保存。
    /// 未設定時は Indigo 相当のデフォルトを返す。
    var customThemeColor: Color {
        get { Self.readColor(defaults: defaults,
                             rKey: Key.customColorR, gKey: Key.customColorG, bKey: Key.customColorB,
                             default: .indigo) }
        nonmutating set { Self.writeColor(defaults: defaults, color: newValue,
                                          rKey: Key.customColorR, gKey: Key.customColorG, bKey: Key.customColorB) }
    }

    /// 背景色カスタム上書きを有効にするか。true なら customBackgroundColor を背景に使う。
    var useCustomBackground: Bool {
        get { defaults.bool(forKey: Key.useCustomBackground) }
        nonmutating set { defaults.set(newValue, forKey: Key.useCustomBackground) }
    }

    /// ウィンドウ背景の任意色。useCustomBackground == true のときに Liquid Glass / Material を上書き。
    var customBackgroundColor: Color {
        get { Self.readColor(defaults: defaults,
                             rKey: Key.customBackgroundR, gKey: Key.customBackgroundG, bKey: Key.customBackgroundB,
                             default: Color(red: 0.1, green: 0.1, blue: 0.15)) }
        nonmutating set { Self.writeColor(defaults: defaults, color: newValue,
                                          rKey: Key.customBackgroundR, gKey: Key.customBackgroundG, bKey: Key.customBackgroundB) }
    }

    /// 文字色カスタム上書きを有効にするか。true なら customTextColor を `.foregroundStyle` に適用。
    var useCustomTextColor: Bool {
        get { defaults.bool(forKey: Key.useCustomTextColor) }
        nonmutating set { defaults.set(newValue, forKey: Key.useCustomTextColor) }
    }

    /// 文字色の任意色。useCustomTextColor == true のときに primary 系の foregroundStyle を上書き。
    var customTextColor: Color {
        get { Self.readColor(defaults: defaults,
                             rKey: Key.customTextR, gKey: Key.customTextG, bKey: Key.customTextB,
                             default: .primary) }
        nonmutating set { Self.writeColor(defaults: defaults, color: newValue,
                                          rKey: Key.customTextR, gKey: Key.customTextG, bKey: Key.customTextB) }
    }

    /// 文字サイズスケール（小 / 標準 / 大 / 特大）。各 Text の font size に factor を掛ける。
    var textScale: TextScale {
        get {
            let raw = defaults.string(forKey: Key.textScale) ?? TextScale.regular.rawValue
            return TextScale(rawValue: raw) ?? .regular
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.textScale) }
    }

    /// リングの太さ（event 円弧の幅）。ClockGeometry の outerRadius - innerRadius を制御。
    var ringThickness: RingThickness {
        get {
            let raw = defaults.string(forKey: Key.ringThickness) ?? RingThickness.regular.rawValue
            return RingThickness(rawValue: raw) ?? .regular
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.ringThickness) }
    }

    /// 針の太さ（時計の針の lineWidth）。
    var handThickness: HandThickness {
        get {
            let raw = defaults.string(forKey: Key.handThickness) ?? HandThickness.regular.rawValue
            return HandThickness(rawValue: raw) ?? .regular
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.handThickness) }
    }

    /// 円自体（時間トラックの内縁を示すリング輪郭線）の太さ。
    var circleOutlineThickness: CircleOutlineThickness {
        get {
            let raw = defaults.string(forKey: Key.circleOutlineThickness) ?? CircleOutlineThickness.regular.rawValue
            return CircleOutlineThickness(rawValue: raw) ?? .regular
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.circleOutlineThickness) }
    }

    // MARK: - Color persistence helpers

    /// 3 キーの RGB Double を読んで SwiftUI Color に復元する。
    /// 未設定（r キーが存在しない）なら default を返す。
    private static func readColor(defaults: UserDefaults,
                                  rKey: String, gKey: String, bKey: String,
                                  default defaultColor: Color) -> Color {
        guard defaults.object(forKey: rKey) != nil else { return defaultColor }
        let r = defaults.double(forKey: rKey)
        let g = defaults.double(forKey: gKey)
        let b = defaults.double(forKey: bKey)
        return Color(red: r, green: g, blue: b)
    }

    /// SwiftUI Color を NSColor 経由で sRGB 成分に分解して 3 キーに保存する。
    private static func writeColor(defaults: UserDefaults, color: Color,
                                   rKey: String, gKey: String, bKey: String) {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .black
        defaults.set(Double(nsColor.redComponent), forKey: rKey)
        defaults.set(Double(nsColor.greenComponent), forKey: gKey)
        defaults.set(Double(nsColor.blueComponent), forKey: bKey)
    }

    /// 針 / 中心ドット / 現在 event アウトラインに使うテーマカラー。
    /// 未設定時はシステムアクセントカラー（System Settings の "強調色"）。
    var themeColor: ThemeColor {
        get {
            let raw = defaults.string(forKey: Key.themeColor) ?? ThemeColor.accent.rawValue
            return ThemeColor(rawValue: raw) ?? .accent
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Key.themeColor)
        }
    }

    /// ウィンドウ背景 material の濃さ。白背景上での視認性調整に使う。
    /// 未設定時は `.regular`。
    var materialStrength: MaterialStrength {
        get {
            let raw = defaults.string(forKey: Key.materialStrength) ?? MaterialStrength.regular.rawValue
            return MaterialStrength(rawValue: raw) ?? .regular
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Key.materialStrength)
        }
    }

    /// 配色モード。auto は macOS 外観設定に追従、light / dark は強制適用。
    /// 文字色 / 背景マテリアル / アイコン色が連動する SwiftUI の preferredColorScheme で実装。
    var colorSchemeMode: ColorSchemeMode {
        get {
            let raw = defaults.string(forKey: Key.colorSchemeMode) ?? ColorSchemeMode.auto.rawValue
            return ColorSchemeMode(rawValue: raw) ?? .auto
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Key.colorSchemeMode)
        }
    }

    /// 前回のウィンドウフレーム。x/y/w/h の 4 つのキーに分解して保存。
    /// いずれかが欠落していたら nil（初回起動扱い）。
    var windowFrame: NSRect? {
        guard defaults.object(forKey: Key.windowFrameX) != nil,
              defaults.object(forKey: Key.windowFrameY) != nil,
              defaults.object(forKey: Key.windowFrameW) != nil,
              defaults.object(forKey: Key.windowFrameH) != nil else {
            return nil
        }
        let x = defaults.double(forKey: Key.windowFrameX)
        let y = defaults.double(forKey: Key.windowFrameY)
        let w = defaults.double(forKey: Key.windowFrameW)
        let h = defaults.double(forKey: Key.windowFrameH)
        return NSRect(x: x, y: y, width: w, height: h)
    }

    func setWindowFrame(_ rect: NSRect) {
        defaults.set(rect.origin.x, forKey: Key.windowFrameX)
        defaults.set(rect.origin.y, forKey: Key.windowFrameY)
        defaults.set(rect.size.width, forKey: Key.windowFrameW)
        defaults.set(rect.size.height, forKey: Key.windowFrameH)
    }
}

/// テーマカラーのプリセット。針 / 中心ドット等に使う SwiftUI Color を提供。
/// `custom` の場合は AppSettings.shared.customThemeColor を返す。
enum ThemeColor: String, CaseIterable, Identifiable, Hashable {
    case accent, indigo, blue, cyan, teal, mint, green, yellow, orange, red, pink, purple, brown, gray, custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .accent: return "システム"
        case .indigo: return "インディゴ"
        case .blue: return "ブルー"
        case .cyan: return "シアン"
        case .teal: return "ティール"
        case .mint: return "ミント"
        case .green: return "グリーン"
        case .yellow: return "イエロー"
        case .orange: return "オレンジ"
        case .red: return "レッド"
        case .pink: return "ピンク"
        case .purple: return "パープル"
        case .brown: return "ブラウン"
        case .gray: return "グレー"
        case .custom: return "カスタム"
        }
    }

    var color: Color {
        switch self {
        case .accent: return .accentColor
        case .indigo: return .indigo
        case .blue: return .blue
        case .cyan: return .cyan
        case .teal: return .teal
        case .mint: return .mint
        case .green: return .green
        case .yellow: return .yellow
        case .orange: return .orange
        case .red: return .red
        case .pink: return .pink
        case .purple: return .purple
        case .brown: return .brown
        case .gray: return .gray
        case .custom: return AppSettings.shared.customThemeColor
        }
    }
}

/// 文字サイズスケール。各 Text の font size に factor を掛けて拡縮する。
enum TextScale: String, CaseIterable, Identifiable, Hashable {
    case small, regular, large, xLarge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small: return "小"
        case .regular: return "標準"
        case .large: return "大"
        case .xLarge: return "特大"
        }
    }

    var factor: CGFloat {
        switch self {
        case .small: return 0.85
        case .regular: return 1.0
        case .large: return 1.2
        case .xLarge: return 1.4
        }
    }
}

/// リングの太さ（event 円弧の幅）。`outerRadius - innerRadius = dim * factor`。
enum RingThickness: String, CaseIterable, Identifiable, Hashable {
    case thin, regular, thick, extraThick

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .thin: return "細"
        case .regular: return "標準"
        case .thick: return "太"
        case .extraThick: return "極太"
        }
    }

    /// dim（min(width, height)）に対する比率。standard=0.08（既存値）。
    var factor: CGFloat {
        switch self {
        case .thin: return 0.05
        case .regular: return 0.08
        case .thick: return 0.12
        case .extraThick: return 0.16
        }
    }
}

/// 円自体（時間トラック内縁を示すリング輪郭線）の太さ。
enum CircleOutlineThickness: String, CaseIterable, Identifiable, Hashable {
    case thin, regular, thick, extraThick

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .thin: return "細"
        case .regular: return "標準"
        case .thick: return "太"
        case .extraThick: return "極太"
        }
    }

    var lineWidth: CGFloat {
        switch self {
        case .thin: return 0.5
        case .regular: return 0.75
        case .thick: return 1.5
        case .extraThick: return 3.0
        }
    }
}

/// 針の太さ（lineWidth）。固定 pt で指定。
enum HandThickness: String, CaseIterable, Identifiable, Hashable {
    case thin, regular, thick, extraThick

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .thin: return "細"
        case .regular: return "標準"
        case .thick: return "太"
        case .extraThick: return "極太"
        }
    }

    var lineWidth: CGFloat {
        switch self {
        case .thin: return 1.0
        case .regular: return 1.5
        case .thick: return 2.5
        case .extraThick: return 4.0
        }
    }
}

/// 背景 material の濃さプリセット。白背景での視認性調整用。
enum MaterialStrength: String, CaseIterable, Identifiable, Hashable {
    case ultraThin, thin, regular, thick, ultraThick

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ultraThin: return "極薄"
        case .thin: return "薄め"
        case .regular: return "標準"
        case .thick: return "濃いめ"
        case .ultraThick: return "極濃"
        }
    }

    var swiftUIMaterial: Material {
        switch self {
        case .ultraThin: return .ultraThinMaterial
        case .thin: return .thinMaterial
        case .regular: return .regularMaterial
        case .thick: return .thickMaterial
        case .ultraThick: return .ultraThickMaterial
        }
    }
}

/// 配色モード（ライト / ダーク / 自動）プリセット。
/// SwiftUI の `.preferredColorScheme()` で実装し、文字色・背景マテリアル・
/// アイコン色を一括で切り替える。
enum ColorSchemeMode: String, CaseIterable, Identifiable, Hashable {
    case auto, light, dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "自動"
        case .light: return "ライト"
        case .dark: return "ダーク"
        }
    }

    /// SwiftUI の `.preferredColorScheme(_:)` に渡す値。
    /// auto は nil で「強制しない＝システム追従」を表現する。
    var swiftUIColorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

extension Notification.Name {
    /// 透過率設定が変更されたときに送出される通知。ClockView が購読して opacity 反映。
    static let tokiOpacityChanged = Notification.Name("toki.opacityChanged")
    /// テーマカラー / 背景マテリアル / 配色モード等の見た目設定が変更されたときの通知。
    static let tokiAppearanceChanged = Notification.Name("toki.appearanceChanged")
}
