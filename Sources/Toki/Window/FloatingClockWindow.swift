import AppKit
import SwiftUI

/// 常時前面表示・全 Space 表示・ボーダーレスのフローティングウィンドウ。
/// テキスト入力がなく他アプリのフォーカスを奪わないよう、key window にならない。
/// spec 008: resizable 対応、min 220x260 / max 420x500。
final class FloatingClockWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// 指定の SwiftUI View をホストするウィンドウを生成する。
    static func make<Content: View>(contentView: Content) -> FloatingClockWindow {
        let window = FloatingClockWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 320),
            styleMask: [.borderless, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.contentMinSize = NSSize(width: 220, height: 260)
        window.contentMaxSize = NSSize(width: 420, height: 500)
        window.contentView = NSHostingView(rootView: contentView)
        return window
    }
}
