import SwiftUI

/// ホバー中のイベント詳細を 2 行で表示する小さなオーバーレイ。
/// 純粋な presentation View（時刻整形やヒットテストは ViewModel 側）。
struct EventTooltip: View {
    let timeLabel: String   // "14:00 - 15:00"
    let title: String
    /// 重なりグループ内の現 index / 総件数（spec 013 改修）。
    /// 例：3 件中の 2 件目 → "2/3"。重なりなしは nil で非表示。
    /// 円弧外側の badge `i/N` が tooltip に隠れて見えなくなる事象の補完。
    var cycleIndicator: String? = nil
    var textScale: CGFloat = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(timeLabel)
                    .font(.system(size: 11 * textScale))
                    .foregroundStyle(.secondary)
                if let cycle = cycleIndicator {
                    Text(cycle)
                        .font(.system(size: 10 * textScale))
                        .foregroundStyle(.tertiary)
                }
            }
            Text(title)
                .font(.system(size: 12 * textScale, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 200, alignment: .leading)
        // spec 008: Liquid Glass（macOS 26+）/ Material fallback
        .tokiGlassBackground(cornerRadius: 6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
    }
}
