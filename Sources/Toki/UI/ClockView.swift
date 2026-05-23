import AppKit
import SwiftUI

/// 円形時計型ウィンドウのルート View。
/// ClockViewModel と AppearanceModel を `@ObservedObject` で受け取り、
/// 描画に必要な派生 state を VM から、見た目関連の設定値を AppearanceModel から取得する。
/// spec 011 で @State 13 個 + onReceive 2 個を撤廃し、AppearanceModel ベースに移行。
struct ClockView: View {
    @ObservedObject var viewModel: ClockViewModel
    @ObservedObject var appearance: AppearanceModel

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
                        groups: viewModel.canvasGroups,
                        backgroundEvent: viewModel.canvasBackgroundEvent,
                        themeColor: appearance.resolvedThemeColor,
                        ringThickness: appearance.ringThickness.factor,
                        handLineWidth: appearance.handThickness.lineWidth,
                        textScale: appearance.textScale.factor,
                        circleOutlineLineWidth: appearance.circleOutlineThickness.lineWidth,
                        circleOutlineColor: appearance.resolvedCircleOutlineColor,
                        onTap: { point, geometry in
                            viewModel.handleArcTap(at: point, geometry: geometry)
                        },
                        onHover: { phase, geometry in
                            viewModel.handleHover(phase: phase, geometry: geometry)
                        }
                    )
                    // spec 013：scroll wheel は AppDelegate の NSEvent.addLocalMonitorForEvents
                    // で捕捉し ViewModel.handleScrollRaw に転送する（SwiftUI overlay 経由では
                    // scrollWheel が responder chain で届かないため、global monitor で対応）。
                    CurrentEventLabel(state: viewModel.centerState,
                                      textScale: appearance.textScale.factor)
                        .allowsHitTesting(false)  // 中央テキストが円弧クリックを奪わないようにする
                }

                Divider().frame(height: 0.5)

                NextEventLine(state: viewModel.nextLineState,
                              lastUpdatedText: viewModel.lastUpdatedFormatted,
                              textScale: appearance.textScale.factor)
                    .frame(height: 40)
            }

            // popover 表示中：透明 backdrop（外側クリックで close）+ popover 本体
            // spec 010: 円弧クリックで Meet / Calendar / 場所 / 参加者を in-app 表示
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
                    // Calendar ボタンは常時表示：webURL あり時は event detail、無ければ day view
                    hasCalendarURL: true,
                    textScale: appearance.textScale.factor,
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
                EventTooltip(timeLabel: tooltip.startEndLabel,
                             title: tooltip.title,
                             textScale: appearance.textScale.factor)
                    .offset(x: position.x, y: position.y)
                    .allowsHitTesting(false)
                    .transaction { $0.animation = nil }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            // ボーダーはテーマカラーで薄く着色して窓の輪郭を白背景でも分かりやすくする。
            RoundedRectangle(cornerRadius: 12)
                .stroke(appearance.resolvedThemeColor.opacity(0.5), lineWidth: 0.75)
        )
        // 文字色カスタム：primary を上書き。secondary/tertiary は影響しないが
        // 中央テキスト主タイトル等の主要表示は変更される。
        .foregroundStyle(appearance.useCustomTextColor ? appearance.customTextColor : .primary)
        // 配色モード：auto なら nil（システム追従）、light/dark なら強制
        .preferredColorScheme(appearance.colorSchemeMode.swiftUIColorScheme)
    }

    /// 背景レイヤー。優先順位：
    /// 1. useCustomBackground == true → 任意の単色背景（Liquid Glass / Material を上書き）
    /// 2. macOS 26+ → Liquid Glass + Material（MaterialStrength で濃度調整）
    /// 3. macOS 25 以下 → Material のみ
    /// いずれも `.opacity()` を最後にかけて透過率調整。
    @ViewBuilder
    private var glassBackgroundLayer: some View {
        if appearance.useCustomBackground {
            RoundedRectangle(cornerRadius: 12)
                .fill(appearance.customBackgroundColor)
                .opacity(appearance.opacity)
        } else if #available(macOS 26.0, *) {
            Rectangle()
                .fill(appearance.materialStrength.swiftUIMaterial)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                .opacity(appearance.opacity)
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(appearance.materialStrength.swiftUIMaterial)
                .opacity(appearance.opacity)
        }
    }
}

extension ClockView {
    /// ツールチップ想定サイズ。EventTooltip.maxWidth と 2 行時の実測高さに合わせる。
    private static let tooltipWidth: CGFloat = 200
    private static let tooltipHeight: CGFloat = 40
    private static let tooltipOffset: CGFloat = 8
    /// ウィンドウサイズ。ClockView.body の .frame と同じ値を使う。
    /// spec 013 候補（spec 010 H-010-1）：リサイズ対応のため動的サイズ化する（現状は固定値）。
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
    /// canvas / window サイズは tooltip 計算と同じ固定値を使う（spec 013 候補で動的化）。
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
