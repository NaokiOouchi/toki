import SwiftUI

/// 時計盤の Canvas 描画。0:00 真上、時計回り、24 時間表示。
/// 描画順：リング輪郭 → 時刻マーク → イベント円弧（past→future→current）→ 中心ドット → 針。
struct ClockFaceCanvas: View {
    /// 現在時刻に対応する針の角度（ラジアン）。
    /// 角度変換は ViewModel 側で `calendar` を考慮して行うため、
    /// View は計算済みの値を受け取るだけにする。
    let nowAngle: Double
    let events: [RenderableEvent]
    /// 円弧クリック時に呼ばれる。位置は Canvas のローカル座標、geometry は描画時と同じ前提。
    var onTap: ((CGPoint, ClockGeometry) -> Void)? = nil

    var body: some View {
        Canvas { ctx, size in
            let geometry = ClockGeometry.standard(in: size)
            drawRingOutlines(in: &ctx, geometry: geometry)
            drawHourMarks(in: &ctx, geometry: geometry)
            drawEventArcs(in: &ctx, geometry: geometry)
            drawHand(in: &ctx, geometry: geometry, angle: nowAngle)
            drawCenterDot(in: &ctx, geometry: geometry)
        }
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture(coordinateSpace: .local)
                .onEnded { value in
                    // ClockView 側で 280x280 固定 frame を当てている前提で size を直書きする（MVP 妥協）。
                    let geometry = ClockGeometry.standard(in: CGSize(width: 280, height: 280))
                    onTap?(value.location, geometry)
                }
        )
    }

    /// 内側リング輪郭線。時間トラックの内縁を示す。
    /// 外側はイベント円弧の外端で示唆されるため描画しない。
    private func drawRingOutlines(in ctx: inout GraphicsContext, geometry: ClockGeometry) {
        let inner = Path(ellipseIn: CGRect(
            x: geometry.center.x - geometry.innerRadius,
            y: geometry.center.y - geometry.innerRadius,
            width: geometry.innerRadius * 2,
            height: geometry.innerRadius * 2
        ))
        ctx.stroke(inner, with: .color(.secondary.opacity(0.6)), lineWidth: 0.75)
    }

    /// 針の根元にある小さなドット。
    private func drawCenterDot(in ctx: inout GraphicsContext, geometry: ClockGeometry) {
        let dotRadius: CGFloat = 2.5
        let rect = CGRect(
            x: geometry.center.x - dotRadius,
            y: geometry.center.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        )
        ctx.fill(Path(ellipseIn: rect), with: .color(.primary))
    }

    /// 0 / 6 / 12 / 18 の時刻マークをリングの内側に描く。
    /// 外周の外側に置くと 280pt の canvas 端でテキストが見切れるため内側配置にする。
    private func drawHourMarks(in ctx: inout GraphicsContext, geometry: ClockGeometry) {
        let labels: [(hour: Int, text: String)] = [
            (0, "0"), (6, "6"), (12, "12"), (18, "18")
        ]
        let labelRadius = geometry.innerRadius - 12
        for label in labels {
            guard let tod = TimeOfDay(hour: label.hour, minute: 0) else { continue }
            let angle = tod.clockAngle
            let position = CGPoint(
                x: geometry.center.x + CGFloat(cos(angle)) * labelRadius,
                y: geometry.center.y + CGFloat(sin(angle)) * labelRadius
            )
            let text = Text(label.text)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            ctx.draw(text, at: position, anchor: .center)
        }
    }

    /// イベント円弧を描画する。current のアウトラインが最上位に来るよう描画順を制御する。
    private func drawEventArcs(in ctx: inout GraphicsContext, geometry: ClockGeometry) {
        let sorted = events.sorted { Self.drawOrder($0.status) < Self.drawOrder($1.status) }
        for event in sorted {
            drawEventArc(in: &ctx, event: event, geometry: geometry)
        }
    }

    /// past → future → current の順で描画するための優先度。
    private static func drawOrder(_ status: EventStatus) -> Int {
        switch status {
        case .past: return 0
        case .future: return 1
        case .current: return 2
        }
    }

    /// 現在時刻を指す針を中心から外径まで描く。
    /// 角度計算は呼び出し側（ViewModel）で行い、View はラジアン値を受け取るだけ。
    private func drawHand(in ctx: inout GraphicsContext, geometry: ClockGeometry, angle: Double) {
        let endPoint = CGPoint(
            x: geometry.center.x + CGFloat(cos(angle)) * geometry.outerRadius,
            y: geometry.center.y + CGFloat(sin(angle)) * geometry.outerRadius
        )
        var path = Path()
        path.move(to: geometry.center)
        path.addLine(to: endPoint)
        ctx.stroke(path, with: .color(.primary), lineWidth: 1.5)
    }
}
