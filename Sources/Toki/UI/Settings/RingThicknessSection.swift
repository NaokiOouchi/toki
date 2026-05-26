import SwiftUI

/// リングの太さ（細 / 標準 / 太 / 極太）。
struct RingThicknessSection: View {
    @ObservedObject var appearance: AppearanceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ring thickness")
                .font(.system(size: 12, weight: .medium))
            Picker("", selection: $appearance.ringThickness) {
                ForEach(RingThickness.allCases) { thickness in
                    Text(thickness.displayName).tag(thickness)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}
