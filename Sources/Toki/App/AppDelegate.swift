import AppKit
import SwiftUI

/// メニューバー常駐と FloatingClockWindow の表示/非表示を司る AppDelegate。
/// Gateway → ViewModel → Window(ClockView) の順で構成し、`vm.start()` で
/// EventKit 権限要求・購読・タイマーを開始する。
/// メニューバーアイコンは左クリックでウィンドウ toggle、右クリックで終了メニュー。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: FloatingClockWindow?
    private var statusItem: NSStatusItem?
    private var gateway: EventKitGateway?
    private var viewModel: ClockViewModel?
    private var oauthClient: GoogleOAuthClient?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // OAuth 依存組み立て：設定ファイルが無ければ nil → 旧挙動を維持。
        let oauth = OAuthConfig.load().map { config in
            GoogleOAuthClient(config: config,
                              keychain: KeychainStore(),
                              receiver: LoopbackOAuthReceiver())
        }
        let googleAPI = oauth.map { GoogleCalendarAPI(oauth: $0) }
        self.oauthClient = oauth

        // 依存の組み立て：Gateway → ViewModel → ClockView。
        let gw = EventKitGateway(googleAPI: googleAPI)
        let vm = ClockViewModel(gateway: gw)
        gateway = gw
        viewModel = vm

        let w = FloatingClockWindow.make(contentView: ClockView(viewModel: vm))
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

        // ViewModel 起動（権限要求 + 購読開始 + タイマー）
        Task { await vm.start() }

        // メニューバーアイコン + 左クリック toggle / 右クリックメニュー
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "clock",
                                     accessibilityDescription: "Toki")
        item.button?.action = #selector(handleStatusBarClick(_:))
        item.button?.target = self
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    /// 左クリック → ウィンドウ toggle、右クリック → コンテキストメニュー（終了）。
    @objc private func handleStatusBarClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            toggleWindow()
        }
    }

    /// メニューバーアイコンクリックで呼ばれる。ウィンドウの表示/非表示をトグルする。
    private func toggleWindow() {
        guard let w = window else { return }
        if w.isVisible {
            w.orderOut(nil)
        } else {
            w.orderFrontRegardless()
        }
    }

    /// 右クリック時の暫定メニュー。Phase 2 で「位置リセット / 再読込」も追加予定。
    /// NSStatusItem に menu を設定するとクリックでメニューが開く性質を利用。
    /// 直後にクリアして、次の左クリックで toggle 動作を維持する。
    /// OAuth 設定が読めた場合のみ、接続状態に応じて「Google Calendar 接続/切断」を出す。
    private func showContextMenu() {
        let menu = NSMenu()

        if let oauth = oauthClient {
            if oauth.isAuthorized {
                menu.addItem(NSMenuItem(
                    title: "Google Calendar 切断",
                    action: #selector(handleDisconnect),
                    keyEquivalent: ""
                ))
            } else {
                menu.addItem(NSMenuItem(
                    title: "Google Calendar 接続",
                    action: #selector(handleConnect),
                    keyEquivalent: ""
                ))
            }
            menu.addItem(NSMenuItem.separator())
        }

        menu.addItem(NSMenuItem(
            title: "Toki を終了",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    /// Google Calendar OAuth 認可フローを開始。ブラウザが立ち上がり同意画面が出る。
    @objc private func handleConnect() {
        Task {
            do {
                try await oauthClient?.beginAuthorization()
            } catch {
                print("OAuth connect failed: \(error)")
            }
        }
    }

    /// Google Calendar 連携を解除。refresh_token を Keychain から削除する。
    @objc private func handleDisconnect() {
        Task {
            do {
                try await oauthClient?.revoke()
            } catch {
                print("OAuth disconnect failed: \(error)")
            }
        }
    }
}
