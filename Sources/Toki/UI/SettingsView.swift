import SwiftUI

/// 設定パネルのコンテナ View。
/// 各 UI 設定軸は `UI/Settings/<Topic>Section.swift` のサブ View に分割され、
/// 本 View は ScrollView 内に並び替えるだけのシンプルな構造。
/// AppDelegate が AppearanceModel を生成し、ClockView と共有して渡す。
/// 旧 SettingsView は 292 行に @State 15 個 + 11 セクション + 変更監視ボイラープレートが
/// 集約されていたが、spec 011 で 11 サブ View に分離 + 永続化は AppearanceModel.didSet 集約。
struct SettingsView: View {
    @ObservedObject var appearance: AppearanceModel

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
                HandThicknessSection(appearance: appearance)
                CircleOutlineThicknessSection(appearance: appearance)
                CustomCircleColorSection(appearance: appearance)
            }
            .padding(20)
        }
        .frame(width: 340, height: 860)
        .tokiGlassBackground(cornerRadius: 12)
    }
}
