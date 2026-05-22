import SwiftUI

/// 軽量設定 UI。AppDelegate が別 NSWindow で表示する。
/// 透過率 / テーマカラー（プリセット + カスタム）/ 背景色 / 文字色 / 配色 / 背景の濃さを調整可能。
/// 各値は即時に AppSettings へ書き込み、NotificationCenter で View 側に通知する。
struct SettingsView: View {
    @State private var opacity: Double = AppSettings.shared.opacity
    @State private var themeColor: ThemeColor = AppSettings.shared.themeColor
    @State private var customThemeColor: Color = AppSettings.shared.customThemeColor
    @State private var materialStrength: MaterialStrength = AppSettings.shared.materialStrength
    @State private var colorSchemeMode: ColorSchemeMode = AppSettings.shared.colorSchemeMode
    @State private var useCustomBackground: Bool = AppSettings.shared.useCustomBackground
    @State private var customBackgroundColor: Color = AppSettings.shared.customBackgroundColor
    @State private var useCustomTextColor: Bool = AppSettings.shared.useCustomTextColor
    @State private var customTextColor: Color = AppSettings.shared.customTextColor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                opacitySection
                themeColorSection
                colorSchemeSection
                materialSection
                customBackgroundSection
                customTextColorSection
            }
            .padding(20)
        }
        .frame(width: 340, height: 520)
        .tokiGlassBackground(cornerRadius: 12)
    }

    /// 透過率セクション（0% = ほぼ透明、100% = 完全不透明）。
    private var opacitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("透過率")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(opacity * 100))%")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $opacity, in: 0.05...1.0)
                .onChange(of: opacity) { _, newValue in
                    AppSettings.shared.opacity = newValue
                    NotificationCenter.default.post(name: .tokiOpacityChanged, object: nil)
                }
        }
    }

    /// テーマカラーセクション（プリセット + カスタム）。
    /// `.custom` 選択時は ColorPicker を inline 表示。
    private var themeColorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("テーマカラー")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
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
                            .fill(color == .custom ? customThemeColor : color.color)
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
    }

    /// 配色モード（auto / light / dark）。
    private var colorSchemeSection: some View {
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
    }

    /// 背景マテリアル濃度。
    private var materialSection: some View {
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

    /// 背景色を任意色で上書きするセクション。
    /// Toggle ON で Liquid Glass / Material を replace、OFF で元に戻る。
    private var customBackgroundSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("背景色を上書き", isOn: $useCustomBackground)
                    .font(.system(size: 12, weight: .medium))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: useCustomBackground) { _, newValue in
                        AppSettings.shared.useCustomBackground = newValue
                        NotificationCenter.default.post(name: .tokiAppearanceChanged, object: nil)
                    }
                Spacer()
                ColorPicker("", selection: $customBackgroundColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 32, height: 20)
                    .disabled(!useCustomBackground)
                    .onChange(of: customBackgroundColor) { _, newValue in
                        AppSettings.shared.customBackgroundColor = newValue
                        NotificationCenter.default.post(name: .tokiAppearanceChanged, object: nil)
                    }
            }
        }
    }

    /// 文字色を任意色で上書きするセクション。
    /// `.foregroundStyle()` を root に適用するため主要テキスト（primary 系）に効く。
    /// secondary / tertiary はシステム既定のまま。
    private var customTextColorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("文字色を上書き", isOn: $useCustomTextColor)
                    .font(.system(size: 12, weight: .medium))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: useCustomTextColor) { _, newValue in
                        AppSettings.shared.useCustomTextColor = newValue
                        NotificationCenter.default.post(name: .tokiAppearanceChanged, object: nil)
                    }
                Spacer()
                ColorPicker("", selection: $customTextColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 32, height: 20)
                    .disabled(!useCustomTextColor)
                    .onChange(of: customTextColor) { _, newValue in
                        AppSettings.shared.customTextColor = newValue
                        NotificationCenter.default.post(name: .tokiAppearanceChanged, object: nil)
                    }
            }
        }
    }
}
