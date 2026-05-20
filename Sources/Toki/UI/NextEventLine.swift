import SwiftUI

/// 下部「次の予定」ラインの表示状態。nil で非表示。
struct NextLineState: Equatable {
    let timeHHMM: String
    let title: String
}

/// 時計の下に表示する「次  HH:MM タイトル」の 1 行 View。
/// state が nil なら透明な領域を表示し、レイアウト位置は維持する。
struct NextEventLine: View {
    let state: NextLineState?

    var body: some View {
        if let s = state {
            HStack {
                Text("次")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(s.timeHHMM) \(s.title)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 16)
        } else {
            Color.clear
        }
    }
}
