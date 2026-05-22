import SwiftUI

/// 文字色を任意色で上書きするセクション。
/// `.foregroundStyle()` を root に適用するため主要テキスト（primary 系）に効く。
/// secondary / tertiary はシステム既定のまま。
struct CustomTextColorSection: View {
    @ObservedObject var appearance: AppearanceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("文字色を上書き", isOn: $appearance.useCustomTextColor)
                    .font(.system(size: 12, weight: .medium))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                ColorPicker("", selection: $appearance.customTextColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 32, height: 20)
                    .disabled(!appearance.useCustomTextColor)
            }
        }
    }
}
