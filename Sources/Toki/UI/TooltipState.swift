import CoreGraphics
import Foundation

/// UI 層 Value Object。ホバー中のイベントから組み立てる表示状態。
/// Equatable 準拠により @Published の同値時 no-op を可能にする（チラつき防止）。
struct TooltipState: Equatable {
    let startEndLabel: String   // "HH:MM - HH:MM"
    let title: String
    let position: CGPoint       // Canvas ローカル座標、ツールチップ左上の基準点
}
