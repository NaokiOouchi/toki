import CoreGraphics

/// 時計盤の幾何情報。中心点と内外径を保持する Value Object。
struct ClockGeometry {
    let center: CGPoint
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    /// 与えられたサイズに対するジオメトリ。
    /// spec 008: 動的サイズ対応のため min(w,h) の比率で innerRadius / outerRadius を算出。
    /// 280 canvas で inner ≈ 84 / outer ≈ 106（既存値とほぼ同等で視覚回帰なし）。
    /// `ringThickness` は (outerRadius - innerRadius) の比率（dim に対する係数）。
    static func standard(in size: CGSize, ringThickness: CGFloat = 0.08) -> ClockGeometry {
        let dim = min(size.width, size.height)
        let inner = dim * 0.30
        let outer = inner + dim * ringThickness
        return ClockGeometry(
            center: CGPoint(x: size.width / 2, y: size.height / 2),
            innerRadius: inner,
            outerRadius: outer
        )
    }
}
