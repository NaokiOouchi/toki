import SwiftUI

/// 下部「終日」ラインの表示状態。nil で非表示。
/// spec 013 改修で追加：24h timed event のタイトルを表示する。
struct AllDayLineState: Equatable {
    let title: String
}

/// 時計の下に表示する「終日  タイトル」の 1 行 View。
/// NextEventLine と同じスタイル / 高さ / フォントで揃え、
/// BottomInfoArea の collapsible UI で priority に応じて表示される。
/// 右端には「最終更新 X 分前」を NextEventLine と同様に表示できる。
struct AllDayEventLine: View {
    let state: AllDayLineState?
    let lastUpdatedText: String?
    var textScale: CGFloat = 1.0

    var body: some View {
        if state != nil || lastUpdatedText != nil {
            HStack {
                if let s = state {
                    Text("All-day")
                        .font(.system(size: 11 * textScale))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(s.title)
                        .font(.system(size: 11 * textScale))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
}
