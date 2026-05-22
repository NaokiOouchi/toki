import AppKit
import SwiftUI

/// 円形時計型ウィンドウのルート View。
/// ClockViewModel を `@ObservedObject` で受け取り、描画に必要な派生 state を
/// （nowAngle / canvasEvents / centerState / nextLineState / hoveredTooltip）
/// VM から直接取得する。
struct ClockView: View {
    @ObservedObject var viewModel: ClockViewModel
    @State private var opacity: Double = AppSettings.shared.opacity
    @State private var themeColor: ThemeColor = AppSettings.shared.themeColor
    @State private var materialStrength: MaterialStrength = AppSettings.shared.materialStrength
    @State private var colorSchemeMode: ColorSchemeMode = AppSettings.shared.colorSchemeMode

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 背景レイヤー（spec 008）：opacity で調整可。
            // 別レイヤーに分離することで、上に重なるコンテンツ（時計 / テキスト）
            // が透過設定の影響を受けないようにする。
            glassBackgroundLayer

            // 前景コンテンツ（時計 / テキスト）：常時 100% 表示
            VStack(spacing: 0) {
                ZStack {
                    ClockFaceCanvas(
                        nowAngle: viewModel.nowAngle,
                        events: viewModel.canvasEvents,
                        themeColor: themeColor.color,
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

                Divider().frame(height: 0.5)

                NextEventLine(state: viewModel.nextLineState,
                              lastUpdatedText: viewModel.lastUpdatedFormatted)
                    .frame(height: 40)
            }

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
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            // ボーダーはテーマカラーで薄く着色して窓の輪郭を白背景でも分かりやすくする。
            RoundedRectangle(cornerRadius: 12)
                .stroke(themeColor.color.opacity(0.5), lineWidth: 0.75)
        )
        // 配色モード：auto なら nil（システム追従）、light/dark なら強制
        .preferredColorScheme(colorSchemeMode.swiftUIColorScheme)
        .onReceive(NotificationCenter.default.publisher(for: .tokiOpacityChanged)) { _ in
            opacity = AppSettings.shared.opacity
        }
        .onReceive(NotificationCenter.default.publisher(for: .tokiAppearanceChanged)) { _ in
            themeColor = AppSettings.shared.themeColor
            materialStrength = AppSettings.shared.materialStrength
            colorSchemeMode = AppSettings.shared.colorSchemeMode
        }
    }

    /// 背景レイヤー。macOS 26+ なら Liquid Glass、それ未満は AppSettings の MaterialStrength を反映。
    /// `.opacity()` で透過率を調整できるよう独立 View として切り出す。
    @ViewBuilder
    private var glassBackgroundLayer: some View {
        if #available(macOS 26.0, *) {
            // Liquid Glass を主に、material 濃度を背景 fill の thickness で追加調整。
            Rectangle()
                .fill(materialStrength.swiftUIMaterial)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                .opacity(opacity)
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(materialStrength.swiftUIMaterial)
                .opacity(opacity)
        }
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
