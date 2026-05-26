import AppKit
import SwiftUI

// MARK: - ThemeColor

/// テーマカラーのプリセット。針 / 中心ドット / ボーダーに使う SwiftUI Color を提供。
/// `.custom` の解決済み Color は AppearanceModel.resolvedThemeColor 経由で得る前提のため、
/// `.custom` ケースの `color` プロパティは `.accentColor` フォールバックを返す
/// （クラッシュ回避 + AppSettings.shared への循環参照解消、spec 011 H-4）。
enum ThemeColor: String, CaseIterable, Identifiable, Hashable {
    case accent, indigo, blue, cyan, teal, mint, green, yellow, orange, red, pink, purple, brown, gray, custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .accent: return String(localized: "System")
        case .indigo: return String(localized: "Indigo")
        case .blue: return String(localized: "Blue")
        case .cyan: return String(localized: "Cyan")
        case .teal: return String(localized: "Teal")
        case .mint: return String(localized: "Mint")
        case .green: return String(localized: "Green")
        case .yellow: return String(localized: "Yellow")
        case .orange: return String(localized: "Orange")
        case .red: return String(localized: "Red")
        case .pink: return String(localized: "Pink")
        case .purple: return String(localized: "Purple")
        case .brown: return String(localized: "Brown")
        case .gray: return String(localized: "Gray")
        case .custom: return String(localized: "Custom")
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
        case .custom: return .accentColor
        }
    }
}

// MARK: - MaterialStrength

/// 背景 material の濃さプリセット。白背景での視認性調整用。
/// 英訳は「透過度」概念で表現（Thin/Thick だと Thickness 系 enum と衝突するため）。
enum MaterialStrength: String, CaseIterable, Identifiable, Hashable {
    case ultraThin, thin, regular, thick, ultraThick

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ultraThin: return String(localized: "Most translucent")
        case .thin: return String(localized: "More translucent")
        case .regular: return String(localized: "Translucent")
        case .thick: return String(localized: "More opaque")
        case .ultraThick: return String(localized: "Most opaque")
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

// MARK: - ColorSchemeMode

/// 配色モード（ライト / ダーク / 自動）プリセット。
/// SwiftUI の `.preferredColorScheme()` で実装し、文字色・背景マテリアル・
/// アイコン色を一括で切り替える。
enum ColorSchemeMode: String, CaseIterable, Identifiable, Hashable {
    case auto, light, dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return String(localized: "Auto")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
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

// MARK: - TextScale

/// 文字サイズスケール。各 Text の font size に factor を掛けて拡縮する。
enum TextScale: String, CaseIterable, Identifiable, Hashable {
    case small, regular, large, xLarge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small: return String(localized: "Small")
        case .regular: return String(localized: "Regular")
        case .large: return String(localized: "Large")
        case .xLarge: return String(localized: "Extra Large")
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

// MARK: - RingThickness

/// リングの太さ（event 円弧の幅）。`outerRadius - innerRadius = dim * factor`。
enum RingThickness: String, CaseIterable, Identifiable, Hashable {
    case thin, regular, thick, extraThick

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .thin: return String(localized: "Thin")
        case .regular: return String(localized: "Regular")
        case .thick: return String(localized: "Thick")
        case .extraThick: return String(localized: "Extra Thick")
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

// MARK: - HandThickness

/// 針の太さ（lineWidth）。固定 pt で指定。
enum HandThickness: String, CaseIterable, Identifiable, Hashable {
    case thin, regular, thick, extraThick

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .thin: return String(localized: "Thin")
        case .regular: return String(localized: "Regular")
        case .thick: return String(localized: "Thick")
        case .extraThick: return String(localized: "Extra Thick")
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

// MARK: - CircleOutlineThickness

/// 円自体（時間トラック内縁を示すリング輪郭線）の太さ。
enum CircleOutlineThickness: String, CaseIterable, Identifiable, Hashable {
    case thin, regular, thick, extraThick

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .thin: return String(localized: "Thin")
        case .regular: return String(localized: "Regular")
        case .thick: return String(localized: "Thick")
        case .extraThick: return String(localized: "Extra Thick")
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
