import SwiftUI

/// 透過率調整の軽量設定 UI。AppDelegate が別 NSWindow で表示する。
/// onChange callback で AppSettings.opacity を即時更新し、
/// NotificationCenter で `.tokiOpacityChanged` を発火、ClockView が購読して反映する。
struct SettingsView: View {
    @State private var opacity: Double = AppSettings.shared.opacity
    var onChange: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("透過率")
                .font(.system(size: 12, weight: .medium))
            Slider(value: $opacity, in: 0.5...1.0)
                .onChange(of: opacity) { _, newValue in
                    AppSettings.shared.opacity = newValue
                    onChange(newValue)
                }
            Text("\(Int(opacity * 100))%")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 260, height: 120)
        // Liquid Glass 適用は Task 12 で。本タスクでは Material 背景に留める。
        .background(Color(NSColor.windowBackgroundColor))
    }
}
