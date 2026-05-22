import SwiftUI

/// 軽量設定 UI。AppDelegate が別 NSWindow で表示する。
/// 透過率 / テーマカラー / 背景マテリアル濃度をユーザーが調整できる。
/// 各値は即時に AppSettings へ書き込み、NotificationCenter で View 側に通知する。
struct SettingsView: View {
    @State private var opacity: Double = AppSettings.shared.opacity
    @State private var themeColor: ThemeColor = AppSettings.shared.themeColor
    @State private var customThemeColor: Color = AppSettings.shared.customThemeColor
    @State private var materialStrength: MaterialStrength = AppSettings.shared.materialStrength
    @State private var colorSchemeMode: ColorSchemeMode = AppSettings.shared.colorSchemeMode

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 透過率セクション（0% 完全透明 〜 100% 完全不透明）
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("透過率")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(Int(opacity * 100))%")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $opacity, in: 0.0...1.0)
                    .onChange(of: opacity) { _, newValue in
                        AppSettings.shared.opacity = newValue
                        NotificationCenter.default.post(name: .tokiOpacityChanged, object: nil)
                    }
            }

            // テーマカラーセクション（プリセット + カスタム）
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("テーマカラー")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    // custom 選択時のみ ColorPicker を inline 表示
                    if themeColor == .custom {
                        ColorPicker("", selection: $customThemeColor, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 32, height: 20)
                            .onChange(of: customThemeColor) { _, newValue in
                                AppSettings.shared.customThemeColor = newValue
                                NotificationCenter.default.post(name: .tokiAppearanceChanged, object: nil)
                            }
                    }
                }
                Picker("", selection: $themeColor) {
                    ForEach(ThemeColor.allCases) { color in
                        HStack {
                            Circle()
                                .fill(color.color)
                                .frame(width: 10, height: 10)
                            Text(color.displayName)
                        }
                        .tag(color)
                    }
                }
                .labelsHidden()
                .onChange(of: themeColor) { _, newValue in
                    AppSettings.shared.themeColor = newValue
                    NotificationCenter.default.post(name: .tokiAppearanceChanged, object: nil)
                }
            }

            // 配色モードセクション（文字色 + 背景色を一括切替）
            VStack(alignment: .leading, spacing: 6) {
                Text("配色")
                    .font(.system(size: 12, weight: .medium))
                Picker("", selection: $colorSchemeMode) {
                    ForEach(ColorSchemeMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: colorSchemeMode) { _, newValue in
                    AppSettings.shared.colorSchemeMode = newValue
                    NotificationCenter.default.post(name: .tokiAppearanceChanged, object: nil)
                }
            }

            // 背景マテリアル濃度セクション（白背景での視認性調整）
            VStack(alignment: .leading, spacing: 6) {
                Text("背景の濃さ")
                    .font(.system(size: 12, weight: .medium))
                Picker("", selection: $materialStrength) {
                    ForEach(MaterialStrength.allCases) { strength in
                        Text(strength.displayName).tag(strength)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: materialStrength) { _, newValue in
                    AppSettings.shared.materialStrength = newValue
                    NotificationCenter.default.post(name: .tokiAppearanceChanged, object: nil)
                }
            }
        }
        .padding(20)
        .frame(width: 320, height: 340)
        // spec 008: Liquid Glass（macOS 26+）/ Material fallback
        .tokiGlassBackground(cornerRadius: 12)
    }
}
