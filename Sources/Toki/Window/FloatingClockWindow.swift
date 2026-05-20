import AppKit
import SwiftUI

/// 常時前面表示・全 Space 表示・ボーダーレスのフローティングウィンドウ。
/// テキスト入力がなく他アプリのフォーカスを奪わないよう、key window にならない。
final class FloatingClockWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// 指定の SwiftUI View をホストするウィンドウを生成する。
    static func make<Content: View>(contentView: Content) -> FloatingClockWindow {
        let window = FloatingClockWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 320),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: contentView)
        return window
    }
}
