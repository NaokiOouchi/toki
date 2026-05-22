import AppKit
import SwiftUI

/// メニューバー常駐と FloatingClockWindow の表示/非表示を司る AppDelegate。
/// Gateway → ViewModel → Window(ClockView) の順で構成し、`vm.start()` で
/// OAuth 接続状態の取り込み・購読・タイマーを開始する。
/// メニューバーアイコンは左クリックでウィンドウ toggle、右クリックで終了メニュー。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: FloatingClockWindow?
    private var statusItem: NSStatusItem?
    private var gateway: GoogleCalendarGateway?
    private var viewModel: ClockViewModel?
    private var oauthClient: GoogleOAuthClient?
    /// focus reload の最後の実行時刻。30 秒 debounce 用。
    private var lastFocusReloadAt: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // OAuth 依存組み立て：設定ファイルが無ければ nil → 未接続 UX で起動する。
        let oauth = OAuthConfig.load().map { config in
            GoogleOAuthClient(config: config,
                              keychain: KeychainStore(),
                              receiver: LoopbackOAuthReceiver())
        }
        self.oauthClient = oauth

        // 依存の組み立て：OAuth → Gateway → ViewModel → ClockView。
        let gw: GoogleCalendarGateway? = oauth.map { client in
            GoogleCalendarGateway(oauthClient: client,
                                  api: GoogleCalendarAPI(oauth: client))
        }
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

        // ViewModel 起動（OAuth 接続状態の取り込み + 購読開始 + タイマー）
        Task { await vm.start() }

        // メニューバーアイコン + 左クリック toggle / 右クリックメニュー
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "clock",
                                     accessibilityDescription: "Toki")
        item.button?.action = #selector(handleStatusBarClick(_:))
        item.button?.target = self
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        // spec 008: フォアグラウンド復帰時に reload を trigger（30 秒 debounce）
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if let last = self.lastFocusReloadAt,
               Date().timeIntervalSince(last) < 30 {
                return
            }
            self.lastFocusReloadAt = Date()
            Task { await self.viewModel?.handleReload() }
        }
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
            if oauth.isAuthorized {
                let reloadItem = NSMenuItem(
                    title: "再読込",
                    action: #selector(handleReload),
                    keyEquivalent: "r"
                )
                menu.addItem(reloadItem)
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
    /// 成功後は ViewModel の接続状態を即時更新し、Gateway を reload して event を取り込む。
    @objc private func handleConnect() {
        Task {
            await viewModel?.setConnecting(true)
            do {
                try await oauthClient?.beginAuthorization()
                await viewModel?.refreshAuthorizationState()
                await gateway?.reload()
            } catch {
                print("OAuth connect failed: \(error)")
            }
            await viewModel?.setConnecting(false)
        }
    }

    /// 右クリックメニューの「再読込」から呼ばれる。ViewModel 経由で gateway.reload() を実行。
    @objc private func handleReload() {
        Task { await viewModel?.handleReload() }
    }

    /// Google Calendar 連携を解除。refresh_token を Keychain から削除する。
    /// 解除後は ViewModel の接続状態を即時更新し、Gateway を reload して空 timeline に戻す。
    @objc private func handleDisconnect() {
        Task {
            do {
                try await oauthClient?.revoke()
                await viewModel?.refreshAuthorizationState()
                await gateway?.reload()
            } catch {
                print("OAuth disconnect failed: \(error)")
            }
        }
    }
}
