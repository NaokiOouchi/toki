import CoreGraphics

/// UI 描画用のイベント表示モデル。
/// ViewModel が Domain Event から角度に変換してこの型を組み立てる。
struct RenderableEvent: Identifiable {
    let id: String
    let title: String
    let startAngle: Double  // ラジアン、TimeOfDay.clockAngle と同じ規約
    let endAngle: Double
    let color: CGColor
    let status: EventStatus
    let externalIdentifier: String?
}

extension RenderableEvent: Equatable {
    static func == (lhs: RenderableEvent, rhs: RenderableEvent) -> Bool {
        lhs.id == rhs.id
    }
}
