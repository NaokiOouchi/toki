import AppKit
import SwiftUI

/// 円形時計型ウィンドウのルート View。
/// ClockViewModel を `@ObservedObject` で受け取り、描画に必要な派生 state を
/// （nowAngle / canvasEvents / centerState / nextLineState / hoveredTooltip）
/// VM から直接取得する。
struct ClockView: View {
    @ObservedObject var viewModel: ClockViewModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ZStack {
                    ClockFaceCanvas(
                        nowAngle: viewModel.nowAngle,
                        events: viewModel.canvasEvents,
                        onTap: { point, geometry in
                            viewModel.handleArcTap(at: point, geometry: geometry)
                        },
                        onHover: { phase, geometry in
                            viewModel.handleHover(phase: phase, geometry: geometry)
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

            // ツールチップ最前面オーバーレイ
            // spec §Non-goals「アニメーション無し」のため transaction で animation を抑制
            if let tooltip = viewModel.hoveredTooltip {
                EventTooltip(timeLabel: tooltip.startEndLabel, title: tooltip.title)
                    .offset(x: tooltip.position.x + 8, y: tooltip.position.y + 8)
                    .allowsHitTesting(false)
                    .transaction { $0.animation = nil }
            }
        }
        .frame(width: 280, height: 320)
    }
}
