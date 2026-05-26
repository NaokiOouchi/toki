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
    /// spec 029: 色変更（colorId 反映）も再描画 trigger になるよう、id に加えて color も比較。
    /// status / 時刻角度は時計進行で別経路 update されるので id + color のみで十分。
    static func == (lhs: RenderableEvent, rhs: RenderableEvent) -> Bool {
        lhs.id == rhs.id && CFEqual(lhs.color, rhs.color)
    }
}

/// 重なりグループ表示単位（spec 013 で導入、改修で peek を廃止し合成弧 + i/N badge に変更）。
/// ClockFaceCanvas が描画、ClockViewModel.canvasGroups が Domain OverlapGroup から生成。
/// `current` は今表示中の event、`currentIndex`/`totalCount` は badge "i/N" 表示用、
/// `groupStartAngle`/`groupEndAngle` は重なり範囲を背景に薄色描画する合成弧用。
struct RenderableOverlapGroup: Identifiable, Equatable {
    let id: String                  // = OverlapGroup.id
    let current: RenderableEvent    // 現在表示中
    /// 1-based の現 index（表示用、scroll で 1→2→3→1→...）。
    let currentIndex: Int
    /// グループの総件数。badge は totalCount > 1 のときだけ "i/N" を表示。
    let totalCount: Int
    /// グループ内全 event の最早 start を時計角度に変換した値（合成弧の開始）。
    let groupStartAngle: Double
    /// グループ内全 event の最遅 end を時計角度に変換した値（合成弧の終了）。
    let groupEndAngle: Double
}
