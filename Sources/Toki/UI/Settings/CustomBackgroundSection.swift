import SwiftUI

/// 背景色を任意色で上書きするセクション。
/// Toggle ON で Liquid Glass / Material を replace、OFF で元に戻る。
/// 旧 SettingsView の customBackgroundSection（spec 009 由来、spec 011 で分離）。
struct CustomBackgroundSection: View {
    @ObservedObject var appearance: AppearanceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("背景色を上書き", isOn: $appearance.useCustomBackground)
                    .font(.system(size: 12, weight: .medium))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                ColorPicker("", selection: $appearance.customBackgroundColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 32, height: 20)
                    .disabled(!appearance.useCustomBackground)
            }
        }
    }
}
