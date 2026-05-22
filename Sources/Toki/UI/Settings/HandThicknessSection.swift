import SwiftUI

/// 針の太さ（細 / 標準 / 太 / 極太）。drawHand の lineWidth を制御。
struct HandThicknessSection: View {
    @ObservedObject var appearance: AppearanceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("針の太さ")
                .font(.system(size: 12, weight: .medium))
            Picker("", selection: $appearance.handThickness) {
                ForEach(HandThickness.allCases) { thickness in
                    Text(thickness.displayName).tag(thickness)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}
