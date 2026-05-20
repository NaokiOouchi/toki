import AppKit
import CoreGraphics
import SwiftUI

/// メニューバー常駐と FloatingClockWindow の表示/非表示を司る AppDelegate。
/// Task 14 ではハードコードデータで ClockView を表示する。
/// ViewModel 接続は Task 16 で対応予定（CoreGraphics import もそのとき削除）。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: FloatingClockWindow?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // === ハードコードデータ（Task 16 で ClockViewModel 経由に差し替え予定）===
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)

        // TimeOfDay.clockAngle と同じ規約：0:00 が真上（-π/2）、時計回り。
        // 早朝/夜間で h が負や 24 以上になった場合のオーバーフロー対策として
        // 総分を 0..<1440 にラップしてから角度に変換する。
        func angle(hour h: Int, minute m: Int) -> Double {
            let totalMinutes = h * 60 + m
            let wrapped = ((totalMinutes % 1440) + 1440) % 1440
            let fraction = Double(wrapped) / (24.0 * 60.0)
            return fraction * 2 * .pi - .pi / 2
        }

        // past: 1 時間前 〜 30 分前
        let pastStart = angle(hour: hour - 1, minute: minute)
        let pastEnd = angle(hour: hour, minute: minute - 30)
        // current: 30 分前 〜 30 分後（今を含む）
        let curStart = angle(hour: hour, minute: minute - 30)
        let curEnd = angle(hour: hour, minute: minute + 30)
        // future: 2 時間後 〜 3 時間後
        let futStart = angle(hour: hour + 2, minute: 0)
        let futEnd = angle(hour: hour + 3, minute: 0)

        let hardcodedEvents: [RenderableEvent] = [
            RenderableEvent(
                id: "past",
                title: "過去予定",
                startAngle: pastStart, endAngle: pastEnd,
                color: CGColor(red: 0.85, green: 0.3, blue: 0.3, alpha: 1),
                status: .past,
                externalIdentifier: nil
            ),
            RenderableEvent(
                id: "current",
                title: "進行中の予定",
                startAngle: curStart, endAngle: curEnd,
                color: CGColor(red: 0.3, green: 0.55, blue: 0.85, alpha: 1),
                status: .current,
                externalIdentifier: nil
            ),
            RenderableEvent(
                id: "future",
                title: "次の予定",
                startAngle: futStart, endAngle: futEnd,
                color: CGColor(red: 0.3, green: 0.7, blue: 0.4, alpha: 1),
                status: .future,
                externalIdentifier: nil
            )
        ]

        let timeStr = String(format: "%02d:%02d", hour, minute)
        let centerState: CenterState = .duringEvent(
            time: timeStr,
            title: "進行中の予定",
            remaining: "残り 30分"
        )
        let nextLineState = NextLineState(
            timeHHMM: String(format: "%02d:00", (hour + 2) % 24),
            title: "次の予定"
        )

        let view = ClockView(
            events: hardcodedEvents,
            now: now,
            centerState: centerState,
            nextLineState: nextLineState
        )
        // === ハードコードデータここまで ===

        let w = FloatingClockWindow.make(contentView: view)
        window = w

        // 初回位置：メインスクリーンの右上 16px インセット
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let origin = NSPoint(
                x: visible.maxX - w.frame.width - 16,
                y: visible.maxY - w.frame.height - 16
            )
            w.setFrameOrigin(origin)
        }
        w.orderFrontRegardless()

        // メニューバーアイコン（SF Symbols の clock）
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "clock",
                                     accessibilityDescription: "Toki")
        item.button?.action = #selector(toggleWindow)
        item.button?.target = self
        statusItem = item
    }

    /// メニューバーアイコンクリックで呼ばれる。ウィンドウの表示/非表示をトグルする。
    @objc private func toggleWindow() {
        guard let w = window else { return }
        if w.isVisible {
            w.orderOut(nil)
        } else {
            w.orderFrontRegardless()
        }
    }
}
