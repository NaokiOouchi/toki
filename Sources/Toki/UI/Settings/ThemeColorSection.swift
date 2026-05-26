import SwiftUI

/// テーマカラーセクション（14 プリセット + カスタム）。
/// 針 / 中心ドット / ボーダーに反映される。`.custom` 選択時のみ ColorPicker を inline 表示。
struct ThemeColorSection: View {
    @ObservedObject var appearance: AppearanceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Theme color")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if appearance.themeColor == .custom {
                    ColorPicker("", selection: $appearance.customThemeColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 32, height: 20)
                }
            }
            Picker("", selection: $appearance.themeColor) {
                ForEach(ThemeColor.allCases) { color in
                    HStack {
                        Circle()
                            .fill(color == .custom ? appearance.customThemeColor : color.color)
                            .frame(width: 10, height: 10)
                        Text(color.displayName)
                    }
                    .tag(color)
                }
            }
            .labelsHidden()
        }
    }
}
