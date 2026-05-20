import AppKit
import SwiftUI

/// 円形時計型ウィンドウのルート View。
/// ClockViewModel を `@ObservedObject` で受け取り、描画に必要な派生 state を
/// （now / canvasEvents / centerState / nextLineState）VM から直接取得する。
struct ClockView: View {
    @ObservedObject var viewModel: ClockViewModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ClockFaceCanvas(
                    nowAngle: viewModel.nowAngle,
                    events: viewModel.canvasEvents,
                    onTap: { point, geometry in
                        viewModel.handleArcTap(at: point, geometry: geometry)
                    }
                )
                CurrentEventLabel(state: viewModel.centerState)
                    .allowsHitTesting(false)  // 中央テキストが円弧クリックを奪わないようにする
            }
            .frame(width: 280, height: 280)

            Divider().frame(height: 0.5)

            NextEventLine(state: viewModel.nextLineState)
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
