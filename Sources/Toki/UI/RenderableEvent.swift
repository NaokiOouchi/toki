import Foundation
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
    /// イベントの開始時刻。繰り返しイベントを開く URL scheme で
    /// 発生日を指定するために保持する。
    let start: Date
    /// イベントの終了時刻。ツールチップで時刻範囲を表示するために保持する。
    let end: Date
    /// イベントが属するカレンダー名（Google の場合はメールアドレス）。
    /// Google event 詳細 URL の eid 生成に必要。
    let calendarTitle: String
    /// Google Calendar API で取得した event detail URL（htmlLink）。
    /// 非 Google event / API 取得失敗の場合は nil。
    /// クリック時は nil なら今日のビュー fallback。
    let webURL: URL?
}

extension RenderableEvent: Equatable {
    static func == (lhs: RenderableEvent, rhs: RenderableEvent) -> Bool {
        lhs.id == rhs.id
    }
}
