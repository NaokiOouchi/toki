import AppKit
import SwiftUI

/// 円形時計型ウィンドウのルート View。
/// ClockViewModel を `@ObservedObject` で受け取り、描画に必要な派生 state を
/// （nowAngle / canvasEvents / centerState / nextLineState / hoveredTooltip）
/// VM から直接取得する。
struct ClockView: View {
    @ObservedObject var viewModel: ClockViewModel
    @State private var opacity: Double = AppSettings.shared.opacity
    // resolved Color を保持する（enum のままだと .custom 内の色変化を検知できないため）
    @State private var themeColorValue: Color = AppSettings.shared.themeColor.color
    @State private var materialStrength: MaterialStrength = AppSettings.shared.materialStrength
    @State private var colorSchemeMode: ColorSchemeMode = AppSettings.shared.colorSchemeMode
    @State private var useCustomBackground: Bool = AppSettings.shared.useCustomBackground
    @State private var customBackgroundColor: Color = AppSettings.shared.customBackgroundColor
    @State private var useCustomTextColor: Bool = AppSettings.shared.useCustomTextColor
    @State private var customTextColor: Color = AppSettings.shared.customTextColor
    @State private var textScale: TextScale = AppSettings.shared.textScale
    @State private var ringThickness: RingThickness = AppSettings.shared.ringThickness
    @State private var handThickness: HandThickness = AppSettings.shared.handThickness
    @State private var circleOutlineThickness: CircleOutlineThickness = AppSettings.shared.circleOutlineThickness
    @State private var useCustomCircleColor: Bool = AppSettings.shared.useCustomCircleColor
    @State private var customCircleColor: Color = AppSettings.shared.customCircleColor

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
                        themeColor: themeColorValue,
                        ringThickness: ringThickness.factor,
                        handLineWidth: handThickness.lineWidth,
                        textScale: textScale.factor,
                        circleOutlineLineWidth: circleOutlineThickness.lineWidth,
                        circleOutlineColor: useCustomCircleColor ? customCircleColor : .secondary.opacity(0.6),
                        onTap: { point, geometry in
                            viewModel.handleArcTap(at: point, geometry: geometry)
                        },
                        onHover: { phase, geometry in
                            viewModel.handleHover(phase: phase, geometry: geometry)
                        }
                    )
                    CurrentEventLabel(state: viewModel.centerState, textScale: textScale.factor)
                        .allowsHitTesting(false)  // 中央テキストが円弧クリックを奪わないようにする
                }

                Divider().frame(height: 0.5)

                NextEventLine(state: viewModel.nextLineState,
                              lastUpdatedText: viewModel.lastUpdatedFormatted,
                              textScale: textScale.factor)
                    .frame(height: 40)
            }

            // popover 表示中：透明 backdrop（外側クリックで close）+ popover 本体
            // spec 010: 円弧クリックで Meet / Calendar / 場所 / 参加者を in-app 表示
            // 位置決めは Task 11 で対応するため、本 Task では中央寄せの仮配置とする。
            if let preview = viewModel.previewedEvent {
                // 透明 backdrop。allowsHitTesting(true) で外側クリックを拾う。
                // ZStack 内では先に描画されるものが背面、後ろが手前なので popover の前に置く。
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.closePreview() }

                // popover 本体。内部のボタン（Meet / Calendar / ×）クリックが効くよう
                // allowsHitTesting はデフォルト（true）のまま。
                // 位置は lastTapLocation を起点に X/Y 独立反転で画面端を回避。
                let tap = viewModel.lastTapLocation
                    ?? CGPoint(x: Self.canvasWidth / 2, y: Self.canvasWidth / 2)
                let pos = Self.popoverDisplayPosition(for: tap)
                EventPreviewPopover(
                    timeLabel: viewModel.previewTimeLabel ?? "",
                    title: preview.title,
                    location: preview.location,
                    attendees: preview.attendees,
                    note: preview.note,
                    hasMeetURL: preview.meetURL != nil,
                    hasCalendarURL: preview.webURL != nil,
                    textScale: textScale.factor,
                    onOpenMeet: { viewModel.openMeet() },
                    onOpenCalendar: { viewModel.openCalendarURL() },
                    onClose: { viewModel.closePreview() }
                )
                .offset(x: pos.x, y: pos.y)
                .transaction { $0.animation = nil }
            }

            // ツールチップ最前面オーバーレイ
            // 想定サイズで右端/下端を検知し、X/Y 軸独立に位置を反転する。
            // spec §Non-goals「アニメーション無し」のため transaction で animation を抑制
            if let tooltip = viewModel.hoveredTooltip {
                let position = Self.tooltipDisplayPosition(for: tooltip.position)
                EventTooltip(timeLabel: tooltip.startEndLabel, title: tooltip.title, textScale: textScale.factor)
                    .offset(x: position.x, y: position.y)
                    .allowsHitTesting(false)
                    .transaction { $0.animation = nil }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            // ボーダーはテーマカラーで薄く着色して窓の輪郭を白背景でも分かりやすくする。
            RoundedRectangle(cornerRadius: 12)
                .stroke(themeColorValue.opacity(0.5), lineWidth: 0.75)
        )
        // 文字色カスタム：primary を上書き。secondary/tertiary は影響しないが
        // 中央テキスト主タイトル等の主要表示は変更される。
        .foregroundStyle(useCustomTextColor ? customTextColor : .primary)
        // 配色モード：auto なら nil（システム追従）、light/dark なら強制
        .preferredColorScheme(colorSchemeMode.swiftUIColorScheme)
        .onReceive(NotificationCenter.default.publisher(for: .tokiOpacityChanged)) { _ in
            opacity = AppSettings.shared.opacity
        }
        .onReceive(NotificationCenter.default.publisher(for: .tokiAppearanceChanged)) { _ in
            // resolved Color を毎回 AppSettings から取り直して再描画させる。
            // enum 値が `.custom` のままで色だけ変わるケースにも対応。
            themeColorValue = AppSettings.shared.themeColor.color
            materialStrength = AppSettings.shared.materialStrength
            colorSchemeMode = AppSettings.shared.colorSchemeMode
            useCustomBackground = AppSettings.shared.useCustomBackground
            customBackgroundColor = AppSettings.shared.customBackgroundColor
            useCustomTextColor = AppSettings.shared.useCustomTextColor
            customTextColor = AppSettings.shared.customTextColor
            textScale = AppSettings.shared.textScale
            ringThickness = AppSettings.shared.ringThickness
            handThickness = AppSettings.shared.handThickness
            circleOutlineThickness = AppSettings.shared.circleOutlineThickness
            useCustomCircleColor = AppSettings.shared.useCustomCircleColor
            customCircleColor = AppSettings.shared.customCircleColor
        }
    }

    /// 背景レイヤー。優先順位：
    /// 1. useCustomBackground == true → 任意の単色背景（Liquid Glass / Material を上書き）
    /// 2. macOS 26+ → Liquid Glass + Material（MaterialStrength で濃度調整）
    /// 3. macOS 25 以下 → Material のみ
    /// いずれも `.opacity()` を最後にかけて透過率調整。
    @ViewBuilder
    private var glassBackgroundLayer: some View {
        if useCustomBackground {
            RoundedRectangle(cornerRadius: 12)
                .fill(customBackgroundColor)
                .opacity(opacity)
        } else if #available(macOS 26.0, *) {
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
    /// spec 011 候補：リサイズ対応のため動的サイズ化する（現状は固定値）。
    private static let canvasWidth: CGFloat = 280
    private static let windowHeight: CGFloat = 320

    /// popover 想定サイズ（最大値）。EventPreviewPopover の maxWidth と一般的な高さに合わせる。
    /// spec 010 で追加。位置計算は tooltipDisplayPosition と同じ流儀（X/Y 独立反転）。
    private static let popoverWidth: CGFloat = 280
    private static let popoverHeight: CGFloat = 280
    private static let popoverOffset: CGFloat = 8

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

    /// クリック位置から popover を描画する左上座標を計算する。
    /// tooltip と同じ流儀：X/Y 独立に判定、右端/下端を超える側だけ反転、左/上端は 0 にクランプ。
    /// canvas / window サイズは tooltip 計算と同じ固定値を使う（spec 011 で動的化候補）。
    static func popoverDisplayPosition(for tap: CGPoint) -> CGPoint {
        let x: CGFloat = (tap.x + popoverOffset + popoverWidth > canvasWidth)
            ? max(0, tap.x - popoverOffset - popoverWidth)
            : tap.x + popoverOffset
        let y: CGFloat = (tap.y + popoverOffset + popoverHeight > windowHeight)
            ? max(0, tap.y - popoverOffset - popoverHeight)
            : tap.y + popoverOffset
        return CGPoint(x: x, y: y)
    }
}
