import SwiftUI

/// 軽量設定 UI。AppDelegate が別 NSWindow で表示する。
/// 透過率 / テーマカラー（プリセット + カスタム）/ 背景色 / 文字色 / 配色 / 背景の濃さを調整可能。
/// spec 011 Task 6: 最初の 4 セクション（Opacity / Theme / ColorScheme / Material）を分離。
/// spec 011 Task 7: さらに 4 セクション（CustomBackground / CustomTextColor / TextScale / RingThickness）を分離。
/// 残り 3 セクション（hand / circleOutline / customCircle）は Task 8 で分割予定。
struct SettingsView: View {
    @ObservedObject var appearance: AppearanceModel

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
                CustomBackgroundSection(appearance: appearance)
                CustomTextColorSection(appearance: appearance)
                TextScaleSection(appearance: appearance)
                RingThicknessSection(appearance: appearance)
                handThicknessSection
                circleOutlineThicknessSection
                customCircleColorSection
            }
            .padding(20)
        }
        .frame(width: 340, height: 860)
        .tokiGlassBackground(cornerRadius: 12)
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
}
