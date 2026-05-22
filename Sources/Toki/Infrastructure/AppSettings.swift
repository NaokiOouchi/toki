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
    }

    /// ウィンドウ透過率（0.5〜1.0）。未設定時は 1.0。
    var opacity: Double {
        get {
            let v = defaults.double(forKey: Key.opacity)
            return v == 0 ? 1.0 : max(0.5, min(1.0, v))
        }
        nonmutating set {
            defaults.set(max(0.5, min(1.0, newValue)), forKey: Key.opacity)
        }
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
enum ThemeColor: String, CaseIterable, Identifiable, Hashable {
    case accent, indigo, blue, teal, mint, green, yellow, orange, red, pink, purple, brown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .accent: return "システム"
        case .indigo: return "インディゴ"
        case .blue: return "ブルー"
        case .teal: return "ティール"
        case .mint: return "ミント"
        case .green: return "グリーン"
        case .yellow: return "イエロー"
        case .orange: return "オレンジ"
        case .red: return "レッド"
        case .pink: return "ピンク"
        case .purple: return "パープル"
        case .brown: return "ブラウン"
        }
    }

    var color: Color {
        switch self {
        case .accent: return .accentColor
        case .indigo: return .indigo
        case .blue: return .blue
        case .teal: return .teal
        case .mint: return .mint
        case .green: return .green
        case .yellow: return .yellow
        case .orange: return .orange
        case .red: return .red
        case .pink: return .pink
        case .purple: return .purple
        case .brown: return .brown
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
