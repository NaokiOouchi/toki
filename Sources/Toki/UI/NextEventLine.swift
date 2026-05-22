import SwiftUI

/// 下部「次の予定」ラインの表示状態。nil で非表示。
struct NextLineState: Equatable {
    let timeHHMM: String
    let title: String
}

/// 時計の下に表示する「次  HH:MM タイトル」の 1 行 View。
/// state が nil なら透明な領域を表示し、レイアウト位置は維持する。
/// spec 008: 右端に「最終更新 X 分前」を控えめに表示する。
/// state が nil でも lastUpdatedText があれば右端表示用に HStack で描画する。
struct NextEventLine: View {
    let state: NextLineState?
    let lastUpdatedText: String?

    var body: some View {
        if state != nil || lastUpdatedText != nil {
            HStack {
                if let s = state {
                    Text("次")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(s.timeHHMM) \(s.title)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                } else {
                    Spacer()
                }
                if let text = lastUpdatedText {
                    Text(text)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
        } else {
            Color.clear
        }
    }
}
