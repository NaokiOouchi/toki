import AppKit
import SwiftUI

/// マウスホイール / トラックパッド scroll を受けて SwiftUI に渡す薄い NSViewRepresentable。
/// `scrollWheel(with:)` を override してデルタを onScroll callback で通知する。
/// spec 013：重なり event の cycle 操作に使用。
///
/// 実装上の注意：
/// - `hitTest(_:)` で nil を返すことで mouse click / hover gesture は下層 View（ClockFaceCanvas）に通す。
/// - scrollWheel は NSWindow.sendEvent の responder chain 経由で受信されるため、
///   hitTest nil でも届く想定（macOS 動作）。MVP 実装、駄目なら responder chain
///   明示転送に切替（spec 013 plan §5.1 fallback 案）。
struct ScrollCatcher: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ScrollHandlingView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ScrollHandlingView)?.onScroll = onScroll
    }

    private final class ScrollHandlingView: NSView {
        var onScroll: ((CGFloat) -> Void)?

        override func scrollWheel(with event: NSEvent) {
            let deltaY = event.scrollingDeltaY
            guard abs(deltaY) > 0 else { return }
            onScroll?(deltaY)
        }

        /// hitTest nil で下層 View に click / hover を通す。
        /// scrollWheel は NSWindow の responder chain 経由で届く。
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
