import SwiftUI

/// 円自体（リング輪郭線）の太さ（細 / 標準 / 太 / 極太）。
struct CircleOutlineThicknessSection: View {
    @ObservedObject var appearance: AppearanceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("円の太さ")
                .font(.system(size: 12, weight: .medium))
            Picker("", selection: $appearance.circleOutlineThickness) {
                ForEach(CircleOutlineThickness.allCases) { thickness in
                    Text(thickness.displayName).tag(thickness)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}
