import AppKit
import SwiftUI

/// 常時前面表示・全 Space 表示・ボーダーレスのフローティングウィンドウ。
/// テキスト入力がなく他アプリのフォーカスを奪わないよう、key window にならない。
/// spec 008: resizable 対応、min 220x260 / max 420x500。
final class FloatingClockWindow: NSWindow, NSWindowDelegate {
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
        // borderless window では NSWindow.contentMinSize が drag resize に効かない
        // macOS の挙動回避のため、self を delegate に設定して windowWillResize で
        // proposed size をリアルタイムにクランプする。
        window.delegate = window
        return window
    }

    /// 時計領域（正方形）の下に必要な固定 UI 領域の高さ。
    /// ClockView の VStack 構成：
    ///   - ZStack(clock).frame(height: width)  ← 正方形
    ///   - Color.clear.frame(height: 4)        ← gap
    ///   - Divider().frame(height: 0.5)         ← 0.5pt
    ///   - BottomInfoArea                       ← ~32pt (collapsed)
    /// 合計 約 36.5pt、margin 込みで 40pt を確保。
    private static let clockBottomReservedHeight: CGFloat = 40

    /// drag resize 中の毎フレーム呼ばれる。Toki の本質は「正方形時計 + 固定 Bottom」のため
    /// aspect 固定で制約：height = width + clockBottomReservedHeight。
    /// width を変えると height が自動連動、height だけ動かすことはできない（縦長は意味なし）。
    /// なお hover による window 拡張は handleBottomHover の animator().setFrame で行うため
    /// この delegate は呼ばれない（drag resize のみで発火）。
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let minSize = contentMinSize
        let maxSize = contentMaxSize
        // width を min / max でクランプ
        let clampedW = min(max(frameSize.width, minSize.width), maxSize.width)
        // height は width に連動（aspect 固定）
        let requiredHeight = clampedW + Self.clockBottomReservedHeight
        return NSSize(width: clampedW, height: requiredHeight)
    }
}
