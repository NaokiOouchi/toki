import SwiftUI

/// 円自体の色を任意色で上書きするセクション。
/// Toggle ON で circleOutlineColor を上書き、OFF で `.secondary.opacity(0.6)` 既定。
struct CustomCircleColorSection: View {
    @ObservedObject var appearance: AppearanceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("円の色を上書き", isOn: $appearance.useCustomCircleColor)
                    .font(.system(size: 12, weight: .medium))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                ColorPicker("", selection: $appearance.customCircleColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 32, height: 20)
                    .disabled(!appearance.useCustomCircleColor)
            }
        }
    }
}
