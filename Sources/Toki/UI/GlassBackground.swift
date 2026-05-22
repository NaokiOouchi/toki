import SwiftUI

extension View {
    /// 軽量な glass / material 背景を適用する。
    /// macOS 26 (Tahoe) 以降では Liquid Glass の `.glassEffect()` を使い、
    /// それ未満では `.regularMaterial` で fallback する。
    /// material → clipShape → overlay(stroke) の合成順序を保ち、視覚回帰を防ぐ。
    @ViewBuilder
    func tokiGlassBackground(cornerRadius: CGFloat = 12) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}
