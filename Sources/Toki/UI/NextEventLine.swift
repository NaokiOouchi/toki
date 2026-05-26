import SwiftUI

/// 下部「次の予定」ラインの表示状態。nil で非表示。
/// dateLabel は spec 012 で追加：今日の event なら nil、明日以降なら
/// "明日" / "明後日" / "土曜" / "5/26 (月)" のような賢いラベル。
struct NextLineState: Equatable {
    let timeHHMM: String
    let title: String
    let dateLabel: String?

    init(timeHHMM: String, title: String, dateLabel: String? = nil) {
        self.timeHHMM = timeHHMM
        self.title = title
        self.dateLabel = dateLabel
    }
}

/// 時計の下に表示する「次  HH:MM タイトル」の 1 行 View。
/// state が nil なら透明な領域を表示し、レイアウト位置は維持する。
/// spec 008: 右端に「最終更新 X 分前」を控えめに表示する。
/// state が nil でも lastUpdatedText があれば右端表示用に HStack で描画する。
/// spec 012: dateLabel があれば「明日 14:00 タイトル」のように時刻の前に prefix。
struct NextEventLine: View {
    let state: NextLineState?
    let lastUpdatedText: String?
    var textScale: CGFloat = 1.0

    var body: some View {
        if state != nil || lastUpdatedText != nil {
            HStack {
                if let s = state {
                    Text("Next")
                        .font(.system(size: 11 * textScale))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(displayText(s))
                        .font(.system(size: 11 * textScale))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                } else {
                    Spacer()
                }
                if let text = lastUpdatedText {
                    Text(text)
                        .font(.system(size: 9 * textScale))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
        } else {
            Color.clear
        }
    }

    /// dateLabel があれば時刻の前に prefix、なければ既存通り。
    /// spec 012 で導入、1 行レイアウト維持のため文字列結合で完結させる。
    private func displayText(_ s: NextLineState) -> String {
        if let label = s.dateLabel {
            return "\(label) \(s.timeHHMM) \(s.title)"
        }
        return "\(s.timeHHMM) \(s.title)"
    }
}
