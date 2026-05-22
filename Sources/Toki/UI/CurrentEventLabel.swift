import SwiftUI

/// 中央 3 行テキストの表示状態。
/// ViewModel が組み立て、View は dumb に表示するだけ。
enum CenterState: Equatable {
    case duringEvent(time: String, title: String, remaining: String)
    case freeTime(time: String, subtitle: String)
}

/// 時計中央に表示する 3 行のテキスト View。
/// `textScale` で全体の font size を拡縮できる（spec 008 拡張）。
struct CurrentEventLabel: View {
    let state: CenterState
    var textScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 2) {
            switch state {
            case .duringEvent(let time, let title, let remaining):
                Text(time)
                    .font(.system(size: 11 * textScale))
                    .foregroundStyle(.tertiary)
                Text(title)
                    .font(.system(size: 15 * textScale, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(remaining)
                    .font(.system(size: 11 * textScale))
                    .foregroundStyle(.tertiary)
            case .freeTime(let time, let subtitle):
                Text(time)
                    .font(.system(size: 11 * textScale))
                    .foregroundStyle(.tertiary)
                Text("—")
                    .font(.system(size: 15 * textScale, weight: .medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 11 * textScale))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
