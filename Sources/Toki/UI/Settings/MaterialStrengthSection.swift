import SwiftUI

/// 背景マテリアル濃度（極薄〜極濃）。Liquid Glass / Material の濃度を制御。
struct MaterialStrengthSection: View {
    @ObservedObject var appearance: AppearanceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("背景の濃さ")
                .font(.system(size: 12, weight: .medium))
            Picker("", selection: $appearance.materialStrength) {
                ForEach(MaterialStrength.allCases) { strength in
                    Text(strength.displayName).tag(strength)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}
