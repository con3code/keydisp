import AppKit
import SwiftUI

/// キー表示を載せる透明フローティングパネル。
/// 全スペース・フルスクリーン上・セカンドディスプレイでも表示でき、
/// 編集モード中のみマウス操作を受け付ける。
/// 編集モード中は枠の内側ドラッグで移動、枠の端ドラッグで矩形を直接リサイズできる。
final class OverlayWindowController: NSObject, NSWindowDelegate {
    private static let frameKey = "OverlayWindowFrame"
    static let defaultSize = NSSize(width: 620, height: 440)

    let panel: NSPanel
    private let settings: AppSettings

    init(model: KeyDisplayModel, settings: AppSettings = .shared) {
        self.settings = settings

        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        // isFloatingPanel はウィンドウレベルを .floating に上書きするため、必ずその後に設定する
        panel.level = .statusBar
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.contentMinSize = NSSize(width: 240, height: 150)
        panel.delegate = self

        let root = OverlayRootView(model: model, settings: settings)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: Self.defaultSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        restoreFrame()
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func setEditMode(_ editing: Bool) {
        panel.ignoresMouseEvents = !editing
        if editing {
            panel.orderFrontRegardless()
        }
    }

    /// 位置とサイズをメインスクリーン左下のデフォルト状態へ戻す。
    /// サイズは現在の表示倍率を考慮して決める（大きな倍率でも表示が収まるように）。
    func resetPosition() {
        guard let screen = NSScreen.main else { return }
        let v = screen.visibleFrame
        let scale = max(1, settings.displayScale)
        var size = NSSize(
            width: Self.defaultSize.width * scale,
            height: Self.defaultSize.height * scale
        )
        size.width = min(size.width, v.width - 80)
        size.height = min(size.height, v.height - 80)
        panel.setFrame(
            NSRect(origin: NSPoint(x: v.minX + 40, y: v.minY + 40), size: size),
            display: true
        )
        saveFrame()
    }

    // MARK: - フレームの保存/復元（マルチディスプレイ対応: 画面外なら戻す）

    private func restoreFrame() {
        if let s = UserDefaults.standard.string(forKey: Self.frameKey) {
            let rect = NSRectFromString(s)
            if !rect.isEmpty, NSScreen.screens.contains(where: { $0.frame.intersects(rect) }) {
                panel.setFrame(rect, display: false)
                return
            }
        }
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.minX + 40, y: f.minY + 40))
        }
    }

    private func saveFrame() {
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: Self.frameKey)
    }

    func windowDidMove(_ notification: Notification) {
        saveFrame()
    }

    func windowDidResize(_ notification: Notification) {
        saveFrame()
    }
}
