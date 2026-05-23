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
    /// イベントの開始時刻。繰り返しイベントを開く URL scheme で
    /// 発生日を指定するために保持する。
    let start: Date
    /// イベントの終了時刻。ツールチップで時刻範囲を表示するために保持する。
    let end: Date
    /// Google Calendar API で取得した event detail URL（htmlLink）。
    /// API 取得失敗の場合は nil。
    /// クリック時は nil なら今日のビュー fallback。
    let webURL: URL?
    /// 場所文字列（spec 010 で追加、popover 表示に使用）。
    let location: String?
    /// description（spec 010 で追加、popover 表示に使用）。Domain Event.note と対応。
    let note: String?
    /// 参加者リスト（spec 010 で追加、popover 表示に使用）。空配列許容。
    let attendees: [Attendee]
    /// Meet URL（spec 010 で追加、popover の「Meet で開く」ボタンで使用）。
    let meetURL: URL?
}

extension RenderableEvent: Equatable {
    static func == (lhs: RenderableEvent, rhs: RenderableEvent) -> Bool {
        lhs.id == rhs.id
    }
}

/// 重なりグループ表示単位（spec 013 で導入）。
/// ClockFaceCanvas が描画、ClockViewModel.canvasGroups が Domain OverlapGroup から生成。
/// `current` は今表示中の event、`next` は peek 表示用の次 event、
/// `extraCount` は badge `+N` 表示用の追加件数。
struct RenderableOverlapGroup: Identifiable, Equatable {
    let id: String                // = OverlapGroup.id
    let current: RenderableEvent  // 現在表示中
    let next: RenderableEvent?    // peek 用、重なりなし（count == 1）は nil
    let extraCount: Int           // 重なり追加件数 = max(0, count - 1)
}
