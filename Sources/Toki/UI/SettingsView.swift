import SwiftUI

/// 軽量設定 UI。AppDelegate が別 NSWindow で表示する。
/// 透過率 / テーマカラー（プリセット + カスタム）/ 背景色 / 文字色 / 配色 / 背景の濃さを調整可能。
/// spec 011 Task 6: 最初の 4 セクション（Opacity / Theme / ColorScheme / Material）を
/// `UI/Settings/<Topic>Section.swift` に分離し、AppearanceModel に直接バインド。
/// 残り 7 セクションは Task 7 / 8 で順次分割予定。
struct SettingsView: View {
    @ObservedObject var appearance: AppearanceModel

    @State private var useCustomBackground: Bool = AppSettings.shared.useCustomBackground
    @State private var customBackgroundColor: Color = AppSettings.shared.customBackgroundColor
    @State private var useCustomTextColor: Bool = AppSettings.shared.useCustomTextColor
    @State private var customTextColor: Color = AppSettings.shared.customTextColor
    @State private var textScale: TextScale = AppSettings.shared.textScale
    @State private var ringThickness: RingThickness = AppSettings.shared.ringThickness
    @State private var handThickness: HandThickness = AppSettings.shared.handThickness
    @State private var circleOutlineThickness: CircleOutlineThickness = AppSettings.shared.circleOutlineThickness
    @State private var useCustomCircleColor: Bool = AppSettings.shared.useCustomCircleColor
    @State private var customCircleColor: Color = AppSettings.shared.customCircleColor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                OpacitySection(appearance: appearance)
                ThemeColorSection(appearance: appearance)
                ColorSchemeSection(appearance: appearance)
                MaterialStrengthSection(appearance: appearance)
                customBackgroundSection
                customTextColorSection
                textScaleSection
                ringThicknessSection
                handThicknessSection
                circleOutlineThicknessSection
                customCircleColorSection
            }
            .padding(20)
        }
        .frame(width: 340, height: 860)
        .tokiGlassBackground(cornerRadius: 12)
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

    /// 文字サイズスケール（小 / 標準 / 大 / 特大）。
    private var textScaleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("文字サイズ")
                .font(.system(size: 12, weight: .medium))
            Picker("", selection: $textScale) {
                ForEach(TextScale.allCases) { scale in
                    Text(scale.displayName).tag(scale)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: textScale) { _, newValue in
                AppSettings.shared.textScale = newValue
                NotificationCenter.default.post(name: .tokiAppearanceChanged, object: nil)
            }
        }
    }

    /// リングの太さ（細 / 標準 / 太 / 極太）。
    private var ringThicknessSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("リングの太さ")
                .font(.system(size: 12, weight: .medium))
            Picker("", selection: $ringThickness) {
                ForEach(RingThickness.allCases) { thickness in
                    Text(thickness.displayName).tag(thickness)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: ringThickness) { _, newValue in
                AppSettings.shared.ringThickness = newValue
                NotificationCenter.default.post(name: .tokiAppearanceChanged, object: nil)
            }
        }
    }

    /// 針の太さ（細 / 標準 / 太 / 極太）。
    private var handThicknessSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("針の太さ")
                .font(.system(size: 12, weight: .medium))
            Picker("", selection: $handThickness) {
                ForEach(HandThickness.allCases) { thickness in
                    Text(thickness.displayName).tag(thickness)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: handThickness) { _, newValue in
                AppSettings.shared.handThickness = newValue
                NotificationCenter.default.post(name: .tokiAppearanceChanged, object: nil)
            }
        }
    }

    /// 円自体（時間トラック内縁の輪郭線）の太さ。
    private var circleOutlineThicknessSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("円の太さ")
                .font(.system(size: 12, weight: .medium))
            Picker("", selection: $circleOutlineThickness) {
                ForEach(CircleOutlineThickness.allCases) { thickness in
                    Text(thickness.displayName).tag(thickness)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: circleOutlineThickness) { _, newValue in
                AppSettings.shared.circleOutlineThickness = newValue
                NotificationCenter.default.post(name: .tokiAppearanceChanged, object: nil)
            }
        }
    }

    /// 円自体の色を任意色で上書きするセクション。
    /// Toggle OFF で既定の secondary 60%。
    private var customCircleColorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("円の色を上書き", isOn: $useCustomCircleColor)
                    .font(.system(size: 12, weight: .medium))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: useCustomCircleColor) { _, newValue in
                        AppSettings.shared.useCustomCircleColor = newValue
                        NotificationCenter.default.post(name: .tokiAppearanceChanged, object: nil)
                    }
                Spacer()
                ColorPicker("", selection: $customCircleColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 32, height: 20)
                    .disabled(!useCustomCircleColor)
                    .onChange(of: customCircleColor) { _, newValue in
                        AppSettings.shared.customCircleColor = newValue
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
