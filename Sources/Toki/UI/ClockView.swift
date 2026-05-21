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
            // 想定サイズで右端/下端を検知し、X/Y 軸独立に位置を反転する。
            // spec §Non-goals「アニメーション無し」のため transaction で animation を抑制
            if let tooltip = viewModel.hoveredTooltip {
                let position = Self.tooltipDisplayPosition(for: tooltip.position)
                EventTooltip(timeLabel: tooltip.startEndLabel, title: tooltip.title)
                    .offset(x: position.x, y: position.y)
                    .allowsHitTesting(false)
                    .transaction { $0.animation = nil }
            }
        }
        .frame(width: 280, height: 320)
    }
}

extension ClockView {
    /// ツールチップ想定サイズ。EventTooltip.maxWidth と 2 行時の実測高さに合わせる。
    private static let tooltipWidth: CGFloat = 200
    private static let tooltipHeight: CGFloat = 40
    private static let tooltipOffset: CGFloat = 8
    /// ウィンドウサイズ。ClockView.body の .frame と同じ値を使う。
    private static let canvasWidth: CGFloat = 280
    private static let windowHeight: CGFloat = 320

    /// ホバー位置からツールチップを描画する左上座標を計算する。
    /// X/Y 軸独立に判定：右端/下端を超える側だけ反転、左/上端は 0 にクランプ。
    static func tooltipDisplayPosition(for hover: CGPoint) -> CGPoint {
        let x: CGFloat = (hover.x + tooltipOffset + tooltipWidth > canvasWidth)
            ? max(0, hover.x - tooltipOffset - tooltipWidth)
            : hover.x + tooltipOffset
        let y: CGFloat = (hover.y + tooltipOffset + tooltipHeight > windowHeight)
            ? max(0, hover.y - tooltipOffset - tooltipHeight)
            : hover.y + tooltipOffset
        return CGPoint(x: x, y: y)
    }
}
