import Foundation

/// 24 時間時計上の時刻を表す Value Object。
/// 0:00 が真上 (-π/2)、12:00 が真下 (+π/2)、時計回り進行。
struct TimeOfDay: Equatable, Comparable, Hashable {
    let hour: Int
    let minute: Int

    init?(hour: Int, minute: Int) {
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }

    var minutesSinceMidnight: Int { hour * 60 + minute }

    /// 24 時間時計上の角度（ラジアン）。0:00 が真上 (-π/2)、時計回り。
    var clockAngle: Double {
        let fraction = Double(minutesSinceMidnight) / (24 * 60)
        return fraction * 2 * .pi - .pi / 2
    }

    static func now(calendar: Calendar = .current) -> TimeOfDay {
        from(date: Date(), calendar: calendar)
    }

    static func from(date: Date, calendar: Calendar = .current) -> TimeOfDay {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
            ?? TimeOfDay(hour: 0, minute: 0)!
    }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}
