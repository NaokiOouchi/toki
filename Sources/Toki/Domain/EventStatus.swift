import Foundation

/// イベントの過去/現在/未来を表す。
enum EventStatus {
    case past
    case current
    case future
}

extension Event {
    /// 指定時刻 `now` 時点のイベント状態を返す。
    /// - `end <= now` → `.past`（終了済み）
    /// - `start > now` → `.future`
    /// - それ以外 → `.current`
    func status(at now: Date) -> EventStatus {
        if end <= now { return .past }
        if start > now { return .future }
        return .current
    }
}
