import CoreGraphics
import Foundation

/// UI 層 Value Object。ホバー中のイベントから組み立てる表示状態。
/// Equatable 準拠により @Published の同値時 no-op を可能にする（チラつき防止）。
struct TooltipState: Equatable {
    let startEndLabel: String   // "HH:MM - HH:MM"
    let title: String
    let position: CGPoint       // Canvas ローカル座標、ツールチップ左上の基準点
    /// 重なりグループ内の現 index / 総件数（spec 013 改修）。
    /// 例：3 件中の 2 件目 → "2/3"。重なりなしは nil。
    /// 円弧外側の badge `i/N` が tooltip に隠れて見えなくなる事象の補完。
    let cycleIndicator: String?

    init(startEndLabel: String, title: String, position: CGPoint, cycleIndicator: String? = nil) {
        self.startEndLabel = startEndLabel
        self.title = title
        self.position = position
        self.cycleIndicator = cycleIndicator
    }
}
