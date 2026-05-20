import AppKit

// AppKit ライフサイクルで起動するエントリポイント。
// SwiftUI App プロトコルは使わず、AppDelegate に委譲する。
@main
enum TokiApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Dock 非表示の二重ガード（Info.plist の LSUIElement と合わせて）
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
