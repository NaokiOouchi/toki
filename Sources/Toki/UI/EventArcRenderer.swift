import SwiftUI
import CoreGraphics

/// 中心と内外径と開始/終了角度から annulus segment の Path を組み立てる。
func annulusPath(center: CGPoint,
                 innerR: CGFloat,
                 outerR: CGFloat,
                 startAngle: Double,
                 endAngle: Double) -> Path {
    var path = Path()
    path.addArc(center: center, radius: outerR,
                startAngle: .radians(startAngle), endAngle: .radians(endAngle),
                clockwise: false)
    path.addArc(center: center, radius: innerR,
                startAngle: .radians(endAngle), endAngle: .radians(startAngle),
                clockwise: true)
    path.closeSubpath()
    return path
}

/// 1 件のイベント円弧を Canvas に描画する。
/// status に応じて alpha と current アウトラインを切り替える。
func drawEventArc(in ctx: inout GraphicsContext,
                  event: RenderableEvent,
                  geometry: ClockGeometry) {
    let path = annulusPath(
        center: geometry.center,
        innerR: geometry.innerRadius,
        outerR: geometry.outerRadius,
        startAngle: event.startAngle,
        endAngle: event.endAngle
    )
    let base = Color(cgColor: event.color)
    let alpha: Double = event.status == .past ? 0.3 : 1.0
    ctx.fill(path, with: .color(base.opacity(alpha)))
    if event.status == .current {
        ctx.stroke(path, with: .color(base.opacity(0.8)), lineWidth: 0.75)
    }
}

/// 指定位置が含まれる円弧を返す（クリックヒットテスト用）。
/// 該当なしは nil。複数該当時は最初に見つかったものを返す。
func hitTest(point: CGPoint,
             events: [RenderableEvent],
             geometry: ClockGeometry) -> RenderableEvent? {
    for event in events {
        let path = annulusPath(
            center: geometry.center,
            innerR: geometry.innerRadius,
            outerR: geometry.outerRadius,
            startAngle: event.startAngle,
            endAngle: event.endAngle
        )
        if path.contains(point) {
            return event
        }
    }
    return nil
}
