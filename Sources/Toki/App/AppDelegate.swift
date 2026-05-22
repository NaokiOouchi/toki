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
    /// 設定パネル（透過率調整）の別ウィンドウ。1 つだけ存続させる。
    private var settingsWindow: NSWindow?
    /// アプリ全体で共有する AppearanceModel。ClockView と SettingsView が同インスタンスを参照する。
    /// spec 011 で導入、設定値は @Published 経由で SwiftUI 標準パターンで再描画される。
    private var appearance: AppearanceModel?

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

        // spec 011: AppearanceModel をアプリ生存期間で 1 インスタンス生成し、
        // ClockView と SettingsView に @ObservedObject で共有する。
        // 全 11 設定軸の永続化は AppearanceModel.@Published の didSet で SettingsStore に集約。
        let appearance = AppearanceModel()
        self.appearance = appearance

        let w = FloatingClockWindow.make(contentView: ClockView(viewModel: vm, appearance: appearance))
        window = w

        // spec 008: 保存フレームの復元（あれば、かつ画面内に表示可能なら）
        // 外部モニタを抜いた等で画面外に行ったフレームは弾き、デフォルト位置にフォールバック。
        if let saved = SettingsStore.shared.windowFrame,
           Self.isFrameVisible(saved) {
            w.setFrame(saved, display: true)
        } else if let screen = NSScreen.main {
            // 初回位置：メインスクリーンの右上 16px インセット
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

        // spec 008: ウィンドウ位置 / サイズの変更を SettingsStore に永続化する（spec 011 で rename）
        // 移動 / リサイズの通知を購読し、その都度 UserDefaults へ書き戻す。
        // didBecomeActiveNotification と同様に [weak self] で参照、強参照ループを防ぐ。
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: w,
            queue: .main
        ) { [weak self] _ in
            guard let w = self?.window else { return }
            SettingsStore.shared.setWindowFrame(w.frame)
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: w,
            queue: .main
        ) { [weak self] _ in
            guard let w = self?.window else { return }
            SettingsStore.shared.setWindowFrame(w.frame)
        }
    }

    /// 終了直前にもウィンドウフレームを保険として保存する。
    /// 通知漏れがあっても最終位置 / サイズを次回起動に持ち越せるようにする。
    func applicationWillTerminate(_ notification: Notification) {
        if let w = window {
            SettingsStore.shared.setWindowFrame(w.frame)
        }
    }

    /// 保存フレームが現在のスクリーン構成内で表示可能かを判定する。
    /// 全 NSScreen の visibleFrame と intersects するなら true。
    /// 外部モニタを抜いた等で画面外に行ったフレームを弾く目的。
    private static func isFrameVisible(_ frame: NSRect) -> Bool {
        for screen in NSScreen.screens {
            if screen.visibleFrame.intersects(frame) {
                return true
            }
        }
        return false
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
            let settingsItem = NSMenuItem(
                title: "設定…",
                action: #selector(handleOpenSettings),
                keyEquivalent: ","
            )
            menu.addItem(settingsItem)
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

    /// 設定パネル（透過率調整）を開く。既に存在すれば前面化のみ。
    /// NSHostingView で SettingsView を載せ、closable な titled window として表示する。
    /// SettingsView 内のサブ View は AppearanceModel に直接 binding するため、
    /// @Published の自動 binding で ClockView 側も即座に再描画される（spec 011）。
    @objc private func handleOpenSettings() {
        if let w = settingsWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let appearance = self.appearance else { return }
        // spec 011 Task 6: SettingsView は AppearanceModel を @ObservedObject で受け取る。
        // 分離済みセクション（Opacity / Theme / ColorScheme / Material）は appearance に
        // 直接バインドし、didSet 経由で SettingsStore に永続化される。
        let view = SettingsView(appearance: appearance)
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 860),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Toki 設定"
        window.contentView = hosting
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow = window
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
