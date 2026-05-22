import Foundation
import AppKit

/// UserDefaults wrapper for app-level settings (opacity / windowFrame).
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

extension Notification.Name {
    /// 透過率設定が変更されたときに送出される通知。ClockView が購読して opacity 反映。
    static let tokiOpacityChanged = Notification.Name("toki.opacityChanged")
}
