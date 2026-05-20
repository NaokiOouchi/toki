import CoreGraphics

/// 時計盤の幾何情報。中心点と内外径を保持する Value Object。
struct ClockGeometry {
    let center: CGPoint
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    /// 与えられたサイズに対する標準ジオメトリ（内径 110 / 外径 130）。
    static func standard(in size: CGSize) -> ClockGeometry {
        ClockGeometry(
            center: CGPoint(x: size.width / 2, y: size.height / 2),
            innerRadius: 110,
            outerRadius: 130
        )
    }
}
