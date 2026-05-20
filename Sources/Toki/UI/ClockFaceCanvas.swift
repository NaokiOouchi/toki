import SwiftUI

/// 時計盤の Canvas 描画。0:00 真上、時計回り、24 時間表示。
/// Task 12 でイベント円弧、Task 14 で events 引数が追加される予定。
struct ClockFaceCanvas: View {
    let now: Date

    var body: some View {
        Canvas { ctx, size in
            let geometry = ClockGeometry.standard(in: size)
            drawHourMarks(in: &ctx, geometry: geometry)
            drawHand(in: &ctx, geometry: geometry, now: now)
        }
    }

    /// 0 / 6 / 12 / 18 の時刻マークを外周に描く。
    private func drawHourMarks(in ctx: inout GraphicsContext, geometry: ClockGeometry) {
        let labels: [(hour: Int, text: String)] = [
            (0, "0"), (6, "6"), (12, "12"), (18, "18")
        ]
        let labelRadius = geometry.outerRadius + 10
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

    /// 現在時刻を指す針を中心から外径まで描く。
    private func drawHand(in ctx: inout GraphicsContext, geometry: ClockGeometry, now: Date) {
        let tod = TimeOfDay.from(date: now)
        let angle = tod.clockAngle
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
