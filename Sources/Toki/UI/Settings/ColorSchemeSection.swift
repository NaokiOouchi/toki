import SwiftUI

/// 配色モード（自動 / ライト / ダーク）。`.preferredColorScheme()` 経由で適用される。
struct ColorSchemeSection: View {
    @ObservedObject var appearance: AppearanceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Appearance")
                .font(.system(size: 12, weight: .medium))
            Picker("", selection: $appearance.colorSchemeMode) {
                ForEach(ColorSchemeMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .labelsHidden()
        }
    }
}
