import CoreGraphics

/// 時計盤の幾何情報。中心点と内外径を保持する Value Object。
struct ClockGeometry {
    let center: CGPoint
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    /// 与えられたサイズに対する標準ジオメトリ（内径 85 / 外径 105）。
    /// 280x280 canvas でも 12% 程度の余白が外側にできるよう、
    /// 円の外径をやや小さく取って中央テキストとの視覚的バランスを取る。
    static func standard(in size: CGSize) -> ClockGeometry {
        ClockGeometry(
            center: CGPoint(x: size.width / 2, y: size.height / 2),
            innerRadius: 85,
            outerRadius: 105
        )
    }
}
