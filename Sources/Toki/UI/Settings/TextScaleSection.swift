import SwiftUI

/// 文字サイズスケール（小 / 標準 / 大 / 特大）。
struct TextScaleSection: View {
    @ObservedObject var appearance: AppearanceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Text size")
                .font(.system(size: 12, weight: .medium))
            Picker("", selection: $appearance.textScale) {
                ForEach(TextScale.allCases) { scale in
                    Text(scale.displayName).tag(scale)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}
