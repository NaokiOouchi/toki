import AppKit
import SwiftUI

/// メニューバー常駐と FloatingClockWindow の表示/非表示を司る AppDelegate。
/// ViewModel は Task 14 以降で接続予定。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: FloatingClockWindow?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 暫定のプレースホルダ View（Task 14 で ClockView に差し替え予定）
        let placeholder = Text("Toki")
            .frame(width: 280, height: 320)
            .background(Color(NSColor.windowBackgroundColor))

        let w = FloatingClockWindow.make(contentView: placeholder)
        window = w

        // 初回位置：メインスクリーンの右上 16px インセット
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let origin = NSPoint(
                x: visible.maxX - w.frame.width - 16,
                y: visible.maxY - w.frame.height - 16
            )
            w.setFrameOrigin(origin)
        }
        w.orderFrontRegardless()

        // メニューバーアイコン（SF Symbols の clock）
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "clock",
                                     accessibilityDescription: "Toki")
        item.button?.action = #selector(toggleWindow)
        item.button?.target = self
        statusItem = item
    }

    /// メニューバーアイコンクリックで呼ばれる。ウィンドウの表示/非表示をトグルする。
    @objc private func toggleWindow() {
        guard let w = window else { return }
        if w.isVisible {
            w.orderOut(nil)
        } else {
            w.orderFrontRegardless()
        }
    }
}
