import AppKit
import SwiftUI

/// 円形時計型ウィンドウのルート View。
/// Task 14 時点では呼び出し側がハードコードデータを渡す。
/// Task 16 で ClockViewModel を介した接続に差し替える予定。
struct ClockView: View {
    let events: [RenderableEvent]
    let now: Date
    let centerState: CenterState
    let nextLineState: NextLineState?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ClockFaceCanvas(now: now, events: events)
                CurrentEventLabel(state: centerState)
            }
            .frame(width: 280, height: 280)

            Divider().frame(height: 0.5)

            NextEventLine(state: nextLineState)
                .frame(height: 40)
        }
        .frame(width: 280, height: 320)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
        )
    }
}
