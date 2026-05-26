import SwiftUI

/// 透過率セクション（0.05〜1.0、5%〜100%）。
/// appearance.opacity に直接バインドし、didSet で SettingsStore に永続化される。
/// 旧 SettingsView の opacitySection（spec 008 由来、spec 011 で分離）。
struct OpacitySection: View {
    @ObservedObject var appearance: AppearanceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Opacity")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(appearance.opacity * 100))%")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $appearance.opacity, in: 0.05...1.0)
        }
    }
}
