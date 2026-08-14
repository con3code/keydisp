//
//  KeyDisp — キーストローク・ビジュアライザ
//  © 2026 con3code
//  Credits: con3code / Kotatsu Rin
//

import AppKit
import Combine
import ServiceManagement
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // delegate を保持し続ける
        objc_setAssociatedObject(app, "appDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        app.run()
    }

    private let settings = AppSettings.shared
    private let model = KeyDisplayModel()
    private lazy var capture = KeyCaptureController(model: model)
    private let mouseHighlight = MouseHighlightController()
    private var overlay: OverlayWindowController!
    private var editHUD: EditHUDPanelController?

    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var guideWindow: NSWindow?

    private var cancellables: Set<AnyCancellable> = []
    private var permissionWatchTimer: Timer?
    private var hotCornerTimer: Timer?
    private var hiddenByHotCorner = false

    // MARK: - ライフサイクル

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = OverlayWindowController(model: model)
        capture.onMouseEvent = { [weak self] type, button in
            self?.mouseHighlight.handle(type: type, buttonNumber: button)
        }

        applyActivationPolicy()
        if settings.showMenuBarIcon { installStatusItem() }
        registerHotKey()
        bindSettings()
        syncLaunchAtLoginState()

        if Permissions.allGranted {
            startCapture()
            if settings.overlayVisible { overlay.show() }
        } else {
            showPermissionGuide()
        }
        startPermissionWatch()
        startHotCornerWatch()

        NotificationCenter.default.addObserver(
            self, selector: #selector(recheckPermissions),
            name: .keyDispRecheckPermissions, object: nil
        )
    }

    /// 設定画面の「再確認」: 権限を確認し直し、キー監視を再起動する
    @objc private func recheckPermissions() {
        capture.stop()
        if Permissions.allGranted {
            if capture.start() {
                if settings.overlayVisible { overlay.show() }
            } else {
                showPermissionGuide()
            }
        } else {
            showPermissionGuide()
        }
    }

    // MARK: - ホットエッジ（画面の下端にカーソルがある間はキー表示を隠す）

    private func startHotCornerWatch() {
        hotCornerTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.tickHotCorner()
        }
    }

    private func tickHotCorner() {
        guard settings.hotCornerHide, settings.overlayVisible, !settings.editMode else {
            if hiddenByHotCorner {
                hiddenByHotCorner = false
                settings.hotCornerSuppressed = false
                if settings.overlayVisible { overlay.show() }
            }
            return
        }
        let atBottom = Self.isMouseAtScreenBottom()
        if atBottom != hiddenByHotCorner {
            hiddenByHotCorner = atBottom
            settings.hotCornerSuppressed = atBottom
            if atBottom {
                // 表示中のエントリも消し、滞在中の新しいキー入力も
                // （KeyCaptureController 側で）処理されないようにする
                model.clearAll()
                overlay.hide()
            } else {
                overlay.show()
            }
        }
    }

    /// カーソルがいずれかの画面の底辺（下端から threshold px 以内）にあるか
    private static func isMouseAtScreenBottom(threshold: CGFloat = 10) -> Bool {
        let loc = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            let f = screen.frame
            guard loc.x >= f.minX - 1, loc.x <= f.maxX + 1,
                  loc.y >= f.minY - 1, loc.y <= f.maxY + 1 else { continue }
            if loc.y <= f.minY + threshold { return true }
        }
        return false
    }

    /// 権限が後から許可された場合（設定画面やシステム設定から直接変更した場合も含めて）、
    /// 自動的にキャプチャを開始する
    private func startPermissionWatch() {
        permissionWatchTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, !self.capture.isRunning, Permissions.allGranted else { return }
            self.startCapture()
            if self.capture.isRunning, self.settings.overlayVisible {
                self.overlay.show()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Dock やメニューバーが非表示でも、Finder から再度開けば設定画面に到達できる
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        capture.stop()
        HotKeyManager.shared.unregister()
    }

    // MARK: - キャプチャ

    private func startCapture() {
        guard !capture.isRunning else { return }
        if !capture.start() {
            showPermissionGuide()
        }
    }

    // MARK: - 設定変更への反応

    private func bindSettings() {
        settings.$showDockIcon
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in
                guard let self else { return }
                if !show && !self.settings.showMenuBarIcon {
                    // 両方非表示は許可しない
                    self.settings.showMenuBarIcon = true
                }
                self.applyActivationPolicy(showDock: show)
            }
            .store(in: &cancellables)

        settings.$showMenuBarIcon
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in
                guard let self else { return }
                if show {
                    self.installStatusItem()
                } else {
                    if !self.settings.showDockIcon {
                        self.warnBothIconsHidden()
                        self.settings.showDockIcon = true
                    }
                    self.removeStatusItem()
                }
            }
            .store(in: &cancellables)

        settings.$launchAtLogin
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.setLaunchAtLogin(enabled)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(settings.$hotKeyKeyCode, settings.$hotKeyModifiers)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.registerHotKey()
            }
            .store(in: &cancellables)

        settings.$overlayVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                guard let self else { return }
                if visible {
                    self.overlay.show()
                } else {
                    self.model.clearAll()
                    if !self.settings.editMode { self.overlay.hide() }
                }
            }
            .store(in: &cancellables)
    }

    private func applyActivationPolicy(showDock: Bool? = nil) {
        let show = showDock ?? settings.showDockIcon
        NSApp.setActivationPolicy(show ? .regular : .accessory)
    }

    private func registerHotKey() {
        HotKeyManager.shared.onHotKey = { [weak self] in
            self?.toggleOverlay()
        }
        HotKeyManager.shared.register(
            keyCode: settings.hotKeyKeyCode,
            carbonModifiers: settings.hotKeyModifiers
        )
    }

    // MARK: - ステータスバー

    private func installStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "keyboard.fill",
                accessibilityDescription: "KeyDisp"
            )
            image?.isTemplate = true
            button.image = image
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private func removeStatusItem() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let toggle = NSMenuItem(title: L("キー表示", "Show Keys"), action: #selector(toggleOverlayAction), keyEquivalent: "")
        toggle.state = settings.overlayVisible ? .on : .off
        menu.addItem(toggle)

        let edit = NSMenuItem(title: L("表示編集モード", "Edit Display Mode"), action: #selector(toggleEditModeAction), keyEquivalent: "")
        edit.state = settings.editMode ? .on : .off
        menu.addItem(edit)

        menu.addItem(NSMenuItem(title: L("表示位置をリセット", "Reset Position & Size"), action: #selector(resetPositionAction), keyEquivalent: ""))
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: L("設定…", "Settings…"), action: #selector(showSettingsAction), keyEquivalent: ",")
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem(title: L("権限設定ガイド…", "Permissions Guide…"), action: #selector(showGuideAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L("KeyDisp について", "About KeyDisp"), action: #selector(showAboutAction), keyEquivalent: ""))
        menu.addItem(.separator())

        let login = NSMenuItem(title: L("ログイン時に起動", "Launch at Login"), action: #selector(toggleLaunchAtLoginAction), keyEquivalent: "")
        login.state = settings.launchAtLogin ? .on : .off
        menu.addItem(login)

        let dock = NSMenuItem(title: L("Dock にアイコンを表示", "Show Dock Icon"), action: #selector(toggleDockIconAction), keyEquivalent: "")
        dock.state = settings.showDockIcon ? .on : .off
        menu.addItem(dock)

        menu.addItem(NSMenuItem(title: L("メニューバーアイコンを隠す", "Hide Menu Bar Icon"), action: #selector(hideMenuBarIconAction), keyEquivalent: ""))
        menu.addItem(.separator())

        let quit = NSMenuItem(title: L("KeyDisp を終了", "Quit KeyDisp"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
    }

    /// ウィンドウを「現在マウスカーソルがある画面」の中央に配置する。
    /// マルチディスプレイでも、操作中の画面の中央あたりに初回表示されるようにする。
    private func centerOnMouseScreen(_ window: NSWindow) {
        let loc = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(loc) }) ?? NSScreen.main else { return }
        let v = screen.visibleFrame
        let f = window.frame
        window.setFrameOrigin(NSPoint(
            x: v.midX - f.width / 2,
            y: v.midY - f.height / 2
        ))
    }

    // MARK: - メニューアクション

    @objc private func toggleOverlayAction() { toggleOverlay() }

    private func toggleOverlay() {
        settings.overlayVisible.toggle()
        if settings.overlayVisible && !capture.isRunning {
            startCapture()
        }
    }

    @objc private func toggleEditModeAction() {
        setEditMode(!settings.editMode)
    }

    private func setEditMode(_ editing: Bool) {
        settings.editMode = editing
        overlay.setEditMode(editing)
        if editing {
            if editHUD == nil {
                editHUD = EditHUDPanelController(settings: settings) { [weak self] in
                    self?.setEditMode(false)
                }
            }
            overlay.show()
            editHUD?.show()
            NSApp.activate(ignoringOtherApps: true)
        } else {
            editHUD?.hide()
            if !settings.overlayVisible {
                overlay.hide()
            }
        }
    }

    @objc private func resetPositionAction() {
        overlay.resetPosition()
    }

    @objc private func showSettingsAction() { showSettings() }

    private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: settings)))
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            centerOnMouseScreen(window)
            settingsWindow = window
        }
        settingsWindow?.title = L("KeyDisp 設定", "KeyDisp Settings")
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showGuideAction() {
        // メニューから意図的に開いた場合は、許可済みでも自動的に閉じない
        showPermissionGuide(autoCloseWhenGranted: false)
    }

    private func showPermissionGuide(autoCloseWhenGranted: Bool = true) {
        let view = PermissionGuideView(
            autoCloseWhenGranted: autoCloseWhenGranted,
            onCompleted: { [weak self] in
                guard let self else { return }
                self.guideWindow?.close()
                self.startCapture()
                if self.settings.overlayVisible { self.overlay.show() }
            },
            onClose: { [weak self] in
                self?.guideWindow?.close()
            }
        )
        let isNew = guideWindow == nil
        if isNew {
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            guideWindow = window
        } else {
            // 自動クローズ設定が呼び出しごとに変わるため、中身は毎回作り直す
            guideWindow?.contentViewController = NSHostingController(rootView: view)
        }
        if isNew { centerOnMouseScreen(guideWindow!) }
        guideWindow?.title = L("KeyDisp の初期設定", "KeyDisp Setup")
        guideWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showAboutAction() {
        if aboutWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            centerOnMouseScreen(window)
            aboutWindow = window
        }
        aboutWindow?.title = L("KeyDisp について", "About KeyDisp")
        aboutWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleLaunchAtLoginAction() {
        settings.launchAtLogin.toggle()
    }

    @objc private func toggleDockIconAction() {
        settings.showDockIcon.toggle()
    }

    @objc private func hideMenuBarIconAction() {
        if !settings.showDockIcon {
            settings.showDockIcon = true
        }
        settings.showMenuBarIcon = false
    }

    private func warnBothIconsHidden() {
        let alert = NSAlert()
        alert.messageText = L("メニューバーと Dock の両方は非表示にできません",
                              "The menu bar icon and Dock icon cannot both be hidden")
        alert.informativeText = L("アプリにアクセスできなくなるのを防ぐため、Dock アイコンを表示します。",
                                  "The Dock icon will be shown so the app remains accessible.")
        alert.alertStyle = .informational
        alert.runModal()
    }

    // MARK: - ログイン時に起動

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("SMAppService error: \(error)")
        }
    }

    private func syncLaunchAtLoginState() {
        let enabled = SMAppService.mainApp.status == .enabled
        if settings.launchAtLogin != enabled {
            settings.launchAtLogin = enabled
        }
    }
}
